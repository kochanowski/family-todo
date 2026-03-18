import Foundation
import SwiftData

@Model
final class CachedWorkItem {
    @Attribute(.unique) var id: UUID
    var logicalItemID: UUID
    var householdId: UUID
    var title: String
    var statusRaw: String
    var assigneeId: UUID?
    var assigneeIdsData: Data?
    var categoryId: UUID?
    var areaId: UUID?
    var dueDate: Date?
    var lastPokedAt: Date?
    var completedAt: Date?
    var completedById: String?
    var taskTypeRaw: String
    var recurringChoreId: UUID?
    var notes: String?
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    var syncStatusRaw: String = "synced"
    var lastSyncedAt: Date?
    var ckRecordIDData: Data?
    var ckSystemFieldsData: Data?

    init(from item: WorkItem) {
        id = item.id
        logicalItemID = item.logicalItemID
        householdId = item.householdId
        title = item.title
        statusRaw = item.status.rawValue
        assigneeId = item.assigneeId
        assigneeIdsData = Self.encodeAssigneeIds(item.assigneeIds)
        categoryId = item.categoryId
        areaId = item.areaId
        dueDate = item.dueDate
        lastPokedAt = item.lastPokedAt
        completedAt = item.completedAt
        completedById = item.completedById
        taskTypeRaw = item.taskType.rawValue
        recurringChoreId = item.recurringChoreId
        notes = item.notes
        order = item.order
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        syncStatusRaw = "synced"
        lastSyncedAt = Date()
    }

    func update(from item: WorkItem) {
        logicalItemID = item.logicalItemID
        householdId = item.householdId
        title = item.title
        statusRaw = item.status.rawValue
        assigneeId = item.assigneeId
        assigneeIdsData = Self.encodeAssigneeIds(item.assigneeIds)
        categoryId = item.categoryId
        areaId = item.areaId
        dueDate = item.dueDate
        lastPokedAt = item.lastPokedAt
        completedAt = item.completedAt
        completedById = item.completedById
        taskTypeRaw = item.taskType.rawValue
        recurringChoreId = item.recurringChoreId
        notes = item.notes
        order = item.order
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        lastSyncedAt = Date()
    }

    func toWorkItem() -> WorkItem {
        WorkItem(
            id: id,
            logicalItemID: logicalItemID,
            householdId: householdId,
            title: title,
            status: WorkItem.Status(rawValue: statusRaw) ?? .idea,
            assigneeId: assigneeId,
            assigneeIds: Self.decodeAssigneeIds(assigneeIdsData),
            categoryId: categoryId,
            areaId: areaId,
            dueDate: dueDate,
            lastPokedAt: lastPokedAt,
            completedAt: completedAt,
            completedById: completedById,
            taskType: WorkItem.ItemType(rawValue: taskTypeRaw) ?? .oneOff,
            recurringChoreId: recurringChoreId,
            notes: notes,
            order: order,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func encodeAssigneeIds(_ ids: [UUID]) -> Data? {
        try? JSONEncoder().encode(ids)
    }

    private static func decodeAssigneeIds(_ data: Data?) -> [UUID] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
    }
}
