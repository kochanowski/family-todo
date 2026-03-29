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

    /// Scope used for all CloudKit **read** (fetch) operations.
    /// See ShoppingListStore.readScope for full rationale.
    private var readScope: CloudKitManager.HouseholdDatabaseScope {
        .participantShared
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

    enum MoveToIdeasResult: Equatable {
        case success(categoryId: UUID)
        case missingDestinationCategory
        case localSaveFailed
        case alreadyProcessing
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

    private func persistTaskWorkItem(
        _ task: Task,
        syncStatusRaw: String,
        lastSyncedAt: Date?,
        shouldSave: Bool,
        operation: String
    ) {
        WorkItemCacheStoreSupport.upsert(
            WorkItem(task: task),
            syncStatusRaw: syncStatusRaw,
            lastSyncedAt: lastSyncedAt,
            context: modelContext,
            shouldSave: shouldSave
        ) { [self] defaultOperation in
            saveContextOrSetError(operation: operation.isEmpty ? defaultOperation : operation)
        }
    }

    private func markTaskWorkItemPendingDelete(
        _ task: Task,
        shouldSave: Bool,
        operation: String
    ) {
        WorkItemCacheStoreSupport.markPendingDelete(
            WorkItem(task: task),
            context: modelContext,
            shouldSave: shouldSave
        ) { [self] defaultOperation in
            saveContextOrSetError(operation: operation.isEmpty ? defaultOperation : operation)
        }
    }

    private func removeTaskWorkItem(
        id: UUID,
        shouldSave: Bool,
        operation: String
    ) {
        WorkItemCacheStoreSupport.remove(
            id: id,
            context: modelContext,
            shouldSave: shouldSave
        ) { [self] defaultOperation in
            saveContextOrSetError(operation: operation.isEmpty ? defaultOperation : operation)
        }
    }

    private func markTaskWorkItemAwaitingCloudEcho(id: UUID, operation: String) {
        WorkItemCacheStoreSupport.markAwaitingCloudEcho(
            id: id,
            context: modelContext,
            shouldSave: true
        ) { [self] defaultOperation in
            saveContextOrSetError(operation: operation.isEmpty ? defaultOperation : operation)
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
            let cloudWorkItems = try await cloudKit.fetchUnifiedWorkItems(
                householdId: householdId,
                scope: readScope
            )

            syncCloudWorkItemsToCache(cloudWorkItems)
            _ = fetchCachedTaskWorkItems(updateVisibleState: true)
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
        _ = fetchCachedTaskWorkItems(updateVisibleState: force || shouldForceVisibleHydration())
    }

    private func fetchCachedTaskWorkItems(updateVisibleState: Bool) -> [CachedWorkItem] {
        guard let householdId else {
            if updateVisibleState {
                tasks = []
                hasHydratedVisibleSnapshot = true
                hasHydratedLocalSnapshot = true
                needsLocalRehydrate = false
            }
            return []
        }

        let cached = WorkItemCacheStoreSupport.fetchCachedWorkItems(
            householdId: householdId,
            context: modelContext
        )
        if updateVisibleState {
            tasks = visibleTasks(from: cached)
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

    private func syncCloudWorkItemsToCache(_ cloudItems: [WorkItem]) {
        guard let householdId else { return }

        let descriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedWorkItems = (try? modelContext.fetch(descriptor)) ?? []
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedWorkItems.map { ($0.id, $0) })
        let pendingSnapshot = WorkItemCacheStoreSupport.pendingSnapshot(from: cachedWorkItems)
        let deduplicatedByLogicalID = WorkItemCacheStoreSupport.canonicalCachedWorkItemsByLogicalItemID(cachedWorkItems)

        for item in cloudItems {
            if pendingSnapshot.pendingDeleteLogicalItemIDs.contains(item.logicalItemID) {
                continue
            }

            if let cached = cachedByID[item.id] {
                if WorkItemCacheStoreSupport.shouldIgnoreCloudSnapshot(
                    item,
                    for: cached,
                    pendingSnapshot: pendingSnapshot,
                    mutationEchoMatches: cloudWorkItemMatchesLocalMutationEcho
                ) {
                    continue
                }
                cached.update(from: item)
                cached.syncStatusRaw = TaskSyncStatus.synced
                cached.lastSyncedAt = Date()
                continue
            }

            if let cached = deduplicatedByLogicalID[item.logicalItemID] {
                if WorkItemCacheStoreSupport.shouldIgnoreCloudSnapshot(
                    item,
                    for: cached,
                    pendingSnapshot: pendingSnapshot,
                    mutationEchoMatches: cloudWorkItemMatchesLocalMutationEcho
                ) {
                    continue
                }
                cached.update(from: item)
                cached.syncStatusRaw = TaskSyncStatus.synced
                cached.lastSyncedAt = Date()
                continue
            }

            if pendingSnapshot.pendingDeleteLogicalItemIDs.contains(item.logicalItemID) {
                continue
            }

            if cachedByID[item.id] == nil {
                let cached = CachedWorkItem(from: item)
                cached.syncStatusRaw = TaskSyncStatus.synced
                cached.lastSyncedAt = Date()
                modelContext.insert(cached)
            }
        }

        saveContextOrSetError(operation: "sync task work items to cache")
    }

    private func visibleTasks(from cachedWorkItems: [CachedWorkItem]) -> [Task] {
        WorkItemCacheStoreSupport.visibleTasks(from: cachedWorkItems)
    }

    private func cloudWorkItemMatchesLocalMutationEcho(_ cloudItem: WorkItem, localItem: WorkItem) -> Bool {
        cloudItem.id == localItem.id &&
            cloudItem.logicalItemID == localItem.logicalItemID &&
            cloudItem.status == localItem.status &&
            cloudItem.assigneeId == localItem.assigneeId &&
            cloudItem.categoryId == localItem.categoryId &&
            cloudItem.updatedAt >= localItem.updatedAt
    }

    private static func workItemTaskSort(_ lhs: WorkItem, _ rhs: WorkItem) -> Bool {
        let lhsTask = lhs.toTask()
        let rhsTask = rhs.toTask()
        return activeTaskSort(lhsTask, rhsTask)
    }

    func syncToCache(_ cloudTasks: [Task], cloudTaskIDs _: Set<UUID>) {
        syncCloudWorkItemsToCache(cloudTasks.map(WorkItem.init(task:)))
    }

    func syncUnifiedWorkItemsToCache(_ cloudItems: [WorkItem]) {
        syncCloudWorkItemsToCache(cloudItems)
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

        // Fix #5 — awaitingCloudEcho expiry sweep: if a task has been awaiting a cloud echo
        // for longer than the grace period, reset it to pendingUpload so the next flush retries.
        // This prevents items from being permanently stuck if a cloud echo never arrives
        // (e.g. after a transient CloudKit outage or silent push throttling).
        let echoGraceDuration: TimeInterval = 45
        let now = Date()
        var didExpireAnyEcho = false
        for cached in cachedTasks
            where cached.syncStatusRaw == TaskSyncStatus.awaitingCloudEcho
        {
            guard let lastSyncedAt = cached.lastSyncedAt else { continue }
            if now.timeIntervalSince(lastSyncedAt) >= echoGraceDuration {
                cached.syncStatusRaw = TaskSyncStatus.pendingUpload
                cached.lastSyncedAt = nil
                didExpireAnyEcho = true
            }
        }
        if didExpireAnyEcho {
            saveContextOrSetError(operation: "reset expired awaitingCloudEcho tasks to pendingUpload")
        }

        let pendingUploads = cachedTasks.filter { $0.syncStatusRaw == TaskSyncStatus.pendingUpload }
        let pendingDeletes = cachedTasks.filter { $0.syncStatusRaw == TaskSyncStatus.pendingDelete }

        guard !pendingUploads.isEmpty || !pendingDeletes.isEmpty else { return }

        var didMutateCache = false

        for cached in pendingUploads where !pendingTaskMutations.contains(cached.id) {
            do {
                _ = try await cloudKit.saveWorkItem(cached.toWorkItem(), scope: cloudScope)
                cached.syncStatusRaw = TaskSyncStatus.awaitingCloudEcho
                cached.lastSyncedAt = Date()
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        for cached in pendingDeletes where !pendingTaskMutations.contains(cached.id) {
            do {
                try await cloudKit.deleteWorkItem(
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

        persistTaskWorkItem(
            updatedTask,
            syncStatusRaw: isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced,
            lastSyncedAt: isCloudSyncEnabled ? nil : now,
            shouldSave: true,
            operation: "cache poked task"
        )

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

        persistTaskWorkItem(
            task,
            syncStatusRaw: isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced,
            lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
            shouldSave: true,
            operation: "persist created task work item"
        )

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
        persistTaskWorkItem(
            updatedTask,
            syncStatusRaw: isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced,
            lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
            shouldSave: true,
            operation: "persist updated task work item"
        )

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
            updatedTask.completedById = currentUserId
        } else if task.status == .done {
            updatedTask.completedAt = nil
            updatedTask.completedById = nil
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
    func moveTaskToIdeas(_ task: Task, destinationCategoryId: UUID?) -> MoveToIdeasResult {
        guard let destinationCategoryId else {
            return .missingDestinationCategory
        }
        let resolvedHouseholdId = householdId ?? task.householdId
        let existingIdea = existingDestinationBacklogItem(for: task.logicalItemID)

        let demotedBacklogItem = demotedBacklogDestination(
            from: task,
            destinationCategoryId: destinationCategoryId,
            householdId: resolvedHouseholdId,
            existing: existingIdea
        )
        let demotedItem = WorkItem(idea: demotedBacklogItem)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            tasks.removeAll { $0.id == task.id }
        }

        if demotedItem.id != task.id {
            if isCloudSyncEnabled {
                markTaskWorkItemPendingDelete(
                    task,
                    shouldSave: false,
                    operation: "mark demoted task pending delete"
                )
            } else {
                removeTaskWorkItem(
                    id: task.id,
                    shouldSave: false,
                    operation: "remove demoted task work item"
                )
            }
        }

        WorkItemCacheStoreSupport.upsert(
            demotedItem,
            syncStatusRaw: isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced,
            lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
            context: modelContext,
            shouldSave: false
        ) { [self] _ in
            saveContextOrSetError(operation: "persist demoted task work item")
        }

        guard saveContextOrSetError(operation: "move task to ideas locally") else {
            modelContext.rollback()
            restoreTaskLocally(task)
            return .localSaveFailed
        }

        NotificationCenter.default.post(name: .backlogDataDidChange, object: "local")
        NotificationCenter.default.post(name: .taskBoardDataDidChange, object: "local")

        _ = _Concurrency.Task { [self] in
            await notificationService.removeTaskReminder(for: task)
            await syncDailyDigestSchedule()
        }

        if isCloudSyncEnabled {
            replayPendingMutationsInBackground()
        }

        return .success(categoryId: destinationCategoryId)
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
        persistTaskWorkItem(
            task,
            syncStatusRaw: TaskSyncStatus.pendingUpload,
            lastSyncedAt: nil,
            shouldSave: true,
            operation: "restore task locally"
        )
        _ = _Concurrency.Task {
            await self.syncDailyDigestSchedule()
        }
    }

    func deleteTaskRemote(id: UUID, householdId: UUID) async throws {
        try await cloudKit.deleteWorkItem(id: id, householdId: householdId, scope: cloudScope)
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
            persistTaskWorkItem(
                updatedTask,
                syncStatusRaw: isCloudSyncEnabled ? TaskSyncStatus.pendingUpload : TaskSyncStatus.synced,
                lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
                shouldSave: false,
                operation: ""
            )
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
        for task in tasksToDelete {
            markTaskWorkItemPendingDelete(
                task,
                shouldSave: false,
                operation: "batch mark tasks pending delete"
            )
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

    private func fetchCachedTasksForCurrentHousehold() -> [CachedWorkItem] {
        let cachedItems = WorkItemCacheStoreSupport.fetchCachedWorkItems(
            householdId: householdId,
            context: modelContext
        )
        return cachedItems.filter { $0.toWorkItem().status != .idea }
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
        markTaskWorkItemPendingDelete(
            task,
            shouldSave: shouldSave,
            operation: shouldSave ? "mark cached task pending delete" : ""
        )
    }

    private func removeCachedTask(id: UUID) {
        removeCachedTask(id: id, shouldSave: true)
    }

    private func removeCachedTask(id: UUID, shouldSave: Bool) {
        removeTaskWorkItem(
            id: id,
            shouldSave: shouldSave,
            operation: "remove cached task"
        )
    }

    func pendingSyncSnapshot(from cachedTasks: [CachedWorkItem]) -> PendingSyncSnapshot {
        var pendingUploadByID: [UUID: Task] = [:]
        var pendingDeleteIDs = Set<UUID>()
        var pendingDeleteLogicalItemIDs = Set<UUID>()

        for cached in cachedTasks {
            switch cached.syncStatusRaw {
            case TaskSyncStatus.pendingUpload, TaskSyncStatus.awaitingCloudEcho:
                if let task = cached.toWorkItem().asTask() {
                    pendingUploadByID[cached.id] = task
                }
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

    private func resolvedLogicalItemID(for cached: CachedWorkItem) -> UUID {
        WorkItemCacheStoreSupport.resolvedLogicalItemID(for: cached)
    }

    private func deduplicatedVisibleTasks(from cachedTasks: [CachedWorkItem]) -> [Task] {
        WorkItemCacheStoreSupport.visibleTasks(from: cachedTasks)
    }

    private func canonicalCachedTasksByLogicalItemID(_ cachedTasks: [CachedWorkItem]) -> [UUID: CachedWorkItem] {
        WorkItemCacheStoreSupport.canonicalCachedWorkItemsByLogicalItemID(cachedTasks)
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
        let cachedWorkItems = WorkItemCacheStoreSupport.fetchCachedWorkItems(
            householdId: householdId,
            context: modelContext
        )

        return cachedWorkItems
            .filter {
                $0.logicalItemID == logicalItemID &&
                    $0.syncStatusRaw != TaskSyncStatus.pendingDelete &&
                    $0.toWorkItem().status == .idea
            }
            .max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }?
            .toWorkItem()
            .asBacklogItem()
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
            id: task.id,
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
