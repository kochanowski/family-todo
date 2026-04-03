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

        modelContainer = try TestModelContainerFactory.makeInMemoryContainer(profile: .shopping)

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

    func testUpdateItemTitleDoesNotChangeBoughtState() async {
        await store.createItem(title: "Bread")
        guard var item = store.toBuyItems.first(where: { normalized($0.title) == "bread" }) else {
            XCTFail("Expected created item")
            return
        }

        item.title = "Wholegrain Bread"
        await store.updateItem(item)

        XCTAssertEqual(store.toBuyItems.count, 1)
        XCTAssertEqual(store.toBuyItems.first?.title, "Wholegrain Bread")
        XCTAssertFalse(store.toBuyItems.first?.isBought ?? true)
        XCTAssertTrue(store.recentItems.isEmpty)
    }

    func testMergeCloudSnapshot_PendingUploadWinsAndPendingDeleteRemoved() {
        let baseDate = Date()
        let pendingID = UUID()
        let deleteID = UUID()
        let cloudOnlyID = UUID()

        let pendingLocal = ShoppingItem(
            id: pendingID,
            householdId: householdId,
            title: "Milk (local pending)",
            isBought: true,
            boughtAt: baseDate,
            updatedAt: baseDate.addingTimeInterval(10)
        )
        let cloudPending = ShoppingItem(
            id: pendingID,
            householdId: householdId,
            title: "Milk (cloud stale)",
            isBought: false,
            updatedAt: baseDate
        )
        let cloudDeleted = ShoppingItem(
            id: deleteID,
            householdId: householdId,
            title: "To delete",
            isBought: false,
            updatedAt: baseDate
        )
        let cloudOnly = ShoppingItem(
            id: cloudOnlyID,
            householdId: householdId,
            title: "Cloud item",
            isBought: false,
            updatedAt: baseDate
        )

        let snapshot = ShoppingListStore.PendingSyncSnapshot(
            pendingUploadByID: [pendingID: pendingLocal],
            pendingDeleteIDs: [deleteID]
        )

        let merged = store.mergeCloudSnapshot([cloudPending, cloudDeleted, cloudOnly], with: snapshot)

        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains(where: { $0.id == cloudOnlyID }))
        XCTAssertTrue(merged.contains(where: { $0.id == pendingID && $0.isBought }))
        XCTAssertFalse(merged.contains(where: { $0.id == deleteID }))
    }

    func testPendingSyncSnapshotTreatsAwaitingCloudEchoAsLocalPending() throws {
        let pendingItem = ShoppingItem(
            householdId: householdId,
            title: "Milk",
            isBought: false
        )
        let cached = CachedShoppingItem(from: pendingItem)
        cached.syncStatusRaw = "awaitingCloudEcho"
        modelContainer.mainContext.insert(cached)
        try modelContainer.mainContext.save()

        let descriptor = FetchDescriptor<CachedShoppingItem>()
        let snapshot = try store.pendingSyncSnapshot(from: modelContainer.mainContext.fetch(descriptor))

        XCTAssertEqual(snapshot.pendingUploadByID[pendingItem.id]?.title, "Milk")
        XCTAssertTrue(snapshot.pendingDeleteIDs.isEmpty)
    }

    func testMergeCloudSnapshotDoesNotAcceptStaleCloudEchoWhileAwaitingCloudEcho() throws {
        let localUpdatedAt = Date(timeIntervalSince1970: 1_736_910_000)
        let localItem = ShoppingItem(
            householdId: householdId,
            title: "Tomatoes",
            quantityValue: "2",
            isBought: false,
            sortOrder: 1,
            updatedAt: localUpdatedAt
        )

        let cached = CachedShoppingItem(from: localItem)
        cached.syncStatusRaw = "awaitingCloudEcho"
        cached.lastSyncedAt = Date()
        modelContainer.mainContext.insert(cached)
        try modelContainer.mainContext.save()

        let staleCloudItem = ShoppingItem(
            id: localItem.id,
            householdId: householdId,
            title: "Tomatoes",
            quantityValue: nil,
            isBought: false,
            sortOrder: 0,
            updatedAt: localUpdatedAt.addingTimeInterval(30)
        )

        let descriptor = FetchDescriptor<CachedShoppingItem>()
        let snapshot = try store.pendingSyncSnapshot(from: modelContainer.mainContext.fetch(descriptor))
        let merged = store.mergeCloudSnapshot([staleCloudItem], with: snapshot)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.quantityValue, "2")
        XCTAssertEqual(merged.first?.sortOrder, 1)
    }

    func testMergeCloudSnapshotDropsExpiredAwaitingCloudEchoWhenCloudNoLongerContainsItem() throws {
        let localItem = ShoppingItem(
            householdId: householdId,
            title: "Tomatoes",
            isBought: false,
            updatedAt: Date(timeIntervalSince1970: 1_736_910_000)
        )

        let cached = CachedShoppingItem(from: localItem)
        cached.syncStatusRaw = "awaitingCloudEcho"
        cached.lastSyncedAt = Date(timeIntervalSince1970: 1_736_900_000)
        modelContainer.mainContext.insert(cached)
        try modelContainer.mainContext.save()

        let descriptor = FetchDescriptor<CachedShoppingItem>()
        let snapshot = try store.pendingSyncSnapshot(from: modelContainer.mainContext.fetch(descriptor))
        let merged = store.mergeCloudSnapshot([], with: snapshot)

        XCTAssertTrue(merged.isEmpty)
    }

    func testUpdateItem_UpsertsCacheWhenRowMissing() async throws {
        let item = ShoppingItem(
            householdId: householdId,
            title: "Upsert check",
            isBought: true
        )

        await store.updateItem(item)

        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.id == item.id }
        )
        let cached = try modelContainer.mainContext.fetch(descriptor)

        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached.first?.title, "Upsert check")
        XCTAssertEqual(cached.first?.isBought, true)
    }

    func testCreateItemsFromTitlesAddsEveryNonEmptyTitleInOrderAndCachesThem() async throws {
        let createdCount = await store.createItems(
            fromTitles: ["Milk", "  ", "Bread", "\nEggs\n"]
        )

        XCTAssertEqual(createdCount, 3)
        XCTAssertEqual(store.toBuyItems.count, 3)
        XCTAssertEqual(store.toBuyItems.map(\.title), ["Milk", "Bread", "Eggs"])

        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let cachedItems = try modelContainer.mainContext.fetch(descriptor)

        XCTAssertEqual(cachedItems.map(\.title), ["Milk", "Bread", "Eggs"])
    }

    func testCreateItemAfterAnchorInsertsDirectlyBelowAndUpdatesCacheOrder() async throws {
        _ = await store.createItem(title: "Milk")
        _ = await store.createItem(title: "Bread")

        guard let milk = store.toBuyItems.first(where: { normalized($0.title) == "milk" }) else {
            XCTFail("Expected Milk item")
            return
        }

        _ = await store.createItem(title: "Eggs", afterItemId: milk.id)

        XCTAssertEqual(store.toBuyItems.map(\.title), ["Milk", "Eggs", "Bread"])

        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let cachedItems = try modelContainer.mainContext.fetch(descriptor)

        XCTAssertEqual(cachedItems.map(\.title), ["Milk", "Eggs", "Bread"])
    }

    func testInitHydratesItemsFromCacheBeforeLoad() throws {
        let cachedItem = ShoppingItem(
            householdId: householdId,
            title: "Pomidorki koktajlowe",
            isBought: false,
            sortOrder: 1
        )
        modelContainer.mainContext.insert(CachedShoppingItem(from: cachedItem))
        try modelContainer.mainContext.save()

        let hydratedStore = ShoppingListStore(
            householdId: householdId,
            modelContext: modelContainer.mainContext
        )

        XCTAssertTrue(hydratedStore.hasHydratedLocalSnapshot)
        XCTAssertEqual(hydratedStore.items.count, 1)
        XCTAssertEqual(hydratedStore.toBuyItems.count, 1)
        XCTAssertEqual(hydratedStore.toBuyItems.first?.title, "Pomidorki koktajlowe")
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
