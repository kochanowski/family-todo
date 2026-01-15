import Foundation

struct Area: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var name: String
    var icon: String?
    var sortOrder: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID,
        name: String,
        icon: String? = nil,
        sortOrder: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    static func defaults(for householdId: UUID) -> [Area] {
        [
            Area(householdId: householdId, name: "Kitchen", icon: "fork.knife", sortOrder: 0),
            Area(householdId: householdId, name: "Bathroom", icon: "shower", sortOrder: 1),
            Area(householdId: householdId, name: "Living Room", icon: "sofa", sortOrder: 2),
            Area(householdId: householdId, name: "Bedroom", icon: "bed.double", sortOrder: 3),
            Area(householdId: householdId, name: "Garden", icon: "leaf", sortOrder: 4),
            Area(householdId: householdId, name: "Repairs", icon: "wrench", sortOrder: 5)
        ]
    }
}
