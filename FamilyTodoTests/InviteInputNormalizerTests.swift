@testable import HousePulse
import XCTest

final class InviteInputNormalizerTests: XCTestCase {
    func testNormalizeAcceptsFullHTTPSLink() throws {
        let raw = "https://www.icloud.com/share/abcd1234"
        let normalized = try InviteInputNormalizer.normalize(raw)

        XCTAssertEqual(normalized, raw)
    }

    func testNormalizeAddsSchemeForICloudShareHost() throws {
        let raw = "www.icloud.com/share/abcd1234"
        let normalized = try InviteInputNormalizer.normalize(raw)

        XCTAssertEqual(normalized, "https://www.icloud.com/share/abcd1234")
    }

    func testNormalizeTrimsWhitespace() throws {
        let raw = "  https://www.icloud.com/share/abcd1234   \n"
        let normalized = try InviteInputNormalizer.normalize(raw)

        XCTAssertEqual(normalized, "https://www.icloud.com/share/abcd1234")
    }

    func testNormalizeAcceptsShortCode() throws {
        let normalized = try InviteInputNormalizer.normalize(" a7b9xq ")
        XCTAssertEqual(normalized, "A7B9XQ")
    }

    func testNormalizeAcceptsCustomHousepulseDeepLinkWithCode() throws {
        let normalized = try InviteInputNormalizer.normalize("housepulse://join/a7b9xq")
        XCTAssertEqual(normalized, "A7B9XQ")
    }

    func testNormalizeAcceptsCustomHousepulseDeepLinkWithURLPayload() throws {
        let raw = "housepulse://join/https%3A%2F%2Fwww.icloud.com%2Fshare%2Fabcd1234"
        let normalized = try InviteInputNormalizer.normalize(raw)
        XCTAssertEqual(normalized, "https://www.icloud.com/share/abcd1234")
    }

    func testNormalizeInputMarksCustomDeepLinkForConfirmation() throws {
        let normalized = try InviteInputNormalizer.normalizeInput("housepulse://join/A7B9XQ")
        XCTAssertEqual(normalized.inviteCode, "A7B9XQ")
        XCTAssertTrue(normalized.requiresConfirmation)
    }

    func testNormalizeAcceptsCustomHousepulseDeepLinkWithBase64URLPayload() throws {
        let shareURL = "https://www.icloud.com/share/abcd1234"
        let payload = Data(shareURL.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let normalized = try InviteInputNormalizer.normalize("housepulse://join?u=\(payload)")
        XCTAssertEqual(normalized, shareURL)
    }

    func testNormalizeRejectsEmptyValue() {
        XCTAssertThrowsError(try InviteInputNormalizer.normalize("   \n  "))
    }

    func testNormalizeInviteCodeTokenRejectsInvalidLengthAndCharacters() {
        XCTAssertNil(InviteInputNormalizer.normalizeInviteCodeToken("AB12"))
        XCTAssertNil(InviteInputNormalizer.normalizeInviteCodeToken("AB12-3"))
        XCTAssertNil(InviteInputNormalizer.normalizeInviteCodeToken("AB12C34D9"))
        XCTAssertEqual(InviteInputNormalizer.normalizeInviteCodeToken("ab12c4"), "AB12C4")
        XCTAssertEqual(InviteInputNormalizer.normalizeInviteCodeToken("AB12C34D"), "AB12C34D")
        XCTAssertNil(InviteInputNormalizer.normalizeInviteCodeToken("AB12C34"))
        XCTAssertNil(InviteInputNormalizer.normalizeInviteCodeToken("ab12c"))
    }

    func testNormalizedURLRejectsShortCodeValue() {
        XCTAssertThrowsError(try InviteInputNormalizer.normalizedURL(from: "A7B9XQ"))
    }
}
