import Foundation
@testable import HousePulse
import XCTest

final class InviteCodeFlowTests: XCTestCase {
    func testGenerateInviteCodeUsesExpectedAlphabetAndLength() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

        for _ in 0 ..< 100 {
            let code = CloudKitManager.generateInviteCode()
            XCTAssertEqual(code.count, 8)
            XCTAssertTrue(code.unicodeScalars.allSatisfy { allowed.contains($0) })
        }
    }

    func testGenerateInviteCodeHonorsCustomLengthWithinBounds() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

        let shorter = CloudKitManager.generateInviteCode(length: 6)
        XCTAssertEqual(shorter.count, 8)
        XCTAssertTrue(shorter.unicodeScalars.allSatisfy { allowed.contains($0) })

        let exact = CloudKitManager.generateInviteCode(length: 8)
        XCTAssertEqual(exact.count, 8)
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

        let url = try InviteInputNormalizer.normalizeInput("https://www.icloud.com/share/abc123")
        XCTAssertEqual(url.kind, .iCloudURL)
        XCTAssertEqual(url.inviteCode, "https://www.icloud.com/share/abc123")
    }
}
