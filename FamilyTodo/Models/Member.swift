import Foundation

struct Member: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    let userId: String
    var displayName: String
    let role: MemberRole
    let joinedAt: Date
    var isActive: Bool

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
        isActive: Bool = true
    ) {
        self.id = id
        self.householdId = householdId
        self.userId = userId
        self.displayName = displayName
        self.role = role
        self.joinedAt = joinedAt
        self.isActive = isActive
    }
}
