import Foundation
import SwiftData

/// SwiftData model for offline caching of RecurringChore.
/// Follows ADR-002: offline-first with optimistic UI updates.
@Model
final class CachedRecurringChore {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var title: String
    var recurrenceTypeRaw: String
    var recurrenceDay: Int?
    var recurrenceDayOfMonth: Int?
    var recurrenceInterval: Int?
    var defaultAssigneeIdsData: Data?
    var areaId: UUID?
    var isActive: Bool
    var lastGeneratedDate: Date?
    var nextScheduledDate: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    // Sync metadata
    var syncStatusRaw: String = "synced"
    var lastSyncedAt: Date?
    var ckRecordIDData: Data?
    var ckSystemFieldsData: Data?

    init(from chore: RecurringChore) {
        id = chore.id
        householdId = chore.householdId
        title = chore.title
        recurrenceTypeRaw = chore.recurrenceType.rawValue
        recurrenceDay = chore.recurrenceDay
        recurrenceDayOfMonth = chore.recurrenceDayOfMonth
        recurrenceInterval = chore.recurrenceInterval
        defaultAssigneeIdsData = try? JSONEncoder().encode(chore.defaultAssigneeIds)
        areaId = chore.areaId
        isActive = chore.isActive
        lastGeneratedDate = chore.lastGeneratedDate
        nextScheduledDate = chore.nextScheduledDate
        notes = chore.notes
        createdAt = chore.createdAt
        updatedAt = chore.updatedAt
        syncStatusRaw = "synced"
        lastSyncedAt = Date()
    }

    func update(from chore: RecurringChore) {
        householdId = chore.householdId
        title = chore.title
        recurrenceTypeRaw = chore.recurrenceType.rawValue
        recurrenceDay = chore.recurrenceDay
        recurrenceDayOfMonth = chore.recurrenceDayOfMonth
        recurrenceInterval = chore.recurrenceInterval
        defaultAssigneeIdsData = try? JSONEncoder().encode(chore.defaultAssigneeIds)
        areaId = chore.areaId
        isActive = chore.isActive
        lastGeneratedDate = chore.lastGeneratedDate
        nextScheduledDate = chore.nextScheduledDate
        notes = chore.notes
        createdAt = chore.createdAt
        updatedAt = chore.updatedAt
        lastSyncedAt = Date()
        syncStatusRaw = "synced"
    }

    func toRecurringChore() -> RecurringChore {
        let defaultAssigneeIds: [UUID]
        if let data = defaultAssigneeIdsData {
            defaultAssigneeIds = (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        } else {
            defaultAssigneeIds = []
        }

        return RecurringChore(
            id: id,
            householdId: householdId,
            title: title,
            recurrenceType: RecurringChore.RecurrenceType(rawValue: recurrenceTypeRaw) ?? .weekly,
            recurrenceDay: recurrenceDay,
            recurrenceDayOfMonth: recurrenceDayOfMonth,
            recurrenceInterval: recurrenceInterval,
            defaultAssigneeIds: defaultAssigneeIds,
            areaId: areaId,
            isActive: isActive,
            lastGeneratedDate: lastGeneratedDate,
            nextScheduledDate: nextScheduledDate,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
