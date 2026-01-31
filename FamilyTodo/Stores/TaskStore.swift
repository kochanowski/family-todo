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

    /// WIP limit per user (max 3 tasks in "Next")
    static let wipLimit = 3

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

    /// Check if user can add more tasks to "Next" (WIP limit)
    func canMoveToNext(assigneeId: UUID?) -> Bool {
        guard let assigneeId else { return true }
        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        return currentCount < Self.wipLimit
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

    func createTask(
        title: String,
        status: Task.TaskStatus = .backlog,
        assigneeId: UUID? = nil,
        assigneeIds: [UUID] = [],
        areaId: UUID? = nil,
        dueDate: Date? = nil,
        notes: String? = nil
    ) async {
        guard let householdId else { return }

        // Check WIP limit
        if status == .next, !canMoveToNext(assigneeId: assigneeId) {
            error = TaskStoreError.wipLimitReached
            return
        }

        let resolvedAssigneeIds: [UUID] = if !assigneeIds.isEmpty {
            assigneeIds
        } else if let assigneeId {
            [assigneeId]
        } else {
            []
        }

        let task = Task(
            householdId: householdId,
            title: title,
            status: status,
            assigneeId: assigneeId,
            assigneeIds: resolvedAssigneeIds,
            areaId: areaId,
            dueDate: dueDate,
            taskType: .oneOff,
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
            await notificationService.scheduleTaskReminder(for: task)
            return
        }

        // Sync to CloudKit
        do {
            _ = try await cloudKit.saveTask(task)
            cached.syncStatusRaw = "synced"
            cached.lastSyncedAt = Date()
            try? modelContext.save()

            // Schedule notification if task has due date
            await notificationService.scheduleTaskReminder(for: task)
        } catch {
            self.error = error
        }
    }

    func updateTask(_ task: Task) async {
        var updatedTask = task
        updatedTask.updatedAt = Date()

        // Check WIP limit if moving to next
        let wipAssigneeId = task.assigneeId ?? task.assigneeIds.first
        if task.status == .next, !canMoveToNext(assigneeId: wipAssigneeId) {
            error = TaskStoreError.wipLimitReached
            return
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
            await notificationService.scheduleTaskReminder(for: updatedTask)
            return
        }

        // Sync to CloudKit
        do {
            _ = try await cloudKit.saveTask(updatedTask)

            // Update notification (remove old, schedule new if due date changed)
            await notificationService.scheduleTaskReminder(for: updatedTask)
        } catch {
            self.error = error
        }
    }

    func moveTask(_ task: Task, to status: Task.TaskStatus) async {
        var updatedTask = task
        updatedTask.status = status
        updatedTask.updatedAt = Date()

        if status == .done {
            updatedTask.completedAt = Date()
        }

        await updateTask(updatedTask)
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
}

enum TaskStoreError: LocalizedError, Equatable {
    case wipLimitReached

    var errorDescription: String? {
        switch self {
        case .wipLimitReached:
            "WIP limit reached. Complete or move existing tasks before adding more to Next."
        }
    }
}
