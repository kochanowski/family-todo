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
        let normalized = try InviteInputNormalizer.normalize("ABCD1234")
        XCTAssertEqual(normalized, "https://www.icloud.com/share/ABCD1234")
    }

    func testNormalizeAcceptsCustomHousepulseDeepLinkWithCode() throws {
        let normalized = try InviteInputNormalizer.normalize("housepulse://join/ABCD1234")
        XCTAssertEqual(normalized, "https://www.icloud.com/share/ABCD1234")
    }

    func testNormalizeAcceptsCustomHousepulseDeepLinkWithURLPayload() throws {
        let raw = "housepulse://join/https%3A%2F%2Fwww.icloud.com%2Fshare%2Fabcd1234"
        let normalized = try InviteInputNormalizer.normalize(raw)
        XCTAssertEqual(normalized, "https://www.icloud.com/share/abcd1234")
    }

    func testNormalizeInputMarksCustomDeepLinkForConfirmation() throws {
        let normalized = try InviteInputNormalizer.normalizeInput("housepulse://join/ABCD1234")
        XCTAssertEqual(normalized.kind, .customScheme)
        XCTAssertTrue(normalized.requiresConfirmation)
    }

    func testNormalizeRejectsEmptyValue() {
        XCTAssertThrowsError(try InviteInputNormalizer.normalize("   \n  "))
    }
}
