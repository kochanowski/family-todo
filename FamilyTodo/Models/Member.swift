import Foundation
import SwiftUI

enum MemberColorToken: String, CaseIterable, Codable {
    case systemRed = "FF3B30"
    case systemOrange = "FF9500"
    case systemYellow = "FFCC00"
    case systemGreen = "34C759"
    case systemMint = "00C7BE"
    case systemTeal = "30B0C7"
    case systemBlue = "007AFF"
    case systemIndigo = "5856D6"
    case systemPurple = "AF52DE"
    case systemPink = "FF2D55"

    static let fallbackHex = MemberColorToken.systemBlue.hex

    var hex: String {
        "#\(rawValue)"
    }

    static func randomHex() -> String {
        allCases.randomElement()?.hex ?? fallbackHex
    }

    static func defaultHex(for memberId: UUID) -> String {
        migratedHex(for: memberId)
    }

    static func migratedHex(for stableId: UUID) -> String {
        let compact = stableId.uuidString.replacingOccurrences(of: "-", with: "")
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

    static func foregroundForBadge(hex: String) -> Color {
        guard let normalized = normalize(hex: hex) else { return .white }
        let hexValue = String(normalized.dropFirst())
        guard let intValue = Int(hexValue, radix: 16) else { return .white }

        let red = Double((intValue >> 16) & 0xFF) / 255
        let green = Double((intValue >> 8) & 0xFF) / 255
        let blue = Double(intValue & 0xFF) / 255
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)

        return luminance > 0.64 ? .black : .white
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
        let normalizedColor = MemberColorToken.normalize(hex: colorHex)
        let resolvedColorHex: String = if let normalizedColor, MemberColorToken.isAllowed(hex: normalizedColor) {
            normalizedColor
        } else {
            MemberColorToken.migratedHex(for: id)
        }
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
        let normalizedColor = MemberColorToken.normalize(hex: decodedColor)
        if let normalizedColor, MemberColorToken.isAllowed(hex: normalizedColor) {
            colorHex = normalizedColor
        } else {
            colorHex = MemberColorToken.migratedHex(for: decodedID)
        }
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
