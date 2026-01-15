import Foundation

struct Household: Identifiable, Codable {
    let id: UUID
    var name: String
    let ownerId: String
    let createdAt: Date
    var updatedAt: Date

    var members: [Member]
    var areas: [Area]

    init(
        id: UUID = UUID(),
        name: String,
        ownerId: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        members: [Member] = [],
        areas: [Area] = []
    ) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.members = members
        self.areas = areas
    }
}
