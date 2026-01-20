import Foundation
import SwiftData

/// SwiftData model for offline caching of Tasks.
/// Follows ADR-002: offline-first with optimistic UI updates.
@Model
final class CachedTask {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var title: String
    var statusRaw: String
    var assigneeId: UUID?
    var assigneeIdsData: Data?
    var areaId: UUID?
    var dueDate: Date?
    var completedAt: Date?
    var completedById: String?
    var taskTypeRaw: String
    var recurringChoreId: UUID?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    /// Pending sync state
    var needsSync: Bool
    var lastSyncedAt: Date?

    init(from task: Task) {
        id = task.id
        householdId = task.householdId
        title = task.title
        statusRaw = task.status.rawValue
        assigneeId = task.assigneeId
        assigneeIdsData = Self.encodeAssigneeIds(task.assigneeIds)
        areaId = task.areaId
        dueDate = task.dueDate
        completedAt = task.completedAt
        completedById = task.completedById
        taskTypeRaw = task.taskType.rawValue
        recurringChoreId = task.recurringChoreId
        notes = task.notes
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        needsSync = false
        lastSyncedAt = Date()
    }

    func update(from task: Task) {
        title = task.title
        statusRaw = task.status.rawValue
        assigneeId = task.assigneeId
        assigneeIdsData = Self.encodeAssigneeIds(task.assigneeIds)
        areaId = task.areaId
        dueDate = task.dueDate
        completedAt = task.completedAt
        completedById = task.completedById
        notes = task.notes
        updatedAt = task.updatedAt
        lastSyncedAt = Date()
    }

    func toTask() -> Task {
        Task(
            id: id,
            householdId: householdId,
            title: title,
            status: Task.TaskStatus(rawValue: statusRaw) ?? .backlog,
            assigneeId: assigneeId,
            assigneeIds: Self.decodeAssigneeIds(assigneeIdsData),
            areaId: areaId,
            dueDate: dueDate,
            completedAt: completedAt,
            completedById: completedById,
            taskType: Task.TaskType(rawValue: taskTypeRaw) ?? .oneOff,
            recurringChoreId: recurringChoreId,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    var status: Task.TaskStatus {
        get { Task.TaskStatus(rawValue: statusRaw) ?? .backlog }
        set { statusRaw = newValue.rawValue }
    }

    private static func encodeAssigneeIds(_ ids: [UUID]) -> Data? {
        try? JSONEncoder().encode(ids)
    }

    private static func decodeAssigneeIds(_ data: Data?) -> [UUID] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
    }
}
