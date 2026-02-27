import Foundation

struct InviteToken: Equatable, Codable, Sendable {
    static let ttl: TimeInterval = 24 * 60 * 60

    let id: String
    let code: String
    let householdId: UUID
    let shareURL: String
    let createdAt: Date
    let expiresAt: Date
    var isRevoked: Bool
    var usesCount: Int
    var lastRedeemedAt: Date?

    init(
        id: String,
        code: String,
        householdId: UUID,
        shareURL: String,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        isRevoked: Bool = false,
        usesCount: Int = 0,
        lastRedeemedAt: Date? = nil
    ) {
        self.id = id
        self.code = code
        self.householdId = householdId
        self.shareURL = shareURL
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(Self.ttl)
        self.isRevoked = isRevoked
        self.usesCount = usesCount
        self.lastRedeemedAt = lastRedeemedAt
    }

    func isExpired(at date: Date = Date()) -> Bool {
        date >= expiresAt
    }

    func isActive(at date: Date = Date()) -> Bool {
        !isRevoked && !isExpired(at: date)
    }
}
