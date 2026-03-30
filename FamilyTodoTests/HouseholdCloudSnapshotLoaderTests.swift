@testable import HousePulse
import XCTest

@MainActor
final class HouseholdCloudSnapshotLoaderTests: XCTestCase {
    func testRepositoryLoadsSnapshotUsingSyncContextScopeAndHousehold() async throws {
        let userId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let member = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )
        let shoppingItem = TestCacheFixtures.shoppingItem(
            householdId: household.id,
            title: "Milk"
        )
        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [member],
            shoppingItems: [shoppingItem],
            acceptedSharedHouseholdIDs: [household.id]
        )
        let repository = HouseholdRepository(cloud: cloud)
        let context = HouseholdSyncContextFactory.make(
            household: household,
            currentUserId: userId
        )

        let snapshot = try await XCTUnwrap(
            try repository.loadCloudSnapshot(for: context)
        )

        XCTAssertEqual(snapshot.members.map(\.id), [member.id])
        XCTAssertEqual(snapshot.shoppingItems.map(\.id), [shoppingItem.id])

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(operations.contains {
            $0.name == "fetchMembers" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchShoppingItems" && $0.scope == .participantShared && $0.householdId == household.id
        })
    }

    func testRepositoryConfirmsActiveMembershipUsingSyncContext() async throws {
        let userId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let member = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )
        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [member],
            acceptedSharedHouseholdIDs: [household.id]
        )
        let repository = HouseholdRepository(cloud: cloud)
        let context = try XCTUnwrap(
            HouseholdSyncContextFactory.make(
                household: household,
                currentUserId: userId
            )
        )

        let isActive = try await repository.hasActiveMembership(
            userId: userId,
            in: context
        )

        XCTAssertTrue(isActive)

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(operations.contains {
            $0.name == "fetchMemberByUserId" &&
                $0.scope == .participantShared &&
                $0.householdId == household.id
        })
    }

    func testLoadSnapshotFetchesEntireHouseholdGraphUsingProvidedScope() async throws {
        let userId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let member = TestCacheFixtures.member(
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
            name: "Weekly"
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [member],
            tasks: [task],
            shoppingItems: [shoppingItem],
            shoppingBundles: [bundle],
            backlogItems: [idea],
            backlogCategories: [category],
            acceptedSharedHouseholdIDs: [household.id]
        )
        let loader = HouseholdCloudSnapshotLoader(cloud: cloud)

        let snapshot = try await loader.loadSnapshot(
            householdId: household.id,
            scope: .participantShared
        )

        XCTAssertEqual(snapshot.members.map(\.id), [member.id])
        XCTAssertEqual(Set(snapshot.unifiedWorkItems.map(\.id)), Set([task.id, idea.id]))
        XCTAssertEqual(snapshot.shoppingItems.map(\.id), [shoppingItem.id])
        XCTAssertEqual(snapshot.shoppingBundles.map(\.id), [bundle.id])
        XCTAssertEqual(snapshot.backlogCategories.map(\.id), [category.id])
        XCTAssertEqual(snapshot.backlogItems.map(\.id), [idea.id])
        XCTAssertTrue(snapshot.hasActiveMembership(userId: userId))

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
            $0.name == "fetchShoppingBundles" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchBacklogCategories" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchBacklogItems" && $0.scope == .participantShared && $0.householdId == household.id
        })
    }
}
