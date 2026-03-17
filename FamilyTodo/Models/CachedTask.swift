import Foundation
import SwiftData

/// SwiftData model for offline caching of Tasks.
/// Follows ADR-002: offline-first with optimistic UI updates.
@Model
final class CachedTask {
    @Attribute(.unique) var id: UUID
    var logicalItemID: UUID?
    var householdId: UUID
    var title: String
    var statusRaw: String
    var assigneeId: UUID?
    var assigneeIdsData: Data?
    var backlogCategoryId: UUID?
    var areaId: UUID?
    var dueDate: Date?
    var lastPokedAt: Date?
    var completedAt: Date?
    var completedById: String?
    var taskTypeRaw: String
    var recurringChoreId: UUID?
    var notes: String?
    var order: Int = 0
    var createdAt: Date
    var updatedAt: Date

    // Sync metadata
    var syncStatusRaw: String = "synced"
    var lastSyncedAt: Date?
    var ckRecordIDData: Data?
    var ckSystemFieldsData: Data?

    init(from task: Task) {
        id = task.id
        logicalItemID = task.logicalItemID
        householdId = task.householdId
        title = task.title
        statusRaw = task.status.rawValue
        assigneeId = task.assigneeId
        assigneeIdsData = Self.encodeAssigneeIds(task.assigneeIds)
        backlogCategoryId = task.backlogCategoryId
        areaId = task.areaId
        dueDate = task.dueDate
        lastPokedAt = task.lastPokedAt
        completedAt = task.completedAt
        completedById = task.completedById
        taskTypeRaw = task.taskType.rawValue
        recurringChoreId = task.recurringChoreId
        notes = task.notes
        order = task.order
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        syncStatusRaw = "synced"
        lastSyncedAt = Date()
    }

    func update(from task: Task) {
        logicalItemID = task.logicalItemID
        title = task.title
        statusRaw = task.status.rawValue
        assigneeId = task.assigneeId
        assigneeIdsData = Self.encodeAssigneeIds(task.assigneeIds)
        backlogCategoryId = task.backlogCategoryId
        areaId = task.areaId
        dueDate = task.dueDate
        lastPokedAt = task.lastPokedAt
        completedAt = task.completedAt
        completedById = task.completedById
        notes = task.notes
        order = task.order
        updatedAt = task.updatedAt
        lastSyncedAt = Date()
    }

    func toTask() -> Task {
        Task(
            id: id,
            logicalItemID: logicalItemID ?? id,
            householdId: householdId,
            title: title,
            status: Task.TaskStatus(rawValue: statusRaw) ?? .backlog,
            assigneeId: assigneeId,
            assigneeIds: Self.decodeAssigneeIds(assigneeIdsData),
            backlogCategoryId: backlogCategoryId,
            areaId: areaId,
            dueDate: dueDate,
            lastPokedAt: lastPokedAt,
            completedAt: completedAt,
            completedById: completedById,
            taskType: Task.TaskType(rawValue: taskTypeRaw) ?? .oneOff,
            recurringChoreId: recurringChoreId,
            notes: notes,
            order: order,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    var status: Task.TaskStatus {
        get { Task.TaskStatus(rawValue: statusRaw) ?? .backlog }
        set { statusRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .synced }
        set { syncStatusRaw = newValue.rawValue }
    }

    private static func encodeAssigneeIds(_ ids: [UUID]) -> Data? {
        try? JSONEncoder().encode(ids)
    }

    private static func decodeAssigneeIds(_ data: Data?) -> [UUID] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
    }
}

// MARK: - Sync Status

enum SyncStatus: String {
    case synced
    case pendingUpload
    case pendingDelete
    case conflict
}
