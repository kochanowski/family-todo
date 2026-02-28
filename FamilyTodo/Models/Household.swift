import Foundation

struct Household: Identifiable, Codable {
    let id: UUID
    var name: String
    var colorHex: String
    var iconSymbol: String
    let ownerId: String
    let createdAt: Date
    var updatedAt: Date
    // Legacy/Test helper properties - keeping for compatibility during refactor
    var members: [Member] = []
    var areas: [Area] = []

    init(
        id: UUID = UUID(),
        name: String = "",
        colorHex: String = MemberColorToken.fallbackHex,
        iconSymbol: String = "house.fill",
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        let normalizedColor = MemberColorToken.normalize(hex: colorHex)
        if let normalizedColor, MemberColorToken.isAllowed(hex: normalizedColor) {
            self.colorHex = normalizedColor
        } else {
            self.colorHex = MemberColorToken.migratedHex(for: id)
        }
        self.iconSymbol = iconSymbol
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex
        case iconSymbol
        case ownerId
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedId = try container.decode(UUID.self, forKey: .id)
        let decodedColor = try container.decodeIfPresent(String.self, forKey: .colorHex)

        id = decodedId
        name = try container.decode(String.self, forKey: .name)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol) ?? "house.fill"
        ownerId = try container.decode(String.self, forKey: .ownerId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        let normalizedColor = MemberColorToken.normalize(hex: decodedColor)
        if let normalizedColor, MemberColorToken.isAllowed(hex: normalizedColor) {
            colorHex = normalizedColor
        } else {
            colorHex = MemberColorToken.migratedHex(for: decodedId)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(iconSymbol, forKey: .iconSymbol)
        try container.encode(ownerId, forKey: .ownerId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
