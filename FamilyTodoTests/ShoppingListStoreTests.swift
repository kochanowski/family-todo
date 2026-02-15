@testable import HousePulse
import SwiftData
import XCTest

@MainActor
final class ShoppingListStoreTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var store: ShoppingListStore!
    private let householdId = UUID()

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([CachedShoppingItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])

        store = ShoppingListStore(
            householdId: householdId,
            modelContext: modelContainer.mainContext
        )
        store.setSyncMode(.localOnly)
    }

    override func tearDown() async throws {
        store = nil
        modelContainer = nil
        try await super.tearDown()
    }

    func testDeleteRecentItemRemovesAllBoughtDuplicatesByNormalizedTitle() async {
        await createBoughtItem(title: "Milk")
        await createBoughtItem(title: " milk ")
        await createBoughtItem(title: "MILK")
        await createBoughtItem(title: "Bread")

        XCTAssertEqual(store.recentItems.count, 2)

        guard let milkRecent = store.recentItems.first(where: { normalized($0.title) == "milk" }) else {
            XCTFail("Expected Milk entry in recent list")
            return
        }

        await store.deleteRecentItem(milkRecent)

        XCTAssertEqual(store.items.filter { $0.isBought && normalized($0.title) == "milk" }.count, 0)
        XCTAssertEqual(store.items.filter { $0.isBought && normalized($0.title) == "bread" }.count, 1)
        XCTAssertFalse(store.recentItems.contains(where: { normalized($0.title) == "milk" }))
    }

    func testClearRecentItemsRemovesAllBoughtAndKeepsActiveToBuy() async {
        await createBoughtItem(title: "Eggs")
        await createBoughtItem(title: "Bread")
        await store.createItem(title: "Active item")

        await store.clearRecentItems()

        XCTAssertTrue(store.recentItems.isEmpty)
        XCTAssertEqual(store.items.filter(\.isBought).count, 0)
        XCTAssertEqual(store.toBuyItems.filter { normalized($0.title) == "active item" }.count, 1)
    }

    func testRestoreRecentItemRemovesEntryFromRecentAndReturnsToToBuy() async {
        await createBoughtItem(title: "Sugar")
        await createBoughtItem(title: "SUGAR")

        guard let sugarRecent = store.recentItems.first(where: { normalized($0.title) == "sugar" }) else {
            XCTFail("Expected Sugar entry in recent list")
            return
        }

        await store.restoreRecentItem(sugarRecent)

        XCTAssertEqual(store.items.filter { $0.isBought && normalized($0.title) == "sugar" }.count, 0)
        XCTAssertEqual(store.toBuyItems.filter { normalized($0.title) == "sugar" }.count, 1)
        XCTAssertFalse(store.recentItems.contains(where: { normalized($0.title) == "sugar" }))
    }

    private func createBoughtItem(title: String) async {
        await store.createItem(title: title)

        guard let created = store.toBuyItems.max(by: { $0.createdAt < $1.createdAt }) else {
            XCTFail("Expected created item for title: \(title)")
            return
        }

        await store.toggleBought(created)
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
