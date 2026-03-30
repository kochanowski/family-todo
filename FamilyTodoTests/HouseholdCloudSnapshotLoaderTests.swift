import CloudKit
@testable import HousePulse
import XCTest

@MainActor
final class HouseholdCloudSnapshotLoaderTests: XCTestCase {
    private func containsOperation(
        _ operations: [FakeHouseholdCloud.OperationEvent],
        name: String,
        scope: CloudKitManager.HouseholdDatabaseScope,
        householdId: UUID
    ) -> Bool {
        operations.contains { operation in
            operation.name == name &&
                operation.scope == scope &&
                operation.householdId == householdId
        }
    }

    func testZoneResolverUsesOwnerZoneForOwnerContext() async throws {
        let ownerId = "owner-1"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: ownerId)
        let ownerZoneID = CKRecordZone.ID(zoneName: "household-\(household.id.uuidString)", ownerName: "__defaultOwner__")
        let cloud = FakeHouseholdCloud(
            households: [household],
            ownerZoneIDsByHouseholdId: [household.id: ownerZoneID]
        )
        let resolver = HouseholdZoneResolver(cloud: cloud)
        let context = try XCTUnwrap(
            HouseholdSyncContextFactory.make(
                household: household,
                currentUserId: ownerId
            )
        )

        let zoneID = try await resolver.resolveZone(for: context)

        XCTAssertEqual(zoneID, ownerZoneID)

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "ensureHouseholdOwnerZone",
                scope: .ownerPrivate,
                householdId: household.id
            )
        )
    }

    func testZoneResolverUsesSubscriptionZoneForParticipantContext() async throws {
        let ownerId = "owner-1"
        let participantId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: ownerId)
        let sharedZoneID = CKRecordZone.ID(zoneName: "shared-\(household.id.uuidString)", ownerName: "owner")
        let cloud = FakeHouseholdCloud(
            households: [household],
            acceptedSharedHouseholdIDs: [household.id],
            participantSharedZoneIDsByHouseholdId: [household.id: sharedZoneID]
        )
        let resolver = HouseholdZoneResolver(cloud: cloud)
        let context = try XCTUnwrap(
            HouseholdSyncContextFactory.make(
                household: household,
                currentUserId: participantId
            )
        )

        let zoneID = try await resolver.resolveZone(for: context)

        XCTAssertEqual(zoneID, sharedZoneID)

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "resolveSubscriptionZone",
                scope: .participantShared,
                householdId: household.id
            )
        )
    }

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
        let context = try XCTUnwrap(
            HouseholdSyncContextFactory.make(
                household: household,
                currentUserId: userId
            )
        )

        let snapshot = try await repository.loadCloudSnapshot(for: context)

        XCTAssertEqual(snapshot.members.map(\.id), [member.id])
        XCTAssertEqual(snapshot.shoppingItems.map(\.id), [shoppingItem.id])

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchMembers",
                scope: .participantShared,
                householdId: household.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchShoppingItems",
                scope: .participantShared,
                householdId: household.id
            )
        )
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
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchMemberByUserId",
                scope: .participantShared,
                householdId: household.id
            )
        )
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
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchMembers",
                scope: .participantShared,
                householdId: household.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchUnifiedWorkItems",
                scope: .participantShared,
                householdId: household.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchShoppingItems",
                scope: .participantShared,
                householdId: household.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchShoppingBundles",
                scope: .participantShared,
                householdId: household.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchBacklogCategories",
                scope: .participantShared,
                householdId: household.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchBacklogItems",
                scope: .participantShared,
                householdId: household.id
            )
        )
    }
}
