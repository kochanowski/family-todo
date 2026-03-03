import Combine
import Foundation
import SwiftData
import SwiftUI

extension Notification.Name {
    static let memberProfileDidChange = Notification.Name("HousePulse.memberProfileDidChange")
    static let taskBoardDataDidChange = Notification.Name("HousePulse.taskBoardDataDidChange")
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
    @Published private(set) var tasks: [Task] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var pendingTaskMutations: Set<UUID> = []

    private lazy var cloudKit = CloudKitManager.shared
    private lazy var notificationService = NotificationService.shared
    private let modelContext: ModelContext
    private var householdId: UUID?
    private var syncMode: SyncMode = .cloud

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
    }

    private var isCloudSyncEnabled: Bool {
        syncMode == .cloud
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

    // MARK: - Data Loading

    func setHousehold(_ id: UUID) {
        householdId = id
    }

    func loadTasks() async {
        guard let householdId else { return }

        isLoading = true
        error = nil

        // First, load from local cache
        let cachedTasks = loadFromCache()
        let pendingSnapshot = pendingSyncSnapshot(from: cachedTasks)

        if !isCloudSyncEnabled {
            isLoading = false
            return
        }

        // Then sync with CloudKit
        do {
            // Ensure CloudKit is ready before accessing
            await cloudKit.ensureReady()
            let cloudTasks = try await cloudKit.fetchTasks(householdId: householdId)
            tasks = mergeCloudSnapshot(cloudTasks, with: pendingSnapshot)
            syncToCache(cloudTasks)
            await flushPendingSync()
        } catch {
            // If CloudKit fails, we already have cached data
            self.error = error
        }

        isLoading = false
    }

    private func loadFromCache() -> [CachedTask] {
        guard let householdId else { return [] }

        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        guard let cached = try? modelContext.fetch(descriptor) else { return [] }
        tasks = cached
            .filter { $0.syncStatusRaw != "pendingDelete" }
            .map { $0.toTask() }
        return cached
    }

    private func syncToCache(_ cloudTasks: [Task]) {
        // Update local cache with cloud data
        for task in cloudTasks {
            let descriptor = FetchDescriptor<CachedTask>(
                predicate: #Predicate { $0.id == task.id }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                if existing.syncStatusRaw == "pendingUpload" || existing.syncStatusRaw == "pendingDelete" {
                    continue
                }
                existing.update(from: task)
            } else {
                let cached = CachedTask(from: task)
                modelContext.insert(cached)
            }
        }
        saveContextOrSetError(operation: "sync tasks cache from cloud")
    }

    private func flushPendingSync() async {
        guard isCloudSyncEnabled, householdId != nil else { return }

        let cachedTasks = fetchCachedTasksForCurrentHousehold()
        let pendingUploads = cachedTasks.filter { $0.syncStatusRaw == "pendingUpload" }
        let pendingDeletes = cachedTasks.filter { $0.syncStatusRaw == "pendingDelete" }

        guard !pendingUploads.isEmpty || !pendingDeletes.isEmpty else { return }

        var didMutateCache = false

        for cached in pendingUploads where !pendingTaskMutations.contains(cached.id) {
            do {
                _ = try await cloudKit.saveTask(cached.toTask())
                cached.syncStatusRaw = "synced"
                cached.lastSyncedAt = Date()
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        for cached in pendingDeletes where !pendingTaskMutations.contains(cached.id) {
            do {
                try await cloudKit.deleteTask(id: cached.id, householdId: cached.householdId)
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

    @discardableResult
    func createTask(
        taskId: UUID = UUID(),
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

        // Validate transition constraints (assignee required for Next).
        if status == .next {
            let validation = validateNextTransition(assigneeId: assigneeId)
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

        let resolvedOrder: Int
        if status == .next {
            resolvedOrder = order ?? (nextTaskOrderBaseline() + 1)
        } else {
            resolvedOrder = order ?? 0
        }

        let task = Task(
            id: taskId,
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
        cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
        cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
        modelContext.insert(cached)
        saveContextOrSetError(operation: "cache created task")

        if !isCloudSyncEnabled {
            if task.dueDate != nil, !notificationService.isAuthorized {
                await notificationService.requestAuthorization()
            }
            await notificationService.scheduleTaskReminder(for: task)
            return .ok
        }

        // Sync to CloudKit
        do {
            _ = try await cloudKit.saveTask(task)
            cached.syncStatusRaw = "synced"
            cached.lastSyncedAt = Date()
            saveContextOrSetError(operation: "mark created task as synced")

            // Schedule notification if task has due date
            if task.dueDate != nil, !notificationService.isAuthorized {
                await notificationService.requestAuthorization()
            }
            await notificationService.scheduleTaskReminder(for: task)
        } catch {
            self.error = error
        }
        return .ok
    }

    @discardableResult
    func updateTask(_ task: Task) async -> NextTransitionValidation {
        var updatedTask = task
        updatedTask.updatedAt = Date()
        beginMutation(updatedTask.id)
        defer { endMutation(updatedTask.id) }

        // Validate transition constraints if moving to Next.
        let wipAssigneeId = task.assigneeId ?? task.assigneeIds.first
        if task.status == .next {
            let validation = validateNextTransition(assigneeId: wipAssigneeId, excludingTaskId: task.id)
            guard validation == .ok else {
                error = validation.taskStoreError
                return validation
            }
        }

        // Optimistic UI update
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                tasks[index] = updatedTask
            }
        }

        // Update cache
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == task.id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.update(from: updatedTask)
            cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            saveContextOrSetError(operation: "cache updated task")
        } else {
            let cached = CachedTask(from: updatedTask)
            cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            modelContext.insert(cached)
            saveContextOrSetError(operation: "cache inserted updated task")
        }

        if !isCloudSyncEnabled {
            if updatedTask.dueDate != nil, !notificationService.isAuthorized {
                await notificationService.requestAuthorization()
            }
            await notificationService.scheduleTaskReminder(for: updatedTask)
            return .ok
        }

        // Sync to CloudKit
        do {
            _ = try await cloudKit.saveTask(updatedTask)
            markCachedTaskSynced(id: updatedTask.id)

            // Update notification (remove old, schedule new if due date changed)
            if updatedTask.dueDate != nil, !notificationService.isAuthorized {
                await notificationService.requestAuthorization()
            }
            await notificationService.scheduleTaskReminder(for: updatedTask)
        } catch {
            self.error = error
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
            return
        }

        markCachedTaskPendingDelete(task)

        // Delete from CloudKit
        do {
            try await cloudKit.deleteTask(id: task.id, householdId: task.householdId)
            removeCachedTask(id: task.id)

            // Remove any scheduled notification
            await notificationService.removeTaskReminder(for: task)
        } catch {
            self.error = error
        }
    }

    func removeTaskLocally(_ task: Task) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            tasks.removeAll { $0.id == task.id }
        }
        markCachedTaskPendingDelete(task)
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
            cached.syncStatusRaw = "pendingUpload"
            cached.lastSyncedAt = nil
        } else {
            let cached = CachedTask(from: task)
            cached.syncStatusRaw = "pendingUpload"
            cached.lastSyncedAt = nil
            modelContext.insert(cached)
        }
        saveContextOrSetError(operation: "restore task locally")
    }

    func deleteTaskRemote(id: UUID, householdId: UUID) async throws {
        try await cloudKit.deleteTask(id: id, householdId: householdId)
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
                cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
                cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            } else {
                let cached = CachedTask(from: updatedTask)
                cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
                cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
                modelContext.insert(cached)
            }
        }
        saveContextOrSetError(operation: "persist reordered tasks")

        guard isCloudSyncEnabled else { return }
        for updatedTask in updatedByID.values.sorted(by: { $0.order < $1.order }) {
            do {
                _ = try await cloudKit.saveTask(updatedTask)
                markCachedTaskSynced(id: updatedTask.id)
            } catch {
                self.error = error
            }
        }
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
            return
        }

        markCachedTasksPendingDelete(tasksToDelete)

        var successfullyDeletedIDs = Set<UUID>()
        for task in tasksToDelete {
            do {
                try await cloudKit.deleteTask(id: task.id, householdId: task.householdId)
                successfullyDeletedIDs.insert(task.id)
                await notificationService.removeTaskReminder(for: task)
            } catch {
                self.error = error
            }
        }

        if !successfullyDeletedIDs.isEmpty {
            batchDeleteCachedTasks(ids: successfullyDeletedIDs)
        }
    }

    private func markCachedTasksPendingDelete(_ tasksToDelete: [Task]) {
        guard !tasksToDelete.isEmpty else { return }
        let cachedTasks = fetchCachedTasksForCurrentHousehold()
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedTasks.map { ($0.id, $0) })

        for task in tasksToDelete {
            if let cached = cachedByID[task.id] {
                cached.syncStatusRaw = "pendingDelete"
                cached.lastSyncedAt = nil
            } else {
                let cached = CachedTask(from: task)
                cached.syncStatusRaw = "pendingDelete"
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

    private func markCachedTaskSynced(id: UUID) {
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.syncStatusRaw = "synced"
            cached.lastSyncedAt = Date()
            saveContextOrSetError(operation: "mark cached task as synced")
        }
    }

    private func markCachedTaskPendingDelete(_ task: Task) {
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == task.id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.syncStatusRaw = "pendingDelete"
            cached.lastSyncedAt = nil
            saveContextOrSetError(operation: "mark cached task pending delete")
            return
        }

        let cached = CachedTask(from: task)
        cached.syncStatusRaw = "pendingDelete"
        cached.lastSyncedAt = nil
        modelContext.insert(cached)
        saveContextOrSetError(operation: "cache pending delete tombstone")
    }

    private func removeCachedTask(id: UUID) {
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            modelContext.delete(cached)
            saveContextOrSetError(operation: "remove cached task")
        }
    }

    func pendingSyncSnapshot(from cachedTasks: [CachedTask]) -> PendingSyncSnapshot {
        var pendingUploadByID: [UUID: Task] = [:]
        var pendingDeleteIDs = Set<UUID>()

        for cached in cachedTasks {
            switch cached.syncStatusRaw {
            case "pendingUpload":
                pendingUploadByID[cached.id] = cached.toTask()
            case "pendingDelete":
                pendingDeleteIDs.insert(cached.id)
            default:
                continue
            }
        }

        return PendingSyncSnapshot(
            pendingUploadByID: pendingUploadByID,
            pendingDeleteIDs: pendingDeleteIDs
        )
    }

    func mergeCloudSnapshot(
        _ cloudTasks: [Task],
        with pendingSnapshot: PendingSyncSnapshot
    ) -> [Task] {
        var mergedByID = Dictionary(uniqueKeysWithValues: cloudTasks.map { ($0.id, $0) })
        let localByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        for (id, pendingTask) in pendingSnapshot.pendingUploadByID {
            if let cloudTask = mergedByID[id], cloudTask.updatedAt > pendingTask.updatedAt {
                continue
            }
            mergedByID[id] = pendingTask
        }

        for id in pendingSnapshot.pendingDeleteIDs {
            mergedByID.removeValue(forKey: id)
        }

        for id in pendingTaskMutations {
            if let local = localByID[id] {
                mergedByID[id] = local
            }
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
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
        backlogCategoryId: UUID? = nil
    ) async -> NextTransitionValidation {
        await createTask(
            taskId: taskId,
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
