import Foundation
import SwiftData

@Model
final class CachedHousehold {
    @Attribute(.unique) var id: UUID
    var name: String
    var ownerId: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from household: Household) {
        id = household.id
        name = household.name
        ownerId = household.ownerId
        createdAt = household.createdAt
        updatedAt = household.updatedAt
    }

    func toHousehold() -> Household {
        Household(
            id: id,
            name: name,
            ownerId: ownerId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from household: Household) {
        name = household.name
        ownerId = household.ownerId
        updatedAt = household.updatedAt
    }
}
