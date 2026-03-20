import CloudKit
@testable import HousePulse
import SwiftData
import UIKit
import XCTest

@MainActor
final class HouseholdRemoteSyncTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var suiteName: String?
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        modelContainer = try TestModelContainerFactory.makeInMemoryContainer(profile: .household)
        let isolatedDefaults = TestModelContainerFactory.makeUserDefaults(
            suitePrefix: "HouseholdRemoteSyncTests"
        )
        suiteName = isolatedDefaults.suiteName
        defaults = isolatedDefaults.defaults
    }

    override func tearDown() async throws {
        TestModelContainerFactory.clearUserDefaults(suiteName: suiteName, defaults: defaults)
        modelContainer = nil
        suiteName = nil
        defaults = nil
        try await super.tearDown()
    }

    private func makeStore(cloud: FakeHouseholdCloud) -> HouseholdStore {
        HouseholdStore(
            modelContext: modelContainer.mainContext,
            cloudKit: cloud,
            userDefaults: defaults,
            recoverySuppressionDuration: 300,
            joinHydrationConfiguration: .default
        )
    }

    private func cachedMembers(for householdId: UUID) throws -> [CachedMember] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedMember>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    private func cachedWorkItems(for householdId: UUID) throws -> [CachedWorkItem] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedWorkItem>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    private func cachedShoppingItems(for householdId: UUID) throws -> [CachedShoppingItem] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedShoppingItem>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    private func cachedShoppingBundles(for householdId: UUID) throws -> [CachedShoppingBundle] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedShoppingBundle>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    private func cachedBacklogCategories(for householdId: UUID) throws -> [CachedBacklogCategory] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedBacklogCategory>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    func testHandleRemoteCloudChangeRefreshesSharedCachesAndReturnsNewData() async throws {
        let userId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let membership = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )
        let category = TestCacheFixtures.category(householdId: household.id, title: "Planning")
        let task = TestCacheFixtures.task(
            householdId: household.id,
            title: "Take out trash",
            backlogCategoryId: category.id
        )
        let idea = TestCacheFixtures.idea(
            categoryId: category.id,
            householdId: household.id,
            title: "Plan spring cleaning"
        )
        let shoppingItem = TestCacheFixtures.shoppingItem(
            householdId: household.id,
            title: "Milk"
        )
        let bundle = TestCacheFixtures.shoppingBundle(
            householdId: household.id,
            name: "Weekly staples"
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [membership],
            tasks: [task],
            shoppingItems: [shoppingItem],
            shoppingBundles: [bundle],
            backlogItems: [idea],
            backlogCategories: [category],
            acceptedSharedHouseholdIDs: [household.id]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = household

        modelContainer.mainContext.insert(CachedHousehold(from: household))
        modelContainer.mainContext.insert(CachedMember(from: membership))
        try modelContainer.mainContext.save()

        let householdExpectation = expectation(
            forNotification: .householdDataDidChange,
            object: nil,
            handler: nil
        )
        let shoppingExpectation = expectation(
            forNotification: .shoppingListDataDidChange,
            object: nil,
            handler: nil
        )

        let result = await store.handleRemoteCloudChange(
            userId: userId,
            preferredHouseholdId: household.id
        )

        await fulfillment(of: [householdExpectation, shoppingExpectation], timeout: 1.0)

        XCTAssertEqual(result, .newData)
        XCTAssertEqual(try cachedMembers(for: household.id).count, 1)
        XCTAssertEqual(try cachedWorkItems(for: household.id).count, 2)
        XCTAssertEqual(try cachedShoppingItems(for: household.id).count, 1)
        XCTAssertEqual(try cachedShoppingBundles(for: household.id).count, 1)
        XCTAssertEqual(try cachedBacklogCategories(for: household.id).count, 1)

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(operations.contains {
            $0.name == "fetchTasks" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchShoppingItems" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchBacklogItems" && $0.scope == .participantShared && $0.householdId == household.id
        })
    }

    func testHandleRemoteCloudChangeReturnsNoDataWhenCachesAreAlreadyCurrent() async throws {
        let userId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let membership = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )
        let task = TestCacheFixtures.task(
            householdId: household.id,
            title: "Take out trash"
        )
        let shoppingItem = TestCacheFixtures.shoppingItem(
            householdId: household.id,
            title: "Milk"
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [membership],
            tasks: [task],
            shoppingItems: [shoppingItem],
            acceptedSharedHouseholdIDs: [household.id]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = household

        modelContainer.mainContext.insert(CachedHousehold(from: household))
        modelContainer.mainContext.insert(CachedMember(from: membership))
        try modelContainer.mainContext.save()

        let firstResult = await store.handleRemoteCloudChange(
            userId: userId,
            preferredHouseholdId: household.id
        )
        let secondResult = await store.handleRemoteCloudChange(
            userId: userId,
            preferredHouseholdId: household.id
        )

        XCTAssertEqual(firstResult, .newData)
        XCTAssertEqual(secondResult, .noData)
    }
}
