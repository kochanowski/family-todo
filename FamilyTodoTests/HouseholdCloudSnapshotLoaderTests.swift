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

    func testRepositoryFetchesActiveScopedMembershipsAcrossOwnerAndParticipantScopes() async throws {
        let userId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let participantMember = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Taylor Shared",
            role: .member
        )
        let ownerMember = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Taylor Owner",
            role: .member
        )
        let ownerZoneID = CKRecordZone.ID(
            zoneName: "household-\(household.id.uuidString)",
            ownerName: "__defaultOwner__"
        )
        let sharedZoneID = CKRecordZone.ID(
            zoneName: "shared-\(household.id.uuidString)",
            ownerName: "owner"
        )
        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [participantMember],
            ownerMembers: [ownerMember],
            acceptedSharedHouseholdIDs: [household.id],
            ownerZoneIDsByHouseholdId: [household.id: ownerZoneID],
            participantSharedZoneIDsByHouseholdId: [household.id: sharedZoneID]
        )
        let repository = HouseholdRepository(cloud: cloud)

        let memberships = try await repository.fetchActiveScopedMemberships(
            userId: userId,
            householdId: household.id
        )

        XCTAssertEqual(memberships.count, 2)
        XCTAssertEqual(
            Set(memberships.map(\.scope)),
            Set([.ownerPrivate, .participantShared])
        )

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "resolveSubscriptionZone",
                scope: .participantShared,
                householdId: household.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "ensureHouseholdOwnerZone",
                scope: .ownerPrivate,
                householdId: household.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchActiveMembersByUserId",
                scope: .participantShared,
                householdId: household.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchActiveMembersByUserId",
                scope: .ownerPrivate,
                householdId: household.id
            )
        )
    }

    func testRepositoryFetchesHouseholdForScopedMembershipUsingMatchingScope() async throws {
        let ownerId = "owner-1"
        let participantId = "joined-user"
        let ownerHousehold = TestCacheFixtures.household(name: "Owner House", ownerId: ownerId)
        let participantHousehold = TestCacheFixtures.household(name: "Shared House", ownerId: ownerId)
        let ownerMember = TestCacheFixtures.member(
            householdId: ownerHousehold.id,
            userId: ownerId,
            displayName: "Owner",
            role: .owner
        )
        let participantMember = TestCacheFixtures.member(
            householdId: participantHousehold.id,
            userId: participantId,
            displayName: "Taylor",
            role: .member
        )
        let ownerZoneID = CKRecordZone.ID(
            zoneName: "household-\(ownerHousehold.id.uuidString)",
            ownerName: "__defaultOwner__"
        )
        let sharedZoneID = CKRecordZone.ID(
            zoneName: "shared-\(participantHousehold.id.uuidString)",
            ownerName: "owner"
        )
        let cloud = FakeHouseholdCloud(
            households: [ownerHousehold, participantHousehold],
            participantMembers: [participantMember],
            ownerMembers: [ownerMember],
            acceptedSharedHouseholdIDs: [participantHousehold.id],
            ownerZoneIDsByHouseholdId: [ownerHousehold.id: ownerZoneID],
            participantSharedZoneIDsByHouseholdId: [participantHousehold.id: sharedZoneID]
        )
        let repository = HouseholdRepository(cloud: cloud)

        let fetchedOwnerHousehold = try await repository.fetchHousehold(
            for: HouseholdScopedMembership(member: ownerMember, scope: .ownerPrivate)
        )
        let fetchedParticipantHousehold = try await repository.fetchHousehold(
            for: HouseholdScopedMembership(member: participantMember, scope: .participantShared)
        )

        XCTAssertEqual(fetchedOwnerHousehold.id, ownerHousehold.id)
        XCTAssertEqual(fetchedParticipantHousehold.id, participantHousehold.id)

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "ensureHouseholdOwnerZone",
                scope: .ownerPrivate,
                householdId: ownerHousehold.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchHousehold",
                scope: .ownerPrivate,
                householdId: ownerHousehold.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "resolveSubscriptionZone",
                scope: .participantShared,
                householdId: participantHousehold.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchHousehold",
                scope: .participantShared,
                householdId: participantHousehold.id
            )
        )
    }

    func testRepositoryFetchesRecoverableCandidatesAcrossScopesAndMissingHouseholds() async throws {
        let userId = "joined-user"
        let ownerHousehold = TestCacheFixtures.household(name: "Owner House", ownerId: userId)
        let missingSharedHouseholdId = UUID()
        let ownerMember = TestCacheFixtures.member(
            householdId: ownerHousehold.id,
            userId: userId,
            displayName: "Owner",
            role: .owner
        )
        let participantMember = TestCacheFixtures.member(
            householdId: missingSharedHouseholdId,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )
        let ownerZoneID = CKRecordZone.ID(
            zoneName: "household-\(ownerHousehold.id.uuidString)",
            ownerName: "__defaultOwner__"
        )
        let missingSharedZoneID = CKRecordZone.ID(
            zoneName: "shared-\(missingSharedHouseholdId.uuidString)",
            ownerName: "owner"
        )
        let cloud = FakeHouseholdCloud(
            households: [ownerHousehold],
            participantMembers: [participantMember],
            ownerMembers: [ownerMember],
            acceptedSharedHouseholdIDs: [missingSharedHouseholdId],
            ownerZoneIDsByHouseholdId: [ownerHousehold.id: ownerZoneID],
            participantSharedZoneIDsByHouseholdId: [missingSharedHouseholdId: missingSharedZoneID]
        )
        let repository = HouseholdRepository(cloud: cloud)

        let candidates = try await repository.fetchRecoverableCandidates(userId: userId)

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(
            candidates.first { $0.membership.scope == .ownerPrivate }?.household?.id,
            ownerHousehold.id
        )
        XCTAssertNil(
            candidates.first { $0.membership.scope == .participantShared }?.household
        )
    }

    func testRepositoryCleansUpStaleRecoverableMembershipUsingMatchingScope() async throws {
        let userId = "joined-user"
        let ownerHousehold = TestCacheFixtures.household(name: "Owner House", ownerId: userId)
        let sharedHousehold = TestCacheFixtures.household(name: "Shared House", ownerId: "owner-1")
        let ownerMember = TestCacheFixtures.member(
            householdId: ownerHousehold.id,
            userId: userId,
            displayName: "Owner",
            role: .owner
        )
        let participantMember = TestCacheFixtures.member(
            householdId: sharedHousehold.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )
        let cloud = FakeHouseholdCloud(
            households: [ownerHousehold, sharedHousehold],
            participantMembers: [participantMember],
            ownerMembers: [ownerMember],
            acceptedSharedHouseholdIDs: [sharedHousehold.id]
        )
        let repository = HouseholdRepository(cloud: cloud)

        try await repository.cleanupStaleRecoverableMembership(
            HouseholdScopedMembership(member: ownerMember, scope: .ownerPrivate)
        )
        try await repository.cleanupStaleRecoverableMembership(
            HouseholdScopedMembership(member: participantMember, scope: .participantShared)
        )

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "updateMemberState",
                scope: .ownerPrivate,
                householdId: ownerHousehold.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "updateMemberState",
                scope: .participantShared,
                householdId: sharedHousehold.id
            )
        )
        let ownerInactiveUpdateCount = await cloud.inactiveUpdateCount(for: ownerHousehold.id)
        let sharedInactiveUpdateCount = await cloud.inactiveUpdateCount(for: sharedHousehold.id)
        XCTAssertEqual(ownerInactiveUpdateCount, 1)
        XCTAssertEqual(sharedInactiveUpdateCount, 1)
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
        let workItem = WorkItem(
            householdId: household.id,
            title: "Legacy work item",
            status: .backlog,
            categoryId: category.id,
            createdAt: Date(timeIntervalSince1970: 3),
            updatedAt: Date(timeIntervalSince1970: 4)
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
            workItems: [workItem],
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
        XCTAssertEqual(Set(snapshot.unifiedWorkItems.map(\.id)), Set([task.id, workItem.id, idea.id]))
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
                name: "fetchTasks",
                scope: .participantShared,
                householdId: household.id
            )
        )
        XCTAssertTrue(
            containsOperation(
                operations,
                name: "fetchWorkItems",
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
        XCTAssertFalse(operations.contains { $0.name == "fetchUnifiedWorkItems" })
        XCTAssertEqual(
            operations.filter { $0.name == "fetchBacklogItems" && $0.householdId == household.id }.count,
            1
        )
    }

    func testLoadSnapshotTimesOutWhenDomainFetchStalls() async throws {
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let cloud = FakeHouseholdCloud(
            households: [household],
            acceptedSharedHouseholdIDs: [household.id],
            fetchDelayNanosecondsByOperation: ["fetchShoppingItems": 500_000_000]
        )
        let loader = HouseholdCloudSnapshotLoader(
            cloud: cloud,
            domainFetchTimeoutNanoseconds: 50_000_000,
            snapshotTimeoutNanoseconds: 250_000_000
        )

        do {
            _ = try await loader.loadSnapshot(
                householdId: household.id,
                scope: .participantShared
            )
            XCTFail("Expected snapshot timeout")
        } catch let error as HouseholdCloudSnapshotLoaderError {
            XCTAssertEqual(error, .domainFetchTimedOut("shoppingItems"))
        }
    }
}
