import Foundation
import SwiftData

/// SwiftData model for offline caching of ShoppingItem.
/// Follows ADR-002: offline-first with optimistic UI updates.
@Model
final class CachedShoppingItem {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var title: String
    var quantityValue: String?
    var quantityUnit: String?
    var isBought: Bool
    var boughtAt: Date?
    var restockCount: Int
    var createdAt: Date
    var updatedAt: Date

    // Sync metadata
    var syncStatusRaw: String = "synced"
    var lastSyncedAt: Date?
    var ckRecordIDData: Data?
    var ckSystemFieldsData: Data?

    init(from item: ShoppingItem) {
        id = item.id
        householdId = item.householdId
        title = item.title
        quantityValue = item.quantityValue
        quantityUnit = item.quantityUnit
        isBought = item.isBought
        boughtAt = item.boughtAt
        restockCount = item.restockCount
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        syncStatusRaw = "synced"
        lastSyncedAt = Date()
    }

    func update(from item: ShoppingItem) {
        householdId = item.householdId
        title = item.title
        quantityValue = item.quantityValue
        quantityUnit = item.quantityUnit
        isBought = item.isBought
        boughtAt = item.boughtAt
        restockCount = item.restockCount
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        lastSyncedAt = Date()
        syncStatusRaw = "synced"
    }

    func toShoppingItem() -> ShoppingItem {
        ShoppingItem(
            id: id,
            householdId: householdId,
            title: title,
            quantityValue: quantityValue,
            quantityUnit: quantityUnit,
            isBought: isBought,
            boughtAt: boughtAt,
            restockCount: restockCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
