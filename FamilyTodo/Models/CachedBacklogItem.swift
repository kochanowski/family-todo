import Foundation
import SwiftData

/// SwiftData model for offline caching of BacklogItem.
/// Follows ADR-002: offline-first with optimistic UI updates.
@Model
final class CachedBacklogItem {
    @Attribute(.unique) var id: UUID
    var categoryId: UUID
    var householdId: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    // Sync metadata
    var syncStatusRaw: String = "synced"
    var lastSyncedAt: Date?
    var ckRecordIDData: Data?
    var ckSystemFieldsData: Data?

    init(from item: BacklogItem) {
        id = item.id
        categoryId = item.categoryId
        householdId = item.householdId
        title = item.title
        notes = item.notes
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        syncStatusRaw = "synced"
        lastSyncedAt = Date()
    }

    func update(from item: BacklogItem) {
        categoryId = item.categoryId
        householdId = item.householdId
        title = item.title
        notes = item.notes
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        lastSyncedAt = Date()
        syncStatusRaw = "synced"
    }

    func toBacklogItem() -> BacklogItem {
        BacklogItem(
            id: id,
            categoryId: categoryId,
            householdId: householdId,
            title: title,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
