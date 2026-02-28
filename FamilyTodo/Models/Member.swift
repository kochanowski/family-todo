import Foundation

enum MemberColorToken: String, CaseIterable, Codable {
    case pastelPink = "F8BBD0"
    case pastelPeach = "FFD1BA"
    case pastelOrange = "FFCCB3"
    case pastelYellow = "FFF3B0"
    case pastelMint = "B8F2E6"
    case pastelGreen = "CDEAC0"
    case pastelBlue = "BDE0FE"
    case pastelPurple = "D7C0F1"
    case pastelLavender = "E4C1F9"
    case pastelCoral = "FFB4A2"

    static let fallbackHex = MemberColorToken.pastelBlue.hex

    var hex: String {
        "#\(rawValue)"
    }

    static func defaultHex(for memberId: UUID) -> String {
        let compact = memberId.uuidString.replacingOccurrences(of: "-", with: "")
        let seed = Int(compact.suffix(6), radix: 16) ?? 0
        let token = allCases[seed % allCases.count]
        return token.hex
    }

    static func isAllowed(hex: String) -> Bool {
        guard let normalized = normalize(hex: hex) else { return false }
        return allCases.contains { $0.hex == normalized }
    }

    static func normalize(hex: String?) -> String? {
        guard let hex else { return nil }
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()

        guard cleaned.count == 6 else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard cleaned.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return "#\(cleaned)"
    }
}

struct Member: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    let userId: String
    var displayName: String
    let role: MemberRole
    let joinedAt: Date
    var isActive: Bool
    var colorHex: String

    enum MemberRole: String, Codable {
        case owner
        case member
    }

    init(
        id: UUID = UUID(),
        householdId: UUID,
        userId: String,
        displayName: String,
        role: MemberRole,
        joinedAt: Date = Date(),
        isActive: Bool = true,
        colorHex: String? = nil
    ) {
        let resolvedColorHex = MemberColorToken.normalize(hex: colorHex) ?? MemberColorToken.defaultHex(for: id)
        self.id = id
        self.householdId = householdId
        self.userId = userId
        self.displayName = displayName
        self.role = role
        self.joinedAt = joinedAt
        self.isActive = isActive
        self.colorHex = resolvedColorHex
    }

    enum CodingKeys: String, CodingKey {
        case id
        case householdId
        case userId
        case displayName
        case role
        case joinedAt
        case isActive
        case colorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decode(UUID.self, forKey: .id)
        let decodedColor = try container.decodeIfPresent(String.self, forKey: .colorHex)

        id = decodedID
        householdId = try container.decode(UUID.self, forKey: .householdId)
        userId = try container.decode(String.self, forKey: .userId)
        displayName = try container.decode(String.self, forKey: .displayName)
        role = try container.decode(MemberRole.self, forKey: .role)
        joinedAt = try container.decode(Date.self, forKey: .joinedAt)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        colorHex = MemberColorToken.normalize(hex: decodedColor) ?? MemberColorToken.defaultHex(for: decodedID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(userId, forKey: .userId)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(role, forKey: .role)
        try container.encode(joinedAt, forKey: .joinedAt)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(colorHex, forKey: .colorHex)
    }
}
