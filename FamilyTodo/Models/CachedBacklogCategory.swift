import Foundation
import SwiftData

/// SwiftData model for offline caching of BacklogCategory.
/// Follows ADR-002: offline-first with optimistic UI updates.
@Model
final class CachedBacklogCategory {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var title: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    // Sync metadata
    var syncStatusRaw: String = "synced"
    var lastSyncedAt: Date?
    var ckRecordIDData: Data?
    var ckSystemFieldsData: Data?

    init(from category: BacklogCategory) {
        id = category.id
        householdId = category.householdId
        title = category.title
        sortOrder = category.sortOrder
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        syncStatusRaw = "synced"
        lastSyncedAt = Date()
    }

    func update(from category: BacklogCategory) {
        householdId = category.householdId
        title = category.title
        sortOrder = category.sortOrder
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        lastSyncedAt = Date()
        syncStatusRaw = "synced"
    }

    func toBacklogCategory() -> BacklogCategory {
        BacklogCategory(
            id: id,
            householdId: householdId,
            title: title,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
