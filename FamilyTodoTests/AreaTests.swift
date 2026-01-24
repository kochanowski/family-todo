@testable import HousePulse
import XCTest

final class AreaTests: XCTestCase {
    private let householdId = UUID()

    // MARK: - Initialization Tests

    func testAreaInitialization() {
        let area = Area(
            householdId: householdId,
            name: "Kitchen",
            icon: "fork.knife",
            sortOrder: 0
        )

        XCTAssertEqual(area.name, "Kitchen")
        XCTAssertEqual(area.icon, "fork.knife")
        XCTAssertEqual(area.sortOrder, 0)
        XCTAssertEqual(area.householdId, householdId)
    }

    func testAreaWithoutIcon() {
        let area = Area(
            householdId: householdId,
            name: "Custom Area",
            sortOrder: 10
        )

        XCTAssertNil(area.icon)
    }

    // MARK: - Defaults Tests

    func testDefaultAreasCount() {
        let defaults = Area.defaults(for: householdId)

        XCTAssertEqual(defaults.count, 6, "Should have 6 default areas")
    }

    func testDefaultAreasNames() {
        let defaults = Area.defaults(for: householdId)
        let names = defaults.map(\.name)

        XCTAssertTrue(names.contains("Kitchen"))
        XCTAssertTrue(names.contains("Bathroom"))
        XCTAssertTrue(names.contains("Living Room"))
        XCTAssertTrue(names.contains("Bedroom"))
        XCTAssertTrue(names.contains("Garden"))
        XCTAssertTrue(names.contains("Repairs"))
    }

    func testDefaultAreasHaveIcons() {
        let defaults = Area.defaults(for: householdId)

        for area in defaults {
            XCTAssertNotNil(area.icon, "Area \(area.name) should have an icon")
        }
    }

    func testDefaultAreasSortOrder() {
        let defaults = Area.defaults(for: householdId)

        for (index, area) in defaults.enumerated() {
            XCTAssertEqual(area.sortOrder, index, "Area \(area.name) should have sortOrder \(index)")
        }
    }

    func testDefaultAreasHaveSameHouseholdId() {
        let defaults = Area.defaults(for: householdId)

        for area in defaults {
            XCTAssertEqual(area.householdId, householdId)
        }
    }

    func testDefaultAreasHaveUniqueIds() {
        let defaults = Area.defaults(for: householdId)
        let ids = defaults.map(\.id)
        let uniqueIds = Set(ids)

        XCTAssertEqual(ids.count, uniqueIds.count, "All areas should have unique IDs")
    }

    // MARK: - Codable Tests

    func testAreaEncodingDecoding() throws {
        let originalArea = Area(
            householdId: householdId,
            name: "Test Area",
            icon: "star",
            sortOrder: 5
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalArea)

        let decoder = JSONDecoder()
        let decodedArea = try decoder.decode(Area.self, from: data)

        XCTAssertEqual(originalArea.id, decodedArea.id)
        XCTAssertEqual(originalArea.name, decodedArea.name)
        XCTAssertEqual(originalArea.icon, decodedArea.icon)
        XCTAssertEqual(originalArea.sortOrder, decodedArea.sortOrder)
    }
}
