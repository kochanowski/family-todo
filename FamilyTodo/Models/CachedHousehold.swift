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
        self.id = household.id
        self.name = household.name
        self.ownerId = household.ownerId
        self.createdAt = household.createdAt
        self.updatedAt = household.updatedAt
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
        self.name = household.name
        self.ownerId = household.ownerId
        self.updatedAt = household.updatedAt
    }
}
