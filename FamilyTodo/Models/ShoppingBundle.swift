import Foundation

struct ShoppingBundle: Identifiable, Codable, Hashable {
    static let defaultIcon = "shippingbox.fill"
    static let curatedIcons = [
        "shippingbox.fill",
        "cube.box.fill",
        "archivebox.fill",
        "shippingbox",
        "cube.box",
        "archivebox",
        "cart.fill",
        "basket.fill",
        "bag.fill",
        "fork.knife",
        "cup.and.saucer.fill",
        "birthday.cake.fill",
        "wineglass.fill",
        "fish.fill",
        "carrot.fill",
        "sparkles",
        "drop.fill",
        "leaf.fill",
        "house.fill",
        "pawprint.fill",
        "car.fill",
        "gift.fill",
        "shower.fill",
        "cross.case.fill",
        "pill.fill",
        "bandage.fill",
        "heart.fill",
        "star.fill",
        "moon.stars.fill",
        "sun.max.fill",
        "snowflake",
        "flame.fill",
        "lightbulb.fill",
        "book.fill",
        "paintpalette.fill",
        "music.note",
    ]
    private static let curatedIconLabels = [
        "shippingbox.fill": "Shipping box",
        "cube.box.fill": "Packed box",
        "archivebox.fill": "Archive box",
        "shippingbox": "Shipping box outline",
        "cube.box": "Packed box outline",
        "archivebox": "Archive box outline",
        "cart.fill": "Shopping cart",
        "basket.fill": "Market basket",
        "bag.fill": "Shopping bag",
        "fork.knife": "Meal plan",
        "cup.and.saucer.fill": "Breakfast",
        "birthday.cake.fill": "Celebration",
        "wineglass.fill": "Drinks",
        "fish.fill": "Seafood",
        "carrot.fill": "Produce",
        "sparkles": "Cleaning",
        "drop.fill": "Bathroom",
        "leaf.fill": "Fresh",
        "house.fill": "Home",
        "pawprint.fill": "Pets",
        "car.fill": "Car",
        "gift.fill": "Party",
        "shower.fill": "Self care",
        "cross.case.fill": "Pharmacy",
        "pill.fill": "Medicine",
        "bandage.fill": "First aid",
        "heart.fill": "Favorites",
        "star.fill": "Special",
        "moon.stars.fill": "Evening",
        "sun.max.fill": "Sunny day",
        "snowflake": "Frozen",
        "flame.fill": "Grill",
        "lightbulb.fill": "Household essentials",
        "book.fill": "School",
        "paintpalette.fill": "Crafts",
        "music.note": "Entertainment",
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
        curatedIconLabels[resolvedIconName(icon)] ?? "Bundle"
    }
}
