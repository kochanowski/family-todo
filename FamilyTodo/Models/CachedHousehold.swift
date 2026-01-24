import Foundation
import SwiftData

/// SwiftData model for offline caching of Household.
/// Follows ADR-002: offline-first with optimistic UI updates.
@Model
final class CachedHousehold {
    @Attribute(.unique) var id: UUID
    var name: String
    var ownerId: String
    var createdAt: Date
    var updatedAt: Date

    // Sync metadata
    var syncStatusRaw: String = "synced"
    var lastSyncedAt: Date?
    var ckRecordIDData: Data?
    var ckSystemFieldsData: Data?

    init(from household: Household) {
        id = household.id
        name = household.name
        ownerId = household.ownerId
        createdAt = household.createdAt
        updatedAt = household.updatedAt
        syncStatusRaw = "synced"
        lastSyncedAt = Date()
    }

    func update(from household: Household) {
        name = household.name
        ownerId = household.ownerId
        createdAt = household.createdAt
        updatedAt = household.updatedAt
        lastSyncedAt = Date()
        syncStatusRaw = "synced"
    }

    func toHousehold() -> Household {
        Household(
            id: id,
            name: name,
            ownerId: ownerId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            members: [],
            areas: []
        )
    }
}
