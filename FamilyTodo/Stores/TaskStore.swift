import Combine
import Foundation
import SwiftData

/// Main store for task management with offline-first architecture.
/// Follows ADR-002: optimistic UI updates with background sync.
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [Task] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private lazy var cloudKit = CloudKitManager.shared
    private let modelContext: ModelContext
    private var householdId: UUID?

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

    func createTask(title: String, status: Task.TaskStatus = .backlog, assigneeId: UUID? = nil, areaId: UUID? = nil, dueDate: Date? = nil, notes: String? = nil) async {
        guard let householdId else { return }

        // Check WIP limit
        if status == .next, !canMoveToNext(assigneeId: assigneeId) {
            error = TaskStoreError.wipLimitReached
            return
        }

        let task = Task(
            householdId: householdId,
            title: title,
            status: status,
            assigneeId: assigneeId,
            areaId: areaId,
            dueDate: dueDate,
            taskType: .oneOff,
            notes: notes
        )

        // Optimistic UI update
        tasks.append(task)

        // Save to cache
        let cached = CachedTask(from: task)
        cached.needsSync = true
        modelContext.insert(cached)
        try? modelContext.save()

        // Sync to CloudKit
        do {
            _ = try await cloudKit.saveTask(task)
            cached.needsSync = false
            cached.lastSyncedAt = Date()
            try? modelContext.save()
        } catch {
            self.error = error
        }
    }

    func updateTask(_ task: Task) async {
        var updatedTask = task
        updatedTask.updatedAt = Date()

        // Check WIP limit if moving to next
        if task.status == .next, !canMoveToNext(assigneeId: task.assigneeId) {
            error = TaskStoreError.wipLimitReached
            return
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
            cached.needsSync = true
            try? modelContext.save()
        }

        // Sync to CloudKit
        do {
            _ = try await cloudKit.saveTask(updatedTask)
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
        tasks.removeAll { $0.id == task.id }

        // Remove from cache
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == task.id }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            modelContext.delete(cached)
            try? modelContext.save()
        }

        // Delete from CloudKit
        do {
            try await cloudKit.deleteTask(id: task.id)
        } catch {
            self.error = error
        }
    }
}

enum TaskStoreError: LocalizedError {
    case wipLimitReached

    var errorDescription: String? {
        switch self {
        case .wipLimitReached:
            "WIP limit reached. Complete or move existing tasks before adding more to Next."
        }
    }
}
