import Foundation
@testable import HousePulse
import XCTest

final class InviteCodeFlowTests: XCTestCase {
    func testGenerateInviteCodeUsesExpectedAlphabetAndLength() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

        for _ in 0 ..< 100 {
            let code = CloudKitManager.generateInviteCode()
            XCTAssertEqual(code.count, InviteInputNormalizer.preferredInviteCodeLength)
            XCTAssertTrue(code.unicodeScalars.allSatisfy { allowed.contains($0) })
        }
    }

    func testGenerateInviteCodeHonorsCustomLengthWithinBounds() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

        let shorter = CloudKitManager.generateInviteCode(length: 4)
        XCTAssertEqual(shorter.count, InviteInputNormalizer.preferredInviteCodeLength)
        XCTAssertTrue(shorter.unicodeScalars.allSatisfy { allowed.contains($0) })

        let exact = CloudKitManager.generateInviteCode(length: InviteInputNormalizer.legacyInviteCodeLength)
        XCTAssertEqual(exact.count, InviteInputNormalizer.legacyInviteCodeLength)
        XCTAssertTrue(exact.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testInviteTokenActiveStateForExpiryAndRevocation() {
        let createdAt = Date(timeIntervalSince1970: 0)
        let expiresAt = createdAt.addingTimeInterval(InviteToken.ttl)
        let token = InviteToken(
            id: "A7B9XQ",
            code: "A7B9XQ",
            householdId: UUID(),
            shareURL: "https://www.icloud.com/share/test",
            createdAt: createdAt,
            expiresAt: expiresAt,
            isRevoked: false,
            usesCount: 0
        )

        XCTAssertTrue(token.isActive(at: createdAt.addingTimeInterval(60)))
        XCTAssertTrue(token.isExpired(at: expiresAt))

        var revoked = token
        revoked.isRevoked = true
        XCTAssertFalse(revoked.isActive(at: createdAt.addingTimeInterval(60)))
    }

    func testNormalizeInputDistinguishesCodeAndURLPaths() throws {
        let code = try InviteInputNormalizer.normalizeInput("A7B9XQ")
        XCTAssertEqual(code.kind, .shortCode)
        XCTAssertEqual(code.inviteCode, "A7B9XQ")

        let legacyCode = try InviteInputNormalizer.normalizeInput("A7B9XQ2M")
        XCTAssertEqual(legacyCode.kind, .shortCode)
        XCTAssertEqual(legacyCode.inviteCode, "A7B9XQ2M")

        let url = try InviteInputNormalizer.normalizeInput("https://www.icloud.com/share/abc123")
        XCTAssertEqual(url.kind, .iCloudURL)
        XCTAssertEqual(url.inviteCode, "https://www.icloud.com/share/abc123")
    }

    func testCanReuseInviteTokenRequiresMatchingLiveShareURL() {
        let token = InviteToken(
            id: "A7B9XQ2M",
            code: "A7B9XQ2M",
            householdId: UUID(),
            shareURL: "https://www.icloud.com/share/live",
            createdAt: Date(timeIntervalSince1970: 0),
            expiresAt: Date(timeIntervalSince1970: InviteToken.ttl),
            isRevoked: false,
            usesCount: 0
        )

        XCTAssertTrue(
            CloudKitManager.canReuseInviteToken(
                token,
                shareURL: "https://www.icloud.com/share/live",
                at: Date(timeIntervalSince1970: 60)
            )
        )
        XCTAssertFalse(
            CloudKitManager.canReuseInviteToken(
                token,
                shareURL: nil,
                at: Date(timeIntervalSince1970: 60)
            )
        )
        XCTAssertFalse(
            CloudKitManager.canReuseInviteToken(
                token,
                shareURL: "https://www.icloud.com/share/stale",
                at: Date(timeIntervalSince1970: 60)
            )
        )
    }

    func testCanReuseInviteTokenRejectsExpiredRevokedOrExhaustedTokens() {
        let householdId = UUID()
        let createdAt = Date(timeIntervalSince1970: 0)
        let expiresAt = createdAt.addingTimeInterval(InviteToken.ttl)

        let expired = InviteToken(
            id: "E1X2P3R4",
            code: "E1X2P3R4",
            householdId: householdId,
            shareURL: "https://www.icloud.com/share/live",
            createdAt: createdAt,
            expiresAt: expiresAt,
            isRevoked: false,
            usesCount: 0
        )
        XCTAssertFalse(
            CloudKitManager.canReuseInviteToken(
                expired,
                shareURL: expired.shareURL,
                at: expiresAt
            )
        )

        let revoked = InviteToken(
            id: "R1V2K3D4",
            code: "R1V2K3D4",
            householdId: householdId,
            shareURL: "https://www.icloud.com/share/live",
            createdAt: createdAt,
            expiresAt: expiresAt,
            isRevoked: true,
            usesCount: 0
        )
        XCTAssertFalse(
            CloudKitManager.canReuseInviteToken(
                revoked,
                shareURL: revoked.shareURL,
                at: createdAt.addingTimeInterval(60)
            )
        )

        let exhausted = InviteToken(
            id: "U1S2E3S4",
            code: "U1S2E3S4",
            householdId: householdId,
            shareURL: "https://www.icloud.com/share/live",
            createdAt: createdAt,
            expiresAt: expiresAt,
            isRevoked: false,
            usesCount: 100
        )
        XCTAssertFalse(
            CloudKitManager.canReuseInviteToken(
                exhausted,
                shareURL: exhausted.shareURL,
                at: createdAt.addingTimeInterval(60)
            )
        )
    }

    func testPrioritizedActiveInviteTokensSortsLocallyByNewestCreatedAt() {
        let householdId = UUID()
        let now = Date(timeIntervalSince1970: 5000)
        let older = InviteToken(
            id: "OLDER1",
            code: "OLDER1",
            householdId: householdId,
            shareURL: "https://www.icloud.com/share/live",
            createdAt: now.addingTimeInterval(-600),
            expiresAt: now.addingTimeInterval(600),
            isRevoked: false,
            usesCount: 0
        )
        let newer = InviteToken(
            id: "NEWER1",
            code: "NEWER1",
            householdId: householdId,
            shareURL: "https://www.icloud.com/share/live",
            createdAt: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(600),
            isRevoked: false,
            usesCount: 0
        )
        let expired = InviteToken(
            id: "EXPIRE",
            code: "EXPIRE",
            householdId: householdId,
            shareURL: "https://www.icloud.com/share/live",
            createdAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(-1),
            isRevoked: false,
            usesCount: 0
        )

        let prioritized = CloudKitManager.prioritizedActiveInviteTokens(
            [older, expired, newer],
            at: now
        )

        XCTAssertEqual(prioritized.map(\.code), ["NEWER1", "OLDER1"])
    }

    func testInviteCodeCreateFailedUsesDetailedDescription() {
        let error = CloudKitManager.CloudKitManagerError.inviteCodeCreateFailed(
            "Invite lookup failed: Field 'createdAt' is not marked sortable."
        )

        XCTAssertEqual(
            error.errorDescription,
            "Invite lookup failed: Field 'createdAt' is not marked sortable."
        )
    }
}
