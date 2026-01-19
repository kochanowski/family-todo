import Foundation

struct ShoppingItem: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var title: String
    var quantityValue: String?
    var quantityUnit: String?
    var isBought: Bool
    var boughtAt: Date?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID,
        title: String,
        quantityValue: String? = nil,
        quantityUnit: String? = nil,
        isBought: Bool = false,
        boughtAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.title = title
        self.quantityValue = quantityValue
        self.quantityUnit = quantityUnit
        self.isBought = isBought
        self.boughtAt = boughtAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var quantityDisplay: String? {
        guard let quantityValue, !quantityValue.isEmpty else { return nil }
        if let quantityUnit, !quantityUnit.isEmpty {
            return "\(quantityValue) \(quantityUnit)"
        }
        return quantityValue
    }
}
