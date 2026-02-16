import Combine
import Foundation
import SwiftData
import SwiftUI

/// Main store for task management with offline-first architecture.
/// Follows ADR-002: optimistic UI updates with background sync.
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [Task] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

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

    // MARK: - Computed Properties

    var backlogTasks: [Task] {
        tasks.filter { $0.status == .backlog }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var nextTasks: [Task] {
        tasks.filter { $0.status == .next }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var doneTasks: [Task] {
        tasks.filter { $0.status == .done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
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
        loadFromCache()

        if !isCloudSyncEnabled {
            isLoading = false
            return
        }

        // Then sync with CloudKit
        do {
            // Ensure CloudKit is ready before accessing
            await cloudKit.ensureReady()
            let cloudTasks = try await cloudKit.fetchTasks(householdId: householdId)
            tasks = cloudTasks
            syncToCache(cloudTasks)
        } catch {
            // If CloudKit fails, we already have cached data
            self.error = error
        }

        isLoading = false
    }

    private func loadFromCache() {
        guard let householdId else { return }

        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        if let cached = try? modelContext.fetch(descriptor) {
            tasks = cached.map { $0.toTask() }
        }
    }

    private func syncToCache(_ cloudTasks: [Task]) {
        // Update local cache with cloud data
        for task in cloudTasks {
            let descriptor = FetchDescriptor<CachedTask>(
                predicate: #Predicate { $0.id == task.id }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.update(from: task)
            } else {
                let cached = CachedTask(from: task)
                modelContext.insert(cached)
            }
        }
        try? modelContext.save()
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
        recurringChoreId: UUID? = nil
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
            notes: notes
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
        try? modelContext.save()

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
            try? modelContext.save()

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
            try? modelContext.save()
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

        return await updateTask(updatedTask)
    }

    func deleteTask(_ task: Task) async {
        // Optimistic UI update
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            tasks.removeAll { $0.id == task.id }
        }

        // Remove from cache
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == task.id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            modelContext.delete(cached)
            try? modelContext.save()
        }

        if !isCloudSyncEnabled {
            await notificationService.removeTaskReminder(for: task)
            return
        }

        // Delete from CloudKit
        do {
            try await cloudKit.deleteTask(id: task.id)

            // Remove any scheduled notification
            await notificationService.removeTaskReminder(for: task)
        } catch {
            self.error = error
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

        for task in tasksToDelete {
            await deleteTask(task)
        }
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

        for task in tasksToDelete {
            await deleteTask(task)
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
