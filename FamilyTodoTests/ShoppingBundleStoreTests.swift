@testable import HousePulse
import SwiftData
import XCTest

@MainActor
final class ShoppingBundleStoreTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var store: ShoppingBundleStore!
    private let householdId = UUID()

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([CachedShoppingBundle.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])

        store = ShoppingBundleStore(
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

    func testCachedShoppingBundleRoundTripPreservesOrderedItems() {
        let bundle = ShoppingBundle(
            householdId: householdId,
            name: "Weekend breakfast",
            icon: "cup.and.saucer.fill",
            items: ["Eggs", "Bread", "Coffee"],
            sortOrder: 2
        )

        let cached = CachedShoppingBundle(from: bundle)
        let restored = cached.toShoppingBundle()

        XCTAssertEqual(restored.name, "Weekend breakfast")
        XCTAssertEqual(restored.icon, "cup.and.saucer.fill")
        XCTAssertEqual(restored.items, ["Eggs", "Bread", "Coffee"])
        XCTAssertEqual(restored.sortOrder, 2)
    }

    func testMalformedItemsJSONDecodesToEmptyArray() {
        let bundle = ShoppingBundle(
            householdId: householdId,
            name: "Malformed",
            items: ["Milk"]
        )
        let cached = CachedShoppingBundle(from: bundle)
        cached.itemsJSON = "{broken-json"

        XCTAssertEqual(cached.toShoppingBundle().items, [])
    }

    func testCreateUpdateDeleteBundleLocalOnlyPersistsCache() async throws {
        await store.createBundle(
            name: "Weekend breakfast",
            icon: "cup.and.saucer.fill",
            items: ["Eggs", "Bread", " "]
        )

        XCTAssertEqual(store.bundles.count, 1)
        XCTAssertEqual(store.bundles.first?.items, ["Eggs", "Bread"])

        var created = try XCTUnwrap(store.bundles.first)
        let createDescriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.id == created.id }
        )
        var cachedBundles = try modelContainer.mainContext.fetch(createDescriptor)
        XCTAssertEqual(cachedBundles.count, 1)
        XCTAssertEqual(cachedBundles.first?.itemsJSON, "[\"Eggs\",\"Bread\"]")

        created.name = "Sunday breakfast"
        created.icon = "cart.fill"
        created.items = ["Bagels", "Jam"]
        await store.updateBundle(created)

        cachedBundles = try modelContainer.mainContext.fetch(createDescriptor)
        XCTAssertEqual(store.bundles.first?.name, "Sunday breakfast")
        XCTAssertEqual(store.bundles.first?.icon, "cart.fill")
        XCTAssertEqual(store.bundles.first?.items, ["Bagels", "Jam"])
        XCTAssertEqual(cachedBundles.first?.itemsJSON, "[\"Bagels\",\"Jam\"]")

        await store.deleteBundle(created)

        XCTAssertTrue(store.bundles.isEmpty)
        XCTAssertTrue(try modelContainer.mainContext.fetch(createDescriptor).isEmpty)
    }

    func testMergeCloudSnapshotPendingUploadWinsAndPendingDeleteRemoved() {
        let baseDate = Date()
        let pendingID = UUID()
        let deleteID = UUID()
        let cloudOnlyID = UUID()

        let pendingLocal = ShoppingBundle(
            id: pendingID,
            householdId: householdId,
            name: "Local breakfast",
            icon: "cart.fill",
            items: ["Milk"],
            updatedAt: baseDate.addingTimeInterval(10)
        )
        let cloudPending = ShoppingBundle(
            id: pendingID,
            householdId: householdId,
            name: "Cloud stale",
            icon: "archivebox.fill",
            items: ["Bread"],
            updatedAt: baseDate
        )
        let cloudDeleted = ShoppingBundle(
            id: deleteID,
            householdId: householdId,
            name: "Remove me",
            items: ["Soap"],
            updatedAt: baseDate
        )
        let cloudOnly = ShoppingBundle(
            id: cloudOnlyID,
            householdId: householdId,
            name: "Cloud only",
            items: ["Coffee"],
            updatedAt: baseDate
        )

        let snapshot = ShoppingBundleStore.PendingSyncSnapshot(
            pendingUploadByID: [pendingID: pendingLocal],
            pendingDeleteIDs: [deleteID]
        )

        let merged = store.mergeCloudSnapshot([cloudPending, cloudDeleted, cloudOnly], with: snapshot)

        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains(where: { $0.id == pendingID && $0.name == "Local breakfast" }))
        XCTAssertTrue(merged.contains(where: { $0.id == cloudOnlyID }))
        XCTAssertFalse(merged.contains(where: { $0.id == deleteID }))
    }
}
