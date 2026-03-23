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
            $0.name == "fetchUnifiedWorkItems" && $0.scope == .participantShared && $0.householdId == household.id
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

    func testHandleRemoteCloudChangeReturnsNewDataWhenHouseholdMetadataChanges() async throws {
        let userId = "joined-user"
        let localHousehold = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let refreshedHousehold = Household(
            id: localHousehold.id,
            name: "Nowy Dom",
            iconSymbol: "building.2.fill",
            ownerId: localHousehold.ownerId,
            createdAt: localHousehold.createdAt,
            updatedAt: Date(timeIntervalSince1970: 2000)
        )
        let membership = TestCacheFixtures.member(
            householdId: localHousehold.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )

        let cloud = FakeHouseholdCloud(
            households: [refreshedHousehold],
            participantMembers: [membership],
            acceptedSharedHouseholdIDs: [localHousehold.id]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = localHousehold

        modelContainer.mainContext.insert(CachedHousehold(from: localHousehold))
        modelContainer.mainContext.insert(CachedMember(from: membership))
        try modelContainer.mainContext.save()

        let householdExpectation = expectation(
            forNotification: .householdDataDidChange,
            object: nil,
            handler: nil
        )

        let result = await store.handleRemoteCloudChange(
            userId: userId,
            preferredHouseholdId: localHousehold.id
        )

        await fulfillment(of: [householdExpectation], timeout: 1.0)

        XCTAssertEqual(result, .newData)
        XCTAssertEqual(store.currentHousehold?.name, "Nowy Dom")
        XCTAssertEqual(store.currentHousehold?.iconSymbol, "building.2.fill")
    }

    func testForceCloudSyncDebugPublishesStoreNotificationsAndRefreshesParticipantSharedCaches() async throws {
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
        let shoppingItem = TestCacheFixtures.shoppingItem(
            householdId: household.id,
            title: "Milk"
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [membership],
            tasks: [task],
            shoppingItems: [shoppingItem],
            backlogCategories: [category],
            acceptedSharedHouseholdIDs: [household.id]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = household

        modelContainer.mainContext.insert(CachedHousehold(from: household))
        modelContainer.mainContext.insert(CachedMember(from: membership))
        try modelContainer.mainContext.save()

        let householdExpectation = expectation(forNotification: .householdDataDidChange, object: nil)
        let shoppingExpectation = expectation(forNotification: .shoppingListDataDidChange, object: nil)
        let taskExpectation = expectation(forNotification: .taskBoardDataDidChange, object: nil)
        let backlogExpectation = expectation(forNotification: .backlogDataDidChange, object: nil)

        await store.forceCloudSyncDebug(userId: userId)

        await fulfillment(
            of: [
                householdExpectation,
                shoppingExpectation,
                taskExpectation,
                backlogExpectation,
            ],
            timeout: 1.0
        )

        XCTAssertEqual(try cachedMembers(for: household.id).count, 1)
        XCTAssertEqual(try cachedWorkItems(for: household.id).count, 1)
        XCTAssertEqual(try cachedShoppingItems(for: household.id).count, 1)
        XCTAssertEqual(try cachedBacklogCategories(for: household.id).count, 1)

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(operations.contains {
            $0.name == "fetchMembers" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchUnifiedWorkItems" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchShoppingItems" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchBacklogCategories" && $0.scope == .participantShared && $0.householdId == household.id
        })
    }

    func testRemoteVisibleContentDiffCountsRealInsertedRecords() {
        let existingTaskID = UUID()
        let addedTaskID = UUID()
        let existingShoppingID = UUID()
        let addedShoppingID = UUID()

        let before = RemoteVisibleContentSnapshot(
            shoppingTitlesByID: [existingShoppingID: "Milk"],
            shoppingBundleIDs: [UUID()],
            workItemIDs: [existingTaskID],
            backlogCategoryIDs: [UUID()]
        )

        let after = RemoteVisibleContentSnapshot(
            shoppingTitlesByID: [
                existingShoppingID: "Milk",
                addedShoppingID: "Bread",
            ],
            shoppingBundleIDs: before.shoppingBundleIDs.union([UUID()]),
            workItemIDs: before.workItemIDs.union([addedTaskID]),
            backlogCategoryIDs: before.backlogCategoryIDs.union([UUID()])
        )

        let diff = after.diff(from: before)

        XCTAssertEqual(diff.addedShoppingTitles, ["Bread"])
        XCTAssertEqual(diff.addedShoppingBundleCount, 1)
        XCTAssertEqual(diff.addedWorkItemCount, 1)
        XCTAssertEqual(diff.addedBacklogCategoryCount, 1)
        XCTAssertEqual(diff.totalAddedCount, 4)
    }
}
