import Combine
import Foundation
import SwiftData
import SwiftUI

// swiftlint:disable file_length type_body_length

extension Notification.Name {
    static let memberProfileDidChange = Notification.Name("HousePulse.memberProfileDidChange")
    static let taskBoardDataDidChange = Notification.Name("HousePulse.taskBoardDataDidChange")
    static let backlogDataDidChange = Notification.Name("HousePulse.backlogDataDidChange")
    static let shoppingListDataDidChange = Notification.Name("HousePulse.shoppingListDataDidChange")
    static let householdDataDidChange = Notification.Name("HousePulse.householdDataDidChange")
    static let tabBarAppearanceRefreshRequested = Notification.Name("HousePulse.tabBarAppearanceRefreshRequested")
}

struct StoreContextSaveError: LocalizedError {
    let store: String
    let operation: String
    let sourceFile: String
    let sourceLine: UInt
    let underlying: Error

    var errorDescription: String? {
        "Could not save local changes in \(store)."
    }
}

enum StoreContextSaver {
    @discardableResult
    static func saveContextOrSetError(
        _ context: ModelContext?,
        store: String,
        operation: String,
        file: StaticString = #fileID,
        line: UInt = #line,
        setError: (Error) -> Void
    ) -> Bool {
        guard let context else { return true }

        do {
            try context.save()
            return true
        } catch {
            let wrapped = StoreContextSaveError(
                store: store,
                operation: operation,
                sourceFile: String(describing: file),
                sourceLine: line,
                underlying: error
            )
            print(
                "[\(store)] save failed during \(operation) at \(file):\(line) - \(error.localizedDescription)"
            )
            setError(wrapped)
            return false
        }
    }
}

/// Main store for task management with offline-first architecture.
/// Follows ADR-002: optimistic UI updates with background sync.
@MainActor
final class TaskStore: ObservableObject {
    private enum TaskSyncStatus {
        static let synced = "synced"
        static let pendingUpload = "pendingUpload"
        static let pendingDelete = "pendingDelete"
        static let awaitingCloudEcho = "awaitingCloudEcho"
    }

    private struct CachedBacklogItemSnapshot {
        var item: BacklogItem
        var syncStatusRaw: String
        var lastSyncedAt: Date?
    }

    @Published private(set) var tasks: [Task] = []
    @Published private(set) var hasHydratedLocalSnapshot = false
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingInBackground = false
    @Published private(set) var error: Error?
    @Published private(set) var pendingTaskMutations: Set<UUID> = []

