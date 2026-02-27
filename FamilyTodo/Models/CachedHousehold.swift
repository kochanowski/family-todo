import Foundation
import SwiftData

@Model
final class CachedHousehold {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconSymbol: String
    var ownerId: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        iconSymbol: String = "house.fill",
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from household: Household) {
        id = household.id
        name = household.name
        iconSymbol = household.iconSymbol
        ownerId = household.ownerId
        createdAt = household.createdAt
        updatedAt = household.updatedAt
    }

    func toHousehold() -> Household {
        Household(
            id: id,
            name: name,
            iconSymbol: iconSymbol,
            ownerId: ownerId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from household: Household) {
        name = household.name
        iconSymbol = household.iconSymbol
        ownerId = household.ownerId
        updatedAt = household.updatedAt
    }
}
