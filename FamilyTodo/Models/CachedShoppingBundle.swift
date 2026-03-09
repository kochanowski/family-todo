import Foundation
import SwiftData

/// SwiftData model for offline caching of ShoppingBundle.
/// Follows ADR-002: offline-first with optimistic UI updates.
@Model
final class CachedShoppingBundle {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var name: String
    var icon: String
    var itemsJSON: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    // Sync metadata
    var syncStatusRaw: String = "synced"
    var lastSyncedAt: Date?
    var ckRecordIDData: Data?
    var ckSystemFieldsData: Data?

    init(from bundle: ShoppingBundle) {
        id = bundle.id
        householdId = bundle.householdId
        name = bundle.normalizedName
        icon = bundle.resolvedIcon
        itemsJSON = ShoppingBundle.encodeItemsJSON(bundle.normalizedItems)
        sortOrder = bundle.sortOrder
        createdAt = bundle.createdAt
        updatedAt = bundle.updatedAt
        syncStatusRaw = "synced"
        lastSyncedAt = Date()
    }

    func update(from bundle: ShoppingBundle) {
        householdId = bundle.householdId
        name = bundle.normalizedName
        icon = bundle.resolvedIcon
        itemsJSON = ShoppingBundle.encodeItemsJSON(bundle.normalizedItems)
        sortOrder = bundle.sortOrder
        createdAt = bundle.createdAt
        updatedAt = bundle.updatedAt
        lastSyncedAt = Date()
        syncStatusRaw = "synced"
    }

    func toShoppingBundle() -> ShoppingBundle {
        ShoppingBundle(
            id: id,
            householdId: householdId,
            name: name,
            icon: icon,
            items: ShoppingBundle.decodeItemsJSON(itemsJSON),
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
