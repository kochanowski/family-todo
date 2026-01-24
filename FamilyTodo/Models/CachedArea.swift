import Foundation
import SwiftData

/// SwiftData model for offline caching of Area.
/// Follows ADR-002: offline-first with optimistic UI updates.
@Model
final class CachedArea {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var name: String
    var icon: String?
    var sortOrder: Int
    var createdAt: Date

    // Sync metadata
    var syncStatusRaw: String = "synced"
    var lastSyncedAt: Date?
    var ckRecordIDData: Data?
    var ckSystemFieldsData: Data?

    init(from area: Area) {
        id = area.id
        householdId = area.householdId
        name = area.name
        icon = area.icon
        sortOrder = area.sortOrder
        createdAt = area.createdAt
        syncStatusRaw = "synced"
        lastSyncedAt = Date()
    }

    func update(from area: Area) {
        householdId = area.householdId
        name = area.name
        icon = area.icon
        sortOrder = area.sortOrder
        createdAt = area.createdAt
        lastSyncedAt = Date()
        syncStatusRaw = "synced"
    }

    func toArea() -> Area {
        Area(
            id: id,
            householdId: householdId,
            name: name,
            icon: icon,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }
}
