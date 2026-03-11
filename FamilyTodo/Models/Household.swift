import Foundation

struct Household: Identifiable, Codable {
    let id: UUID
    var name: String
    var iconSymbol: String
    let ownerId: String
    var activeShopperId: String?
    let createdAt: Date
    var updatedAt: Date
    // Legacy/Test helper properties - keeping for compatibility during refactor
    var members: [Member] = []
    var areas: [Area] = []

    init(
        id: UUID = UUID(),
        name: String = "",
        iconSymbol: String = "house.fill",
        ownerId: String = "",
        activeShopperId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.ownerId = ownerId
        self.activeShopperId = activeShopperId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case iconSymbol
        case ownerId
        case activeShopperId
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol) ?? "house.fill"
        ownerId = try container.decode(String.self, forKey: .ownerId)
        activeShopperId = try container.decodeIfPresent(String.self, forKey: .activeShopperId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(iconSymbol, forKey: .iconSymbol)
        try container.encode(ownerId, forKey: .ownerId)
        try container.encodeIfPresent(activeShopperId, forKey: .activeShopperId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
