@testable import HousePulse
import SwiftData
import UIKit
import XCTest

@MainActor
final class HouseholdJoinFlowTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var suiteName: String?
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        modelContainer = try TestModelContainerFactory.makeInMemoryContainer(profile: .household)
        let isolatedDefaults = TestModelContainerFactory.makeUserDefaults(
            suitePrefix: "HouseholdJoinFlowTests"
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
        let defaultHydrationConfiguration = HouseholdStore.JoinHydrationConfiguration(
            initialHydrationBudgetNanoseconds: 20_000_000,
            initialRetryDelaysNanoseconds: [0],
            backgroundRetryDelaysNanoseconds: [],
            pendingJoinGraceDuration: 30
        )
        return makeStore(
            cloud: cloud,
            joinedHouseholdPrewarmOverride: { _, _, _ in },
            joinHydrationConfiguration: defaultHydrationConfiguration
        )
    }

    private func makeStore(
        cloud: FakeHouseholdCloud,
        joinedHouseholdPrewarmOverride: @escaping (Household, String, ModelContext?) async throws -> Void,
        joinHydrationConfiguration: HouseholdStore.JoinHydrationConfiguration
    ) -> HouseholdStore {
        HouseholdStore(
            modelContext: modelContainer.mainContext,
            cloudKit: cloud,
            joinedHouseholdPrewarmOverride: joinedHouseholdPrewarmOverride,
            userDefaults: defaults,
            recoverySuppressionDuration: 300,
            joinHydrationConfiguration: joinHydrationConfiguration
        )
    }

    private func cachedMembers(for householdId: UUID) throws -> [CachedMember] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedMember>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    private func cachedHouseholds() throws -> [CachedHousehold] {
        try modelContainer.mainContext.fetch(FetchDescriptor<CachedHousehold>())
    }

    private func cachedWorkItems(for householdId: UUID) throws -> [CachedWorkItem] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedWorkItem>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    func testJoinInviteCodeUsesResolvedTargetHouseholdAndIgnoresStaleRecoveredHousehold() async throws {
        let userId = "joined-user"
        let staleHousehold = TestCacheFixtures.household(name: "Ghost Home", ownerId: userId)
        let targetHousehold = TestCacheFixtures.household(name: "Target Home", ownerId: "owner-2")
        let staleMembership = TestCacheFixtures.member(
            householdId: staleHousehold.id,
            userId: userId,
            displayName: "Jamie",
            role: .owner
        )
        let inviteToken = InviteToken(
            id: "A7B9XQ2M",
            code: "A7B9XQ2M",
            householdId: targetHousehold.id,
            shareURL: "https://www.icloud.com/share/test",
            createdAt: TestCacheFixtures.referenceDate,
            expiresAt: TestCacheFixtures.referenceDate.addingTimeInterval(InviteToken.ttl),
            isRevoked: false,
            usesCount: 0
        )

        let cloud = FakeHouseholdCloud(
            households: [staleHousehold, targetHousehold],
            inviteTokens: [inviteToken],
            inviteRedeemResults: [inviteToken.code: targetHousehold],
            ownerMembers: [staleMembership]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)

        modelContainer.mainContext.insert(CachedHousehold(from: staleHousehold))
        modelContainer.mainContext.insert(CachedMember(from: staleMembership))
        try modelContainer.mainContext.save()
        store.currentHousehold = staleHousehold

        try await store.joinHousehold(
            inviteCode: inviteToken.code,
            userId: userId,
            displayName: "Jamie"
        )

        XCTAssertEqual(store.currentHousehold?.id, targetHousehold.id)
        XCTAssertEqual(try cachedHouseholds().map(\.id), [targetHousehold.id])
        XCTAssertEqual(try cachedMembers(for: targetHousehold.id).count, 1)
        XCTAssertTrue(try cachedMembers(for: staleHousehold.id).isEmpty)
        let staleInactiveUpdateCount = await cloud.inactiveUpdateCount(for: staleHousehold.id)
        XCTAssertEqual(staleInactiveUpdateCount, 1)
    }

    func testJoinCreatesLocalCachedMemberImmediatelyForTargetHousehold() async throws {
        let userId = "joined-user"
        let targetHousehold = TestCacheFixtures.household(name: "Joined Home", ownerId: "owner-2")
        let inviteToken = InviteToken(
            id: "B8C9DQ2M",
            code: "B8C9DQ2M",
            householdId: targetHousehold.id,
            shareURL: "https://www.icloud.com/share/test2",
            createdAt: TestCacheFixtures.referenceDate,
            expiresAt: TestCacheFixtures.referenceDate.addingTimeInterval(InviteToken.ttl),
            isRevoked: false,
            usesCount: 0
        )

        let cloud = FakeHouseholdCloud(
            households: [targetHousehold],
            inviteTokens: [inviteToken],
            inviteRedeemResults: [inviteToken.code: targetHousehold]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)

        try await store.joinHousehold(
            inviteCode: inviteToken.code,
            userId: userId,
            displayName: "Taylor"
        )

        XCTAssertEqual(store.currentHousehold?.id, targetHousehold.id)
        let cachedTargetMembers = try cachedMembers(for: targetHousehold.id)
        XCTAssertEqual(cachedTargetMembers.count, 1)
        XCTAssertEqual(cachedTargetMembers.first?.userId, userId)
        XCTAssertTrue(cachedTargetMembers.first?.isActive ?? false)
    }

    func testJoinInviteCodeClearsStaleLocalHouseholdSelection() async throws {
        let userId = "joined-user"
        let staleHousehold = TestCacheFixtures.household(name: "Stale Local", ownerId: "owner-old")
        let targetHousehold = TestCacheFixtures.household(name: "Fresh Target", ownerId: "owner-new")
        let inviteToken = InviteToken(
            id: "C9D8EQ2M",
            code: "C9D8EQ2M",
            householdId: targetHousehold.id,
            shareURL: "https://www.icloud.com/share/test3",
            createdAt: TestCacheFixtures.referenceDate,
            expiresAt: TestCacheFixtures.referenceDate.addingTimeInterval(InviteToken.ttl),
            isRevoked: false,
            usesCount: 0
        )

        let cloud = FakeHouseholdCloud(
            households: [targetHousehold],
            inviteTokens: [inviteToken],
            inviteRedeemResults: [inviteToken.code: targetHousehold]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)

        modelContainer.mainContext.insert(CachedHousehold(from: staleHousehold))
        try modelContainer.mainContext.save()
        store.currentHousehold = staleHousehold

        try await store.joinHousehold(
            inviteCode: inviteToken.code,
            userId: userId,
            displayName: "Taylor"
        )

        XCTAssertEqual(store.currentHousehold?.id, targetHousehold.id)
        XCTAssertEqual(try cachedHouseholds().map(\.id), [targetHousehold.id])
    }

    func testCreateHouseholdPreflightDoesNotMutateCurrentHouseholdWhenRemoteMembershipExists() async throws {
        let userId = "existing-user"
        let existingHousehold = TestCacheFixtures.household(name: "Already There", ownerId: "owner")
        let existingMembership = TestCacheFixtures.member(
            householdId: existingHousehold.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )

        let cloud = FakeHouseholdCloud(
            households: [existingHousehold],
            participantMembers: [existingMembership]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)

        do {
            _ = try await store.createHousehold(
                name: "New Home",
                userId: userId,
                displayName: "Taylor"
            )
            XCTFail("Expected alreadyInHousehold error")
        } catch let error as HouseholdError {
            XCTAssertEqual(error, .alreadyInHousehold)
        }

        XCTAssertNil(store.currentHousehold)
        XCTAssertTrue(try cachedHouseholds().isEmpty)
    }

    func testRecoveryIgnoresAmbiguousActiveMemberships() async {
        let userId = "ambiguous-user"
        let participantHousehold = TestCacheFixtures.household(name: "Shared Home", ownerId: "owner-a")
        let ownerHousehold = TestCacheFixtures.household(name: "Owned Home", ownerId: userId)
        let participantMembership = TestCacheFixtures.member(
            householdId: participantHousehold.id,
            userId: userId,
            displayName: "Jamie",
            role: .member
        )
        let ownerMembership = TestCacheFixtures.member(
            householdId: ownerHousehold.id,
            userId: userId,
            displayName: "Jamie",
            role: .owner
        )

        let cloud = FakeHouseholdCloud(
            households: [participantHousehold, ownerHousehold],
            participantMembers: [participantMembership],
            ownerMembers: [ownerMembership]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)

        await store.refreshCurrentHouseholdAndMembershipFromCloud(userId: userId)

        XCTAssertNil(store.currentHousehold)
    }

    func testHardResetCloudCleanupDeactivatesParticipantMembershipAndLeavesShare() async {
        let userId = "participant-user"
        let household = TestCacheFixtures.household(name: "Shared Home", ownerId: "owner-a")
        let membership = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Jamie",
            role: .member
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [membership]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = household

        await store.hardResetCloudHousehold(userId: userId)

        let inactiveUpdateCount = await cloud.inactiveUpdateCount(for: household.id)
        let leftSharedHouseholds = await cloud.leftSharedHouseholdsSnapshot()
        XCTAssertEqual(inactiveUpdateCount, 1)
        XCTAssertEqual(leftSharedHouseholds, [household.id])
    }

    func testJoinWaitsForInitialHydrationWhenSharedDataArrivesQuickly() async throws {
        let userId = "joined-user"
        let targetHousehold = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-2")
        let inviteToken = InviteToken(
            id: "Q2W3E4R5",
            code: "Q2W3E4R5",
            householdId: targetHousehold.id,
            shareURL: "https://www.icloud.com/share/test-quick",
            createdAt: TestCacheFixtures.referenceDate,
            expiresAt: TestCacheFixtures.referenceDate.addingTimeInterval(InviteToken.ttl),
            isRevoked: false,
            usesCount: 0
        )

        let quickIdea = TestCacheFixtures.idea(
            categoryId: UUID(),
            householdId: targetHousehold.id,
            title: "Plan weekend"
        )
        let hydrationConfig = HouseholdStore.JoinHydrationConfiguration(
            initialHydrationBudgetNanoseconds: 500_000_000,
            initialRetryDelaysNanoseconds: [0],
            backgroundRetryDelaysNanoseconds: [],
            pendingJoinGraceDuration: 30
        )
        let cloud = FakeHouseholdCloud(
            households: [targetHousehold],
            inviteTokens: [inviteToken],
            inviteRedeemResults: [inviteToken.code: targetHousehold]
        )

        let store = makeStore(
            cloud: cloud,
            joinedHouseholdPrewarmOverride: { _, _, context in
                try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
                guard let context else { return }
                context.insert(TestCacheFixtures.cachedWorkItem(from: WorkItem(idea: quickIdea)))
                try context.save()
            },
            joinHydrationConfiguration: hydrationConfig
        )
        store.setSyncMode(SyncMode.cloud)

        try await store.joinHousehold(
            inviteCode: inviteToken.code,
            userId: userId,
            displayName: "Taylor"
        )

        XCTAssertEqual(store.currentHousehold?.id, targetHousehold.id)
        XCTAssertEqual(try cachedWorkItems(for: targetHousehold.id).count, 1)
        XCTAssertEqual(try cachedMembers(for: targetHousehold.id).count, 1)
    }

    func testJoinTimeoutKeepsLocalHouseholdAndCachedMember() async throws {
        let userId = "joined-user"
        let targetHousehold = TestCacheFixtures.household(name: "Timeout Home", ownerId: "owner-2")
        let inviteToken = InviteToken(
            id: "T1M3O5U7",
            code: "T1M3O5U7",
            householdId: targetHousehold.id,
            shareURL: "https://www.icloud.com/share/test-timeout",
            createdAt: TestCacheFixtures.referenceDate,
            expiresAt: TestCacheFixtures.referenceDate.addingTimeInterval(InviteToken.ttl),
            isRevoked: false,
            usesCount: 0
        )
        let hydrationConfig = HouseholdStore.JoinHydrationConfiguration(
            initialHydrationBudgetNanoseconds: 20_000_000,
            initialRetryDelaysNanoseconds: [0],
            backgroundRetryDelaysNanoseconds: [],
            pendingJoinGraceDuration: 30
        )
        let cloud = FakeHouseholdCloud(
            households: [targetHousehold],
            inviteTokens: [inviteToken],
            inviteRedeemResults: [inviteToken.code: targetHousehold]
        )

        let store = makeStore(
            cloud: cloud,
            joinedHouseholdPrewarmOverride: { _, _, _ in
                try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            },
            joinHydrationConfiguration: hydrationConfig
        )
        store.setSyncMode(.cloud)

        try await store.joinHousehold(
            inviteCode: inviteToken.code,
            userId: userId,
            displayName: "Taylor"
        )

        XCTAssertEqual(store.currentHousehold?.id, targetHousehold.id)
        XCTAssertEqual(try cachedMembers(for: targetHousehold.id).count, 1)
    }

    func testPendingJoinProtectionPreventsImmediateInvalidationDuringEchoGap() async throws {
        let userId = "joined-user"
        let targetHousehold = TestCacheFixtures.household(name: "Echo Gap Home", ownerId: "owner-2")
        let inviteToken = InviteToken(
            id: "E1C2H3O4",
            code: "E1C2H3O4",
            householdId: targetHousehold.id,
            shareURL: "https://www.icloud.com/share/test-echo",
            createdAt: TestCacheFixtures.referenceDate,
            expiresAt: TestCacheFixtures.referenceDate.addingTimeInterval(InviteToken.ttl),
            isRevoked: false,
            usesCount: 0
        )
        let hydrationConfig = HouseholdStore.JoinHydrationConfiguration(
            initialHydrationBudgetNanoseconds: 20_000_000,
            initialRetryDelaysNanoseconds: [0],
            backgroundRetryDelaysNanoseconds: [],
            pendingJoinGraceDuration: 30
        )
        let cloud = FakeHouseholdCloud(
            households: [targetHousehold],
            inviteTokens: [inviteToken],
            inviteRedeemResults: [inviteToken.code: targetHousehold]
        )

        let store = makeStore(
            cloud: cloud,
            joinedHouseholdPrewarmOverride: { _, _, _ in
                try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            },
            joinHydrationConfiguration: hydrationConfig
        )
        store.setSyncMode(.cloud)

        try await store.joinHousehold(
            inviteCode: inviteToken.code,
            userId: userId,
            displayName: "Taylor"
        )

        let validationResult = try await store.validateRecoveredMembershipOrAbandon(
            household: targetHousehold,
            userId: userId,
            retryDelaysNanoseconds: [0],
            fetchActiveMember: { _, _ in nil }
        )

        XCTAssertTrue(validationResult)
        XCTAssertEqual(store.currentHousehold?.id, targetHousehold.id)
        XCTAssertTrue(store.hasPendingJoinProtection(for: targetHousehold.id, userId: userId))
    }

    func testJoinAcceptsShareBeforeParticipantMembershipWriteAndVerifyUsesParticipantScope() async throws {
        let userId = "joined-user"
        let targetHousehold = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-2")
        let inviteToken = InviteToken(
            id: "S8H7A6R5",
            code: "S8H7A6R5",
            householdId: targetHousehold.id,
            shareURL: "https://www.icloud.com/share/verified-join",
            createdAt: TestCacheFixtures.referenceDate,
            expiresAt: TestCacheFixtures.referenceDate.addingTimeInterval(InviteToken.ttl),
            isRevoked: false,
            usesCount: 0
        )

        let cloud = FakeHouseholdCloud(
            households: [targetHousehold],
            inviteTokens: [inviteToken]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)

        try await store.joinHousehold(
            inviteCode: inviteToken.code,
            userId: userId,
            displayName: "Taylor"
        )

        let acceptedShare = await cloud.hasAcceptedSharedHousehold(targetHousehold.id)
        let operations = await cloud.operationEventsSnapshot()
        let memberSaveEvent = operations.first {
            $0.name == "saveMember" && $0.householdId == targetHousehold.id
        }
        let memberVerifyEvent = operations.last {
            $0.name == "fetchMemberByUserId" && $0.householdId == targetHousehold.id
        }

        XCTAssertTrue(acceptedShare)
        XCTAssertEqual(memberSaveEvent?.scope, .participantShared)
        XCTAssertEqual(memberVerifyEvent?.scope, .participantShared)
        XCTAssertEqual(store.currentHousehold?.id, targetHousehold.id)
    }

    func testJoinDoesNotSetCurrentHouseholdWhenParticipantSharedMembershipVerificationFails() async throws {
        let userId = "joined-user"
        let targetHousehold = TestCacheFixtures.household(name: "Broken Share", ownerId: "owner-2")
        let inviteToken = InviteToken(
            id: "B1R2O3K4",
            code: "B1R2O3K4",
            householdId: targetHousehold.id,
            shareURL: "https://www.icloud.com/share/broken-share",
            createdAt: TestCacheFixtures.referenceDate,
            expiresAt: TestCacheFixtures.referenceDate.addingTimeInterval(InviteToken.ttl),
            isRevoked: false,
            usesCount: 0
        )

        let cloud = FakeHouseholdCloud(
            households: [targetHousehold],
            inviteTokens: [inviteToken],
            participantSharedVerificationDeniedHouseholds: [targetHousehold.id]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)

        do {
            try await store.joinHousehold(
                inviteCode: inviteToken.code,
                userId: userId,
                displayName: "Taylor"
            )
            XCTFail("Expected sharedAccessNotEstablished error")
        } catch let error as HouseholdError {
            XCTAssertEqual(error, .sharedAccessNotEstablished)
        }

        XCTAssertNil(store.currentHousehold)
        XCTAssertTrue(try cachedHouseholds().isEmpty)
        XCTAssertTrue(try cachedMembers(for: targetHousehold.id).isEmpty)
        XCTAssertFalse(store.hasPendingJoinProtection(for: targetHousehold.id, userId: userId))
    }

    func testFetchOrCreateInviteCodeDelegatesReuseDecisionToCloudKitManager() async throws {
        let household = TestCacheFixtures.household(name: "Invite Home", ownerId: "owner-1")
        let cachedToken = InviteToken(
            id: "C4C4E4D1",
            code: "C4C4E4D1",
            householdId: household.id,
            shareURL: "https://www.icloud.com/share/stale"
        )
        let refreshedToken = InviteToken(
            id: "R3F2R1S9",
            code: "R3F2R1S9",
            householdId: household.id,
            shareURL: "https://www.icloud.com/share/live"
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            inviteTokens: [cachedToken],
            createInviteCodeResultsByHouseholdId: [household.id: refreshedToken]
        )
        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = household
        store.activeInviteCode = cachedToken.code

        let code = try await store.fetchOrCreateInviteCode()

        XCTAssertEqual(code, refreshedToken.code)
        XCTAssertEqual(store.activeInviteCode, refreshedToken.code)
        let createInviteCodeCallCount = await cloud.createInviteCodeCallCount()
        XCTAssertEqual(createInviteCodeCallCount, 1)
    }
}
