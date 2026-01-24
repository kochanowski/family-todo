import Foundation
import SwiftData

/// SwiftData model for offline caching of Member.
/// Follows ADR-002: offline-first with optimistic UI updates.
@Model
final class CachedMember {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var userId: String
    var displayName: String
    var roleRaw: String
    var joinedAt: Date
    var isActive: Bool

    // Sync metadata
    var syncStatusRaw: String = "synced"
    var lastSyncedAt: Date?
    var ckRecordIDData: Data?
    var ckSystemFieldsData: Data?

    init(from member: Member) {
        id = member.id
        householdId = member.householdId
        userId = member.userId
        displayName = member.displayName
        roleRaw = member.role.rawValue
        joinedAt = member.joinedAt
        isActive = member.isActive
        syncStatusRaw = "synced"
        lastSyncedAt = Date()
    }

    func update(from member: Member) {
        householdId = member.householdId
        userId = member.userId
        displayName = member.displayName
        roleRaw = member.role.rawValue
        joinedAt = member.joinedAt
        isActive = member.isActive
        lastSyncedAt = Date()
        syncStatusRaw = "synced"
    }

    func toMember() -> Member {
        Member(
            id: id,
            householdId: householdId,
            userId: userId,
            displayName: displayName,
            role: Member.MemberRole(rawValue: roleRaw) ?? .member,
            joinedAt: joinedAt,
            isActive: isActive
        )
    }
}
