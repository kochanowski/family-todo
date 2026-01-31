import Foundation

struct Household: Identifiable, Codable {
    let id: UUID
    var name: String
    let ownerId: String
    let createdAt: Date
    var updatedAt: Date
    // Legacy/Test helper properties - keeping for compatibility during refactor
    var members: [Member] = []
    var areas: [Area] = []

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
}
