import Foundation
import SwiftUI

struct BacklogCategory: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    var title: String
    var colorHex: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID,
        title: String,
        colorHex: String = MemberColorToken.fallbackHex,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.title = title
        let normalizedColor = MemberColorToken.normalize(hex: colorHex)
        if let normalizedColor, MemberColorToken.isAllowed(hex: normalizedColor) {
            self.colorHex = normalizedColor
        } else {
            self.colorHex = MemberColorToken.migratedHex(for: id)
        }
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct BacklogItem: Identifiable, Codable {
    let id: UUID
    let logicalItemID: UUID
    let categoryId: UUID
    let householdId: UUID
    var title: String
    var assigneeId: UUID?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case logicalItemID
        case categoryId
        case householdId
        case title
        case assigneeId
        case notes
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        logicalItemID: UUID? = nil,
        categoryId: UUID,
        householdId: UUID,
        title: String,
        assigneeId: UUID? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.logicalItemID = logicalItemID ?? id
        self.categoryId = categoryId
        self.householdId = householdId
        self.title = title
        self.assigneeId = assigneeId
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decode(UUID.self, forKey: .id)

        id = decodedID
        logicalItemID = try container.decodeIfPresent(UUID.self, forKey: .logicalItemID) ?? decodedID
        categoryId = try container.decode(UUID.self, forKey: .categoryId)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        title = try container.decode(String.self, forKey: .title)
        assigneeId = try container.decodeIfPresent(UUID.self, forKey: .assigneeId)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

extension BacklogCategory {
    var color: Color {
        Color(hex: colorHex)
    }
}