    private lazy var cloudKit = CloudKitManager.shared
    private lazy var notificationService = NotificationService.shared
    private let modelContext: ModelContext
    private var householdId: UUID?
    private var syncMode: SyncMode = .cloud
    private var currentUserId: String?
    private var householdOwnerId: String?
    private var isReplayingPendingMutations = false
    private var shouldReplayPendingMutationsAfterCurrentPass = false
    private var activeLoadTask: _Concurrency.Task<Void, Never>?
    private var shouldReloadAfterCurrentLoad = false
    private var hasHydratedVisibleSnapshot = false
    private var needsLocalRehydrate = false

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
    }

    func setCloudContext(currentUserId: String?, householdOwnerId: String?) {
        self.currentUserId = currentUserId
        self.householdOwnerId = householdOwnerId
    }

    private var isCloudSyncEnabled: Bool {
        syncMode == .cloud
    }

    private var cloudScope: CloudKitManager.HouseholdDatabaseScope {
        guard let currentUserId, let householdOwnerId else {
            return .participantShared
        }
        return currentUserId == householdOwnerId ? .ownerPrivate : .participantShared
    }

    /// Default recommended WIP limit per user.
    static let defaultRecommendedWipLimit = 3

    /// Recommended WIP limit per user (soft limit, configurable in Settings).
    static var recommendedWipLimit: Int {
        let stored = UserDefaults.standard.integer(forKey: "recommendedWipLimit")
        if stored <= 0 {
            return defaultRecommendedWipLimit
        }
        return min(max(stored, 1), 7)
    }

    struct PendingSyncSnapshot {
        var pendingUploadByID: [UUID: Task]
        var pendingDeleteIDs: Set<UUID>
        var pendingDeleteLogicalItemIDs: Set<UUID>
    }

    /// Backward-compatible alias used in older call sites/tests.
    static var wipLimit: Int {
        recommendedWipLimit
    }

    enum NextTransitionValidation: Equatable {
        case ok
        case assigneeRequired
        case wipLimitReached(current: Int, limit: Int)
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    private func saveContextOrSetError(
        operation: String = "persist task cache",
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        StoreContextSaver.saveContextOrSetError(
            modelContext,
            store: "TaskStore",
            operation: operation,
            file: file,
            line: line
        ) { [self] saveError in
            error = saveError
        }
    }

    private func syncReminder(for task: Task) async {
        if task.dueDate != nil, !notificationService.isAuthorized {
            await notificationService.requestAuthorization()
        }

        if task.dueDate == nil || task.status == .done {
            await notificationService.removeTaskReminder(for: task)
        } else {
            await notificationService.scheduleTaskReminder(for: task)
        }
    }

    private func syncDailyDigestSchedule() async {
        await notificationService.refreshDailyDigest(
            householdId: householdId,
            modelContext: modelContext
        )
    }

    // MARK: - Computed Properties

    var backlogTasks: [Task] {
        tasks.filter { $0.status == .backlog }
            .sorted(by: Self.activeTaskSort)
    }

    var nextTasks: [Task] {
        tasks.filter { $0.status == .next }
            .sorted(by: Self.activeTaskSort)
    }

    var doneTasks: [Task] {
        tasks.filter { $0.status == .done }
            .sorted(by: Self.completedTaskSort)
    }

    /// Recently completed tasks shown on Tasks tab (last 24h).
    var recentlyDoneTasks: [Task] {
        doneTasks.filter { task in
            guard let completedAt = task.completedAt else { return true }
            return completedAt > Date().addingTimeInterval(-86400)
        }
    }

    /// Archived completed tasks shown in More -> Completed Tasks (older than 24h).
    var archivedDoneTasks: [Task] {
        doneTasks.filter { task in
            guard let completedAt = task.completedAt else { return false }
            return completedAt <= Date().addingTimeInterval(-86400)
        }
    }

    /// Validate if task can enter "Next" state.
    func validateNextTransition(assigneeId: UUID?, excludingTaskId: UUID? = nil) -> NextTransitionValidation {
        guard let assigneeId else { return .assigneeRequired }
        _ = excludingTaskId
        _ = assigneeId
        // Soft limit: transitions are allowed; UI communicates overload via color zones.
        return .ok
    }

    /// Count of active Next tasks for a specific assignee.
    func nextTaskCount(for assigneeId: UUID) -> Int {
        tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
    }

    /// Backward-compatible helper for legacy call sites.
    func canMoveToNext(assigneeId: UUID?, excludingTaskId: UUID? = nil) -> Bool {
        validateNextTransition(assigneeId: assigneeId, excludingTaskId: excludingTaskId) == .ok
    }

    func completedTaskCountThisWeek(
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let referenceComponents = calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: referenceDate
        )

        return tasks.filter { task in
            guard task.status == .done else { return false }

            let completionDate = task.completedAt ?? task.updatedAt
            let completionComponents = calendar.dateComponents(
                [.yearForWeekOfYear, .weekOfYear],
                from: completionDate
            )

            return completionComponents.weekOfYear == referenceComponents.weekOfYear &&
                completionComponents.yearForWeekOfYear == referenceComponents.yearForWeekOfYear
        }.count
    }

    // MARK: - Data Loading

    func setHousehold(_ id: UUID) {
        let didChangeHousehold = householdId != id
        householdId = id
        if didChangeHousehold {
            hasHydratedVisibleSnapshot = false
            hasHydratedLocalSnapshot = false
            needsLocalRehydrate = false
        }
        hydrateVisibleSnapshotFromCacheIfNeeded(
            force: didChangeHousehold || shouldForceVisibleHydration()
        )
    }

    func loadTasksForDisplay() async {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: shouldForceVisibleHydration())
        guard isCloudSyncEnabled else { return }
        scheduleBackgroundRefresh()
    }

    func loadTasks() async {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: shouldForceVisibleHydration())
        guard isCloudSyncEnabled else {
            await notificationService.refreshScheduledNotifications(
                householdId: householdId,
                modelContext: modelContext
            )
            return
        }
        let loadTask = ensureBackgroundRefreshTask()
        await loadTask.value
    }

    private func scheduleBackgroundRefresh() {
        _ = ensureBackgroundRefreshTask()
    }

    private func ensureBackgroundRefreshTask() -> _Concurrency.Task<Void, Never> {
        if let activeLoadTask {
            shouldReloadAfterCurrentLoad = true
            return activeLoadTask
        }

        let loadTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }

            repeat {
                shouldReloadAfterCurrentLoad = false
                await performLoadTasksPass()
            } while shouldReloadAfterCurrentLoad

            activeLoadTask = nil
        }

        activeLoadTask = loadTask
        return loadTask
    }

    private func performLoadTasksPass() async {
        guard let householdId else { return }

        isLoading = true
        isRefreshingInBackground = true
        error = nil
        defer {
            isLoading = false
            isRefreshingInBackground = false
        }

        // First, load from local cache
        hydrateVisibleSnapshotFromCacheIfNeeded(force: shouldForceVisibleHydration())

        if !isCloudSyncEnabled {
            await notificationService.refreshScheduledNotifications(
                householdId: householdId,
                modelContext: modelContext
            )
            return
        }

        // Then sync with CloudKit
        do {
            // Ensure CloudKit is ready before accessing
            await cloudKit.ensureReady()
            let cloudTasks = try await cloudKit.fetchTasks(
                householdId: householdId,
                scope: cloudScope
            )
            let latestCachedTasks = fetchCachedTasks(updateVisibleState: false)
            let latestPendingSnapshot = pendingSyncSnapshot(from: latestCachedTasks)
            tasks = mergeCloudSnapshot(cloudTasks, with: latestPendingSnapshot)
            syncToCache(cloudTasks, cloudTaskIDs: Set(cloudTasks.map(\.id)))
            replayPendingMutationsInBackground()
        } catch {
            // If CloudKit fails, we already have cached data
            self.error = error
        }

        await notificationService.refreshScheduledNotifications(
            householdId: householdId,
            modelContext: modelContext
        )
    }

    private func hydrateVisibleSnapshotFromCacheIfNeeded(force: Bool = false) {
        _ = fetchCachedTasks(updateVisibleState: force || shouldForceVisibleHydration())
    }

    private func fetchCachedTasks(updateVisibleState: Bool) -> [CachedTask] {
        guard let householdId else {
            if updateVisibleState {
                tasks = []
                hasHydratedVisibleSnapshot = true
                hasHydratedLocalSnapshot = true
                needsLocalRehydrate = false
            }
            return []
        }

        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cached = (try? modelContext.fetch(descriptor)) ?? []
        if updateVisibleState {
            tasks = deduplicatedVisibleTasks(from: cached)
            hasHydratedVisibleSnapshot = true
            hasHydratedLocalSnapshot = true
            needsLocalRehydrate = false
        }
        return cached
    }

    func markLocalSnapshotStale() {
        needsLocalRehydrate = true
    }

    func rehydrateVisibleSnapshotFromCache() {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: true)
    }

    func replayPendingMutationsIfNeeded() {
        guard isCloudSyncEnabled else { return }
        replayPendingMutationsInBackground()
    }

    func syncToCache(_ cloudTasks: [Task], cloudTaskIDs _: Set<UUID>) {
        guard let householdId else { return }

        let cacheDescriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedTasks = (try? modelContext.fetch(cacheDescriptor)) ?? []
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedTasks.map { ($0.id, $0) })
        let cachedByLogicalID = canonicalCachedTasksByLogicalItemID(cachedTasks)
        let tombstonedTaskIDs = Set(
            cachedTasks.compactMap { cachedTask in
                cachedTask.syncStatusRaw == TaskSyncStatus.pendingDelete ? cachedTask.id : nil
            }
        )
        let tombstonedTaskLogicalIDs = Set(
            cachedTasks.compactMap { cachedTask in
                cachedTask.syncStatusRaw == TaskSyncStatus.pendingDelete
                    ? resolvedLogicalItemID(for: cachedTask) : nil
            }
        )
        let resolvedCloudTasks = deduplicatedCloudTasks(cloudTasks)

        // Update local cache with cloud data
        for task in resolvedCloudTasks {
            if tombstonedTaskIDs.contains(task.id) || tombstonedTaskLogicalIDs.contains(task.logicalItemID) {
                continue
            }
            if let existing = cachedByID[task.id] {
                if existing.syncStatusRaw == TaskSyncStatus.pendingDelete {
                    continue
                }
                if existing.syncStatusRaw == TaskSyncStatus.pendingUpload ||
                    existing.syncStatusRaw == TaskSyncStatus.awaitingCloudEcho
                {
                    let localTask = existing.toTask()
                    guard cloudTaskMatchesLocalMutationEcho(task, localTask: localTask) else {
                        continue
                    }
                }
                existing.update(from: task)
                existing.syncStatusRaw = TaskSyncStatus.synced
                existing.lastSyncedAt = Date()
            } else if let lineageExisting = cachedByLogicalID[task.logicalItemID] {
                if lineageExisting.syncStatusRaw == TaskSyncStatus.pendingDelete {
                    continue
                }
                if lineageExisting.syncStatusRaw == TaskSyncStatus.pendingUpload ||
                    lineageExisting.syncStatusRaw == TaskSyncStatus.awaitingCloudEcho
                {
                    let localTask = lineageExisting.toTask()
                    guard cloudTaskMatchesLocalMutationEcho(task, localTask: localTask) else {
                        continue
                    }
                }
                guard shouldReplaceTaskLineageConflict(with: task, existing: lineageExisting.toTask()) else {
                    continue
                }
                modelContext.delete(lineageExisting)
                let cached = CachedTask(from: task)
                cached.syncStatusRaw = TaskSyncStatus.synced
                cached.lastSyncedAt = Date()
                modelContext.insert(cached)
            } else {
                let cached = CachedTask(from: task)
                cached.syncStatusRaw = TaskSyncStatus.synced
                cached.lastSyncedAt = Date()
                modelContext.insert(cached)
            }
        }
        saveContextOrSetError(operation: "sync tasks cache from cloud")
    }

    private func replayPendingMutationsInBackground() {
        if isReplayingPendingMutations {
            shouldReplayPendingMutationsAfterCurrentPass = true
            return
        }
        isReplayingPendingMutations = true

        _ = _Concurrency.Task(priority: .utility) { [self] in
            while true {
                shouldReplayPendingMutationsAfterCurrentPass = false
                await flushPendingSync()
                if !shouldReplayPendingMutationsAfterCurrentPass {
                    break
                }
            }
            isReplayingPendingMutations = false
        }
    }

    private func flushPendingSync() async {
        guard isCloudSyncEnabled, householdId != nil else { return }

        let cachedTasks = fetchCachedTasksForCurrentHousehold()
        let pendingUploads = cachedTasks.filter { $0.syncStatusRaw == TaskSyncStatus.pendingUpload }
        let pendingDeletes = cachedTasks.filter { $0.syncStatusRaw == TaskSyncStatus.pendingDelete }

        guard !pendingUploads.isEmpty || !pendingDeletes.isEmpty else { return }

        var didMutateCache = false

        for cached in pendingUploads where !pendingTaskMutations.contains(cached.id) {
            do {
                _ = try await cloudKit.saveTask(cached.toTask(), scope: cloudScope)
                cached.syncStatusRaw = TaskSyncStatus.awaitingCloudEcho
                cached.lastSyncedAt = Date()
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        for cached in pendingDeletes where !pendingTaskMutations.contains(cached.id) {
            do {
                try await cloudKit.deleteTask(
                    id: cached.id,
                    householdId: cached.householdId,
                    scope: cloudScope
                )
                modelContext.delete(cached)
                tasks.removeAll { $0.id == cached.id }
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        if didMutateCache {
            saveContextOrSetError(operation: "flush pending task sync mutations")
        }
    }

    // MARK: - Task Operations

    func canPoke(
        task: Task,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let lastPokedAt = task.lastPokedAt else { return true }
        return !calendar.isDate(lastPokedAt, inSameDayAs: now)
    }

    @discardableResult
    func pokeTask(
        _ task: Task,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return false }

        let currentTask = tasks[index]
        let assignedIDs = Set(
            currentTask.assigneeIds + (currentTask.assigneeId.map { [$0] } ?? [])
        )
        guard !assignedIDs.isEmpty else { return false }
        guard !pendingTaskMutations.contains(currentTask.id) else { return false }
        guard canPoke(task: currentTask, now: now, calendar: calendar) else { return false }

        beginMutation(currentTask.id)
        defer { endMutation(currentTask.id) }

        var updatedTask = currentTask
        updatedTask.lastPokedAt = now
        updatedTask.updatedAt = now
        tasks[index] = updatedTask

        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == updatedTask.id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.update(from: updatedTask)
            cached.syncStatusRaw = isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : now
            saveContextOrSetError(operation: "cache poked task")
        } else {
            let cached = CachedTask(from: updatedTask)
            cached.syncStatusRaw = isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : now
            modelContext.insert(cached)
            saveContextOrSetError(operation: "cache inserted poked task")
        }

        guard isCloudSyncEnabled else { return true }

        replayPendingMutationsInBackground()
        return true
    }

    @discardableResult
    func createTask(
        taskId: UUID = UUID(),
        logicalItemID: UUID? = nil,
        title: String,
        status: Task.TaskStatus = .backlog,
        assigneeId: UUID? = nil,
        assigneeIds: [UUID] = [],
        backlogCategoryId: UUID? = nil,
        areaId: UUID? = nil,
        dueDate: Date? = nil,
        notes: String? = nil,
        taskType: Task.TaskType = .oneOff,
        recurringChoreId: UUID? = nil,
        order: Int? = nil
    ) async -> NextTransitionValidation {
        guard let householdId else { return .ok }

        let resolvedPrimaryAssigneeId = assigneeId ?? assigneeIds.first

        // Tasks shown on the execution board must stay assigned.
        if status != .backlog {
            let validation = validateNextTransition(assigneeId: resolvedPrimaryAssigneeId)
            guard validation == .ok else {
                error = validation.taskStoreError
                return validation
            }
        }

        let resolvedAssigneeIds: [UUID] = if !assigneeIds.isEmpty {
            assigneeIds
        } else if let assigneeId {
            [assigneeId]
        } else {
            []
        }

        let resolvedOrder: Int = if status == .next {
            order ?? (nextTaskOrderBaseline() + 1)
        } else {
            order ?? 0
        }

        let task = Task(
            id: taskId,
            logicalItemID: logicalItemID,
            householdId: householdId,
            title: title,
            status: status,
            assigneeId: assigneeId,
            assigneeIds: resolvedAssigneeIds,
            backlogCategoryId: backlogCategoryId,
            areaId: areaId,
            dueDate: dueDate,
            taskType: taskType,
            recurringChoreId: recurringChoreId,
            notes: notes,
            order: resolvedOrder
        )

        // Optimistic UI update
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            tasks.append(task)
        }

        // Save to cache
        let cached = CachedTask(from: task)
        cached.syncStatusRaw = isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced
        cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
        modelContext.insert(cached)
        saveContextOrSetError(operation: "cache created task")

        // Fire-and-forget: notification scheduling must not block the caller.
        // Promotion flow (promoteItemToTask) awaits createTask before removing the
        // idea from the UI. Blocking here causes a visible ~13-second delay.
        _ = _Concurrency.Task { [self] in
            await syncReminder(for: task)
            await syncDailyDigestSchedule()
        }

        if isCloudSyncEnabled {
            replayPendingMutationsInBackground()
        }
        return .ok
    }

    @discardableResult
    func updateTask(_ task: Task) async -> NextTransitionValidation {
        var updatedTask = task
        updatedTask.updatedAt = Date()
        beginMutation(updatedTask.id)
        defer { endMutation(updatedTask.id) }

        // Tasks outside backlog must keep a concrete assignee.
        let resolvedAssigneeId = task.assigneeId ?? task.assigneeIds.first
        if task.status != .backlog {
            let validation = validateNextTransition(
                assigneeId: resolvedAssigneeId,
                excludingTaskId: task.id
            )
            guard validation == .ok else {
                error = validation.taskStoreError
                return validation
            }
        }

        // Optimistic UI update
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = updatedTask
        }

        // Update cache
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == task.id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.update(from: updatedTask)
            cached.syncStatusRaw = isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            saveContextOrSetError(operation: "cache updated task")
        } else {
            let cached = CachedTask(from: updatedTask)
            cached.syncStatusRaw = isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            modelContext.insert(cached)
            saveContextOrSetError(operation: "cache inserted updated task")
        }

        await syncReminder(for: updatedTask)
        await syncDailyDigestSchedule()

        if isCloudSyncEnabled {
            replayPendingMutationsInBackground()
        }
        return .ok
    }

    @discardableResult
    func moveTask(_ task: Task, to status: Task.TaskStatus) async -> NextTransitionValidation {
        var updatedTask = task
        updatedTask.status = status
        updatedTask.updatedAt = Date()

        if status == .done {
            updatedTask.completedAt = Date()
        } else if task.status == .done {
            updatedTask.completedAt = nil
        }

        if status == .next, task.status != .next {
            updatedTask.order = nextTaskOrderBaseline() + 1
        }

        return await updateTask(updatedTask)
    }

    @discardableResult
    func toggleTaskCompletion(_ task: Task) async -> NextTransitionValidation {
        let newStatus: Task.TaskStatus = task.status == .done ? .next : .done
        return await moveTask(task, to: newStatus)
    }

    @discardableResult
    func moveTaskToIdeas(_ task: Task, destinationCategoryId: UUID) async -> Bool {
        guard let householdId else { return false }
        let existingDestination = existingDestinationBacklogItem(for: task.logicalItemID)
        let previousDestinationSnapshot = existingDestination.flatMap {
            cachedBacklogItemSnapshot(for: $0.id)
        }
        let backlogItem = demotedBacklogDestination(
            from: task,
            destinationCategoryId: destinationCategoryId,
            householdId: householdId,
            existing: existingDestination
        )
        let shouldSyncDestinationInBackground = true

        guard existingDestination != nil || !pendingTaskMutations.contains(task.id) else { return false }

        beginMutation(task.id)
        defer { endMutation(task.id) }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            tasks.removeAll { $0.id == task.id }
        }

        upsertCachedBacklogItem(
            backlogItem,
            syncStatusRaw: isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced,
            lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
            shouldSave: false
        )

        if isCloudSyncEnabled {
            markCachedTaskPendingDelete(task, shouldSave: false)
        } else {
            removeCachedTask(id: task.id, shouldSave: false)
        }

        guard saveContextOrSetError(operation: "move task to ideas locally") else {
            restoreTaskLocally(task)
            if let previousDestinationSnapshot {
                restoreCachedBacklogItem(previousDestinationSnapshot, shouldSave: false)
            } else {
                removeCachedBacklogItem(id: backlogItem.id, shouldSave: false)
            }
            _ = saveContextOrSetError(operation: "rollback move task to ideas")
            return false
        }

        NotificationCenter.default.post(name: .backlogDataDidChange, object: nil)
        NotificationCenter.default.post(name: .taskBoardDataDidChange, object: nil)

        await notificationService.removeTaskReminder(for: task)
        await syncDailyDigestSchedule()

        if isCloudSyncEnabled {
            if shouldSyncDestinationInBackground {
                syncDemotedTaskDestinationInBackground(backlogItem)
            }
            replayPendingMutationsInBackground()
        }

        return true
    }

    func archiveTask(_ task: Task) async {
        guard task.status == .done else { return }
        var archivedTask = task
        archivedTask.completedAt = Date().addingTimeInterval(-86401)
        _ = await updateTask(archivedTask)
    }

    func deleteTask(_ task: Task) async {
        beginMutation(task.id)
        defer { endMutation(task.id) }

        // Optimistic UI update
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            tasks.removeAll { $0.id == task.id }
        }

        if !isCloudSyncEnabled {
            removeCachedTask(id: task.id)
            await notificationService.removeTaskReminder(for: task)
            await syncDailyDigestSchedule()
            return
        }

        markCachedTaskPendingDelete(task)
        await notificationService.removeTaskReminder(for: task)
        await syncDailyDigestSchedule()
        replayPendingMutationsInBackground()
    }

    func removeTaskLocally(_ task: Task) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            tasks.removeAll { $0.id == task.id }
        }
        markCachedTaskPendingDelete(task)
        _ = _Concurrency.Task {
            await self.syncDailyDigestSchedule()
        }
    }

    func restoreTaskLocally(_ task: Task) {
        guard tasks.contains(where: { $0.id == task.id }) == false else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            tasks.append(task)
        }
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == task.id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.update(from: task)
            cached.syncStatusRaw = TaskSyncStatus.pendingUpload
            cached.lastSyncedAt = nil
        } else {
            let cached = CachedTask(from: task)
            cached.syncStatusRaw = TaskSyncStatus.pendingUpload
            cached.lastSyncedAt = nil
            modelContext.insert(cached)
        }
        saveContextOrSetError(operation: "restore task locally")
        _ = _Concurrency.Task {
            await self.syncDailyDigestSchedule()
        }
    }

    func deleteTaskRemote(id: UUID, householdId: UUID) async throws {
        try await cloudKit.deleteTask(id: id, householdId: householdId, scope: cloudScope)
        removeCachedTask(id: id)
    }

    func reorderActiveTasks(
        from source: IndexSet,
        to destination: Int,
        visibleTaskIDs: [UUID]
    ) async {
        let visibleActiveTasks = visibleTaskIDs.compactMap { id in
            tasks.first(where: { $0.id == id && $0.status == .next })
        }
        guard !visibleActiveTasks.isEmpty else { return }

        var reorderedVisibleTasks = visibleActiveTasks
        reorderedVisibleTasks.move(fromOffsets: source, toOffset: destination)

        let hiddenActiveTasks = tasks
            .filter { $0.status == .next && !visibleTaskIDs.contains($0.id) }
            .sorted(by: Self.activeTaskSort)

        let finalActiveOrder = reorderedVisibleTasks + hiddenActiveTasks
        let updatedAt = Date()
        var updatedByID: [UUID: Task] = [:]

        for (index, task) in finalActiveOrder.enumerated() {
            if task.order != index {
                var updatedTask = task
                updatedTask.order = index
                updatedTask.updatedAt = updatedAt
                updatedByID[updatedTask.id] = updatedTask
            }
        }

        guard !updatedByID.isEmpty else { return }

        let updatedIDs = Array(updatedByID.keys)
        updatedIDs.forEach(beginMutation)
        defer { updatedIDs.forEach(endMutation) }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            for index in tasks.indices {
                if let updatedTask = updatedByID[tasks[index].id] {
                    tasks[index] = updatedTask
                }
            }
        }

        for updatedTask in updatedByID.values {
            let descriptor = FetchDescriptor<CachedTask>(
                predicate: #Predicate { $0.id == updatedTask.id }
            )
            if let cached = try? modelContext.fetch(descriptor).first {
                cached.update(from: updatedTask)
                cached.syncStatusRaw = isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced
                cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            } else {
                let cached = CachedTask(from: updatedTask)
                cached.syncStatusRaw = isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced
                cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
                modelContext.insert(cached)
            }
        }
        saveContextOrSetError(operation: "persist reordered tasks")

        guard isCloudSyncEnabled else { return }
        replayPendingMutationsInBackground()
    }

    /// Clears completed tasks.
    /// - Parameter keepingDays:
    ///   - `nil`: delete all completed tasks.
    ///   - number: keep tasks from last N days, delete older completed tasks.
    func clearCompletedTasks(keepingDays: Int?) async {
        let retentionCutoff = keepingDays.map { Date().addingTimeInterval(-Double($0) * 86400) }

        let tasksToDelete = tasks.filter { task in
            guard task.status == .done else { return false }
            guard let retentionCutoff else { return true }
            let completedDate = task.completedAt ?? task.updatedAt
            return completedDate < retentionCutoff
        }

        guard !tasksToDelete.isEmpty else { return }
        await deleteTasksBatch(tasksToDelete)
    }

    /// Clears archived done tasks (older than 24h).
    /// - Parameter keepingDays:
    ///   - `nil`: delete all archived tasks.
    ///   - number: keep tasks from last N days, delete older archived tasks.
    func clearArchivedTasks(keepingDays: Int?) async {
        let archiveCutoff = Date().addingTimeInterval(-86400)
        let retentionCutoff = keepingDays.map { Date().addingTimeInterval(-Double($0) * 86400) }

        let tasksToDelete = tasks.filter { task in
            guard task.status == .done, let completedAt = task.completedAt else { return false }
            guard completedAt <= archiveCutoff else { return false }

            if let retentionCutoff {
                return completedAt < retentionCutoff
            }
            return true
        }

        guard !tasksToDelete.isEmpty else { return }
        await deleteTasksBatch(tasksToDelete)
    }

    private func deleteTasksBatch(_ tasksToDelete: [Task]) async {
        guard !tasksToDelete.isEmpty else { return }
        let taskIDs = Set(tasksToDelete.map(\.id))

        taskIDs.forEach(beginMutation)
        defer { taskIDs.forEach(endMutation) }

        withAnimation(.easeOut(duration: 0.16)) {
            tasks.removeAll { taskIDs.contains($0.id) }
        }

        if !isCloudSyncEnabled {
            batchDeleteCachedTasks(ids: taskIDs)
            for task in tasksToDelete {
                await notificationService.removeTaskReminder(for: task)
            }
            await syncDailyDigestSchedule()
            return
        }

        markCachedTasksPendingDelete(tasksToDelete)
        for task in tasksToDelete {
            await notificationService.removeTaskReminder(for: task)
        }
        await syncDailyDigestSchedule()
        replayPendingMutationsInBackground()
    }

    private func markCachedTasksPendingDelete(_ tasksToDelete: [Task]) {
        guard !tasksToDelete.isEmpty else { return }
        let cachedTasks = fetchCachedTasksForCurrentHousehold()
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedTasks.map { ($0.id, $0) })

        for task in tasksToDelete {
            if let cached = cachedByID[task.id] {
                cached.syncStatusRaw = TaskSyncStatus.pendingDelete
                cached.lastSyncedAt = nil
            } else {
                let cached = CachedTask(from: task)
                cached.syncStatusRaw = TaskSyncStatus.pendingDelete
                cached.lastSyncedAt = nil
                modelContext.insert(cached)
            }
        }
        saveContextOrSetError(operation: "batch mark tasks pending delete")
    }

    private func batchDeleteCachedTasks(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let cachedTasks = fetchCachedTasksForCurrentHousehold()
        for cached in cachedTasks where ids.contains(cached.id) {
            modelContext.delete(cached)
        }
        saveContextOrSetError(operation: "batch remove cached tasks")
    }

    private func fetchCachedTasksForCurrentHousehold() -> [CachedTask] {
        if let householdId {
            let descriptor = FetchDescriptor<CachedTask>(
                predicate: #Predicate { $0.householdId == householdId }
            )
            return (try? modelContext.fetch(descriptor)) ?? []
        }

        let descriptor = FetchDescriptor<CachedTask>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func beginMutation(_ id: UUID) {
        pendingTaskMutations.insert(id)
    }

    private func endMutation(_ id: UUID) {
        pendingTaskMutations.remove(id)
    }

    private func markCachedTaskPendingDelete(_ task: Task) {
        markCachedTaskPendingDelete(task, shouldSave: true)
    }

    private func markCachedTaskPendingDelete(_ task: Task, shouldSave: Bool) {
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == task.id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.syncStatusRaw = TaskSyncStatus.pendingDelete
            cached.lastSyncedAt = nil
            if shouldSave {
                saveContextOrSetError(operation: "mark cached task pending delete")
            }
            return
        }

        let cached = CachedTask(from: task)
        cached.syncStatusRaw = TaskSyncStatus.pendingDelete
        cached.lastSyncedAt = nil
        modelContext.insert(cached)
        if shouldSave {
            saveContextOrSetError(operation: "cache pending delete tombstone")
        }
    }

    private func removeCachedTask(id: UUID) {
        removeCachedTask(id: id, shouldSave: true)
    }

    private func removeCachedTask(id: UUID, shouldSave: Bool) {
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            modelContext.delete(cached)
            if shouldSave {
                saveContextOrSetError(operation: "remove cached task")
            }
        }
    }

    private func upsertCachedBacklogItem(
        _ item: BacklogItem,
        syncStatusRaw: String,
        lastSyncedAt: Date?,
        shouldSave: Bool
    ) {
        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == item.id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.update(from: item)
            cached.syncStatusRaw = syncStatusRaw
            cached.lastSyncedAt = lastSyncedAt
        } else {
            let cached = CachedBacklogItem(from: item)
            cached.syncStatusRaw = syncStatusRaw
            cached.lastSyncedAt = lastSyncedAt
            modelContext.insert(cached)
        }

        if shouldSave {
            saveContextOrSetError(operation: "persist backlog item from task move")
        }
    }

    private func cachedBacklogItemSnapshot(for id: UUID) -> CachedBacklogItemSnapshot? {
        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == id }
        )
        guard let cached = try? modelContext.fetch(descriptor).first else { return nil }
        return CachedBacklogItemSnapshot(
            item: cached.toBacklogItem(),
            syncStatusRaw: cached.syncStatusRaw,
            lastSyncedAt: cached.lastSyncedAt
        )
    }

    private func restoreCachedBacklogItem(_ snapshot: CachedBacklogItemSnapshot, shouldSave: Bool) {
        upsertCachedBacklogItem(
            snapshot.item,
            syncStatusRaw: snapshot.syncStatusRaw,
            lastSyncedAt: snapshot.lastSyncedAt,
            shouldSave: shouldSave
        )
    }

    private func removeCachedBacklogItem(id: UUID, shouldSave: Bool) {
        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            modelContext.delete(cached)
        }

        if shouldSave {
            saveContextOrSetError(operation: "remove backlog item from task move rollback")
        }
    }

    private func markCachedBacklogItemAwaitingCloudEcho(id: UUID) {
        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.syncStatusRaw = "awaitingCloudEcho"
            cached.lastSyncedAt = Date()
            saveContextOrSetError(operation: "mark backlog item awaiting cloud echo")
        }
    }

    func pendingSyncSnapshot(from cachedTasks: [CachedTask]) -> PendingSyncSnapshot {
        var pendingUploadByID: [UUID: Task] = [:]
        var pendingDeleteIDs = Set<UUID>()
        var pendingDeleteLogicalItemIDs = Set<UUID>()

        for cached in cachedTasks {
            switch cached.syncStatusRaw {
            case TaskSyncStatus.pendingUpload, TaskSyncStatus.awaitingCloudEcho:
                pendingUploadByID[cached.id] = cached.toTask()
            case TaskSyncStatus.pendingDelete:
                pendingDeleteIDs.insert(cached.id)
                pendingDeleteLogicalItemIDs.insert(resolvedLogicalItemID(for: cached))
            default:
                continue
            }
        }

        return PendingSyncSnapshot(
            pendingUploadByID: pendingUploadByID,
            pendingDeleteIDs: pendingDeleteIDs,
            pendingDeleteLogicalItemIDs: pendingDeleteLogicalItemIDs
        )
    }

    func mergeCloudSnapshot(
        _ cloudTasks: [Task],
        with pendingSnapshot: PendingSyncSnapshot
    ) -> [Task] {
        var mergedByLogicalID = Dictionary(
            uniqueKeysWithValues: deduplicatedCloudTasks(cloudTasks).map { ($0.logicalItemID, $0) }
        )
        let localByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        for pendingTask in pendingSnapshot.pendingUploadByID.values {
            if let cloudTask = mergedByLogicalID[pendingTask.logicalItemID],
               cloudTaskMatchesLocalMutationEcho(cloudTask, localTask: pendingTask)
            {
                mergedByLogicalID[pendingTask.logicalItemID] = cloudTask
                continue
            }
            mergedByLogicalID[pendingTask.logicalItemID] = pendingTask
        }

        for logicalID in pendingSnapshot.pendingDeleteLogicalItemIDs {
            mergedByLogicalID.removeValue(forKey: logicalID)
        }

        for id in pendingTaskMutations {
            if let local = localByID[id] {
                mergedByLogicalID[local.logicalItemID] = local
            }
        }

        return mergedByLogicalID.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func cloudTaskMatchesLocalMutationEcho(_ cloudTask: Task, localTask: Task) -> Bool {
        guard cloudTask.updatedAt >= localTask.updatedAt else { return false }

        return cloudTask.logicalItemID == localTask.logicalItemID &&
            cloudTask.status == localTask.status &&
            cloudTask.completedAt == localTask.completedAt &&
            cloudTask.completedById == localTask.completedById &&
            cloudTask.assigneeId == localTask.assigneeId &&
            Set(cloudTask.assigneeIds) == Set(localTask.assigneeIds) &&
            cloudTask.backlogCategoryId == localTask.backlogCategoryId &&
            cloudTask.title == localTask.title &&
            cloudTask.notes == localTask.notes &&
            cloudTask.order == localTask.order
    }

    private func shouldForceVisibleHydration() -> Bool {
        needsLocalRehydrate || !hasHydratedVisibleSnapshot || tasks.isEmpty
    }

    private func syncDemotedTaskDestinationInBackground(_ item: BacklogItem) {
        _ = _Concurrency.Task { [self] in
            do {
                _ = try await cloudKit.saveBacklogItem(item, scope: cloudScope)
                markCachedBacklogItemAwaitingCloudEcho(id: item.id)
            } catch {
                self.error = error
            }
        }
    }

    @discardableResult
    func createTaskFromBacklogItem(
        title: String,
        notes: String? = nil,
        preferredStatus: Task.TaskStatus = .next,
        assigneeId: UUID? = nil,
        taskType: Task.TaskType = .oneOff,
        recurringChoreId: UUID? = nil,
        taskId: UUID = UUID(),
        logicalItemID: UUID? = nil,
        backlogCategoryId: UUID? = nil
    ) async -> NextTransitionValidation {
        await createTask(
            taskId: taskId,
            logicalItemID: logicalItemID,
            title: title,
            status: preferredStatus,
            assigneeId: assigneeId,
            assigneeIds: assigneeId.map { [$0] } ?? [],
            backlogCategoryId: backlogCategoryId,
            notes: notes,
            taskType: taskType,
            recurringChoreId: recurringChoreId
        )
    }

    private func nextTaskOrderBaseline() -> Int {
        tasks
            .filter { $0.status == .next }
            .map(\.order)
            .max() ?? -1
    }

    private func resolvedLogicalItemID(for cached: CachedTask) -> UUID {
        cached.logicalItemID ?? cached.id
    }

    private func deduplicatedVisibleTasks(from cachedTasks: [CachedTask]) -> [Task] {
        let tombstonedLogicalItemIDs = Set(
            cachedTasks.compactMap { cachedTask in
                cachedTask.syncStatusRaw == TaskSyncStatus.pendingDelete
                    ? resolvedLogicalItemID(for: cachedTask) : nil
            }
        )

        return canonicalCachedTasksByLogicalItemID(cachedTasks)
            .filter { !tombstonedLogicalItemIDs.contains($0.key) }
            .values
            .filter { $0.syncStatusRaw != TaskSyncStatus.pendingDelete }
            .map { $0.toTask() }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func canonicalCachedTasksByLogicalItemID(_ cachedTasks: [CachedTask]) -> [UUID: CachedTask] {
        var deduplicated: [UUID: CachedTask] = [:]

        for cached in cachedTasks {
            let logicalItemID = resolvedLogicalItemID(for: cached)
            if let existing = deduplicated[logicalItemID] {
                if shouldPreferCachedTask(cached, over: existing) {
                    deduplicated[logicalItemID] = cached
                }
            } else {
                deduplicated[logicalItemID] = cached
            }
        }

        return deduplicated
    }

    private func shouldPreferCachedTask(_ candidate: CachedTask, over current: CachedTask) -> Bool {
        let candidatePriority = taskSyncPriority(candidate.syncStatusRaw)
        let currentPriority = taskSyncPriority(current.syncStatusRaw)
        if candidatePriority != currentPriority {
            return candidatePriority > currentPriority
        }
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }
        if candidate.createdAt != current.createdAt {
            return candidate.createdAt > current.createdAt
        }
        return candidate.id.uuidString < current.id.uuidString
    }

    private func taskSyncPriority(_ syncStatusRaw: String) -> Int {
        switch syncStatusRaw {
        case TaskSyncStatus.pendingUpload, TaskSyncStatus.awaitingCloudEcho:
            3
        case TaskSyncStatus.synced:
            2
        case TaskSyncStatus.pendingDelete:
            0
        default:
            1
        }
    }

    private func deduplicatedCloudTasks(_ tasks: [Task]) -> [Task] {
        var deduplicated: [UUID: Task] = [:]

        for task in tasks {
            if let existing = deduplicated[task.logicalItemID] {
                if shouldPreferCloudTask(task, over: existing) {
                    deduplicated[task.logicalItemID] = task
                }
            } else {
                deduplicated[task.logicalItemID] = task
            }
        }

        return Array(deduplicated.values)
    }

    private func shouldPreferCloudTask(_ candidate: Task, over current: Task) -> Bool {
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }
        if candidate.createdAt != current.createdAt {
            return candidate.createdAt > current.createdAt
        }
        return candidate.id.uuidString < current.id.uuidString
    }

    private func shouldReplaceTaskLineageConflict(with cloudTask: Task, existing: Task) -> Bool {
        cloudTask.updatedAt >= existing.updatedAt
    }

    private func existingDestinationBacklogItem(for logicalItemID: UUID) -> BacklogItem? {
        guard let householdId else { return nil }
        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedItems = (try? modelContext.fetch(descriptor)) ?? []

        return cachedItems
            .filter {
                ($0.logicalItemID ?? $0.id) == logicalItemID &&
                    $0.syncStatusRaw != TaskSyncStatus.pendingDelete
            }
            .max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }?
            .toBacklogItem()
    }

    private func demotedBacklogDestination(
        from task: Task,
        destinationCategoryId: UUID,
        householdId: UUID,
        existing: BacklogItem?
    ) -> BacklogItem {
        if let existing {
            return BacklogItem(
                id: existing.id,
                logicalItemID: existing.logicalItemID,
                categoryId: destinationCategoryId,
                householdId: householdId,
                title: task.title,
                assigneeId: task.assigneeId,
                notes: task.notes,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
        }

        return BacklogItem(
            logicalItemID: task.logicalItemID,
            categoryId: destinationCategoryId,
            householdId: householdId,
            title: task.title,
            assigneeId: task.assigneeId,
            notes: task.notes,
            createdAt: task.createdAt,
            updatedAt: Date()
        )
    }

    private static func activeTaskSort(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.status == .next, rhs.status == .next, lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        let lhsDue = lhs.dueDate ?? .distantFuture
        let rhsDue = rhs.dueDate ?? .distantFuture
        if lhsDue != rhsDue {
            return lhsDue < rhsDue
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func completedTaskSort(_ lhs: Task, _ rhs: Task) -> Bool {
        let lhsCompleted = lhs.completedAt ?? .distantPast
        let rhsCompleted = rhs.completedAt ?? .distantPast
        if lhsCompleted != rhsCompleted {
            return lhsCompleted > rhsCompleted
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private extension TaskStore.NextTransitionValidation {
    var taskStoreError: TaskStoreError? {
        switch self {
        case .ok:
            nil
        case .assigneeRequired:
            .assigneeRequired
        case .wipLimitReached:
            .wipLimitReached
        }
    }
}

enum TaskStoreError: LocalizedError, Equatable {
    case assigneeRequired
    case wipLimitReached

    var errorDescription: String? {
        switch self {
        case .assigneeRequired:
            "Assign this task before moving it to Next."
        case .wipLimitReached:
            "You are above the recommended active task count. Consider finishing some tasks first."
        }
    }
}

// swiftlint:enable file_length type_body_length
