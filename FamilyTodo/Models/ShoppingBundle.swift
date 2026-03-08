import Foundation

struct ShoppingBundle: Identifiable, Codable, Hashable {
    static let defaultIcon = "archivebox.fill"
    static let curatedIcons = [
        "archivebox.fill",
        "cart.fill",
        "fork.knife",
        "cup.and.saucer.fill",
        "sparkles",
        "drop.fill",
        "leaf.fill",
        "house.fill",
        "pawprint.fill",
        "car.fill",
        "gift.fill",
        "shower.fill",
    ]

    let id: UUID
    let householdId: UUID
    var name: String
    var icon: String
    var items: [String]
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID,
        name: String,
        icon: String = ShoppingBundle.defaultIcon,
        items: [String] = [],
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.name = Self.sanitizedName(name)
        self.icon = Self.resolvedIconName(icon)
        self.items = Self.sanitizedItems(items)
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var normalizedName: String {
        Self.sanitizedName(name)
    }

    var normalizedItems: [String] {
        Self.sanitizedItems(items)
    }

    var resolvedIcon: String {
        Self.resolvedIconName(icon)
    }

    var itemCount: Int {
        normalizedItems.count
    }

    static func sanitizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitizedItems(_ items: [String]) -> [String] {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func resolvedIconName(_ icon: String) -> String {
        curatedIcons.contains(icon) ? icon : defaultIcon
    }

    static func encodeItemsJSON(_ items: [String]) -> String {
        let cleanedItems = sanitizedItems(items)
        guard let data = try? JSONEncoder().encode(cleanedItems),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    static func decodeItemsJSON(_ itemsJSON: String) -> [String] {
        guard let data = itemsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return sanitizedItems(decoded)
    }

    static func iconLabel(for icon: String) -> String {
        switch resolvedIconName(icon) {
        case "archivebox.fill":
            "Essentials"
        case "cart.fill":
            "Groceries"
        case "fork.knife":
            "Recipe"
        case "cup.and.saucer.fill":
            "Breakfast"
        case "sparkles":
            "Cleaning"
        case "drop.fill":
            "Bathroom"
        case "leaf.fill":
            "Fresh produce"
        case "house.fill":
            "Home"
        case "pawprint.fill":
            "Pets"
        case "car.fill":
            "Car"
        case "gift.fill":
            "Party"
        case "shower.fill":
            "Self care"
        default:
            "Bundle"
        }
    }
}
