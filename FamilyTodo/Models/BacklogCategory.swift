import Foundation
import SwiftUI

struct BacklogCategory: Identifiable, Codable {
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
    let categoryId: UUID
    let householdId: UUID
    var title: String
    var assigneeId: UUID?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        categoryId: UUID,
        householdId: UUID,
        title: String,
        assigneeId: UUID? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.categoryId = categoryId
        self.householdId = householdId
        self.title = title
        self.assigneeId = assigneeId
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension BacklogCategory {
    var color: Color {
        Color(hex: colorHex)
    }
}
