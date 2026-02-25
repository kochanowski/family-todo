import Foundation
import SwiftUI

struct BacklogCategory: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var title: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID,
        title: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.title = title
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
    /// Palette of cheerful, stable colors used for category tagging.
    static let categoryPalette: [Color] = [
        .purple,
        .orange,
        .teal,
        .pink,
        .indigo,
        .mint,
        .brown,
        .cyan,
        Color(red: 0.95, green: 0.4, blue: 0.3), // coral
        Color(red: 0.3, green: 0.7, blue: 0.4), // emerald
        Color(red: 0.6, green: 0.2, blue: 0.8), // violet
        Color(red: 0.2, green: 0.6, blue: 0.9), // sky blue
        Color(red: 0.9, green: 0.6, blue: 0.1), // amber
        Color(red: 0.4, green: 0.8, blue: 0.7), // aquamarine
        Color(red: 0.85, green: 0.3, blue: 0.5), // rose
        Color(red: 0.5, green: 0.7, blue: 0.2) // lime
    ]

    /// Deterministic color derived from category id.
    var color: Color {
        let hash = abs(id.hashValue)
        return Self.categoryPalette[hash % Self.categoryPalette.count]
    }
}
