import Foundation
import UIKit

struct ShoppingBundle: Identifiable, Codable, Hashable {
    static let defaultIcon = "shippingbox.fill"
    static let foodIcons = [
        "fork.knife",
        "fork.knife.circle.fill",
        "takeoutbag.and.cup.and.straw.fill",
        "cup.and.saucer.fill",
        "mug.fill",
        "birthday.cake.fill",
        "wineglass.fill",
        "fish.fill",
        "carrot.fill",
        "popcorn.fill",
        "refrigerator.fill",
        "waterbottle.fill",
    ]
    static let homeIcons = [
        "house.fill",
        "lightbulb.fill",
        "drop.fill",
        "shower.fill",
        "bed.double.fill",
        "sun.max.fill",
        "moon.stars.fill",
        "pawprint.fill",
        "car.fill",
        "cross.case.fill",
        "pill.fill",
        "bandage.fill",
    ]
    static let genericIcons = [
        "shippingbox.fill",
        "archivebox.fill",
        "sparkles",
        "gift.fill",
        "heart.fill",
        "star.fill",
        "book.fill",
        "paintpalette.fill",
        "music.note",
        "bell.fill",
        "tag.fill",
        "hammer.fill",
    ]
    static let curatedIcons = foodIcons + homeIcons + genericIcons
    static let curatedIconGroups = [
        CuratedIconGroup(title: "Food", icons: foodIcons),
        CuratedIconGroup(title: "Home", icons: homeIcons),
        CuratedIconGroup(title: "Generic", icons: genericIcons),
    ]
    private static let curatedIconLabels = [
        "fork.knife": "Meal",
        "fork.knife.circle.fill": "Dinner",
        "takeoutbag.and.cup.and.straw.fill": "Takeout",
        "cup.and.saucer.fill": "Breakfast",
        "mug.fill": "Coffee",
        "birthday.cake.fill": "Celebration",
        "wineglass.fill": "Drinks",
        "fish.fill": "Seafood",
        "carrot.fill": "Produce",
        "popcorn.fill": "Snacks",
        "refrigerator.fill": "Fridge",
        "waterbottle.fill": "Beverages",
        "house.fill": "Home",
        "lightbulb.fill": "Household essentials",
        "drop.fill": "Bathroom",
        "shower.fill": "Self care",
        "bed.double.fill": "Bedroom",
        "sun.max.fill": "Daytime",
        "moon.stars.fill": "Evening",
        "pawprint.fill": "Pets",
        "car.fill": "Car",
        "cross.case.fill": "Pharmacy",
        "pill.fill": "Medicine",
        "bandage.fill": "First aid",
        "shippingbox.fill": "Bundle",
        "archivebox.fill": "Archive box",
        "sparkles": "Cleaning",
        "gift.fill": "Party",
        "heart.fill": "Favorites",
        "star.fill": "Special",
        "book.fill": "School",
        "paintpalette.fill": "Crafts",
        "music.note": "Entertainment",
        "bell.fill": "Reminder",
        "tag.fill": "Tagged",
        "hammer.fill": "Tools",
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
        UIImage(systemName: icon) != nil ? icon : defaultIcon
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

struct CuratedIconGroup: Identifiable, Hashable {
    let title: String
    let icons: [String]

    var id: String {
        title
    }
}
