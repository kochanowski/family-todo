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

    func testNormalizeRejectsUnsupportedCodeOnlyValue() {
        XCTAssertThrowsError(try InviteInputNormalizer.normalize("ABCD1234"))
    }

    func testNormalizeRejectsEmptyValue() {
        XCTAssertThrowsError(try InviteInputNormalizer.normalize("   \n  "))
    }
}
