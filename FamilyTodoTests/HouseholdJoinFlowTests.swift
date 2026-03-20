import CloudKit
@testable import HousePulse
import SwiftData
import UIKit
import XCTest

private enum HouseholdJoinTestError: Error {
    case unimplemented
    case missingInviteToken(String)
}

// swiftlint:enable file_length

actor FakeHouseholdCloud: HouseholdCloudSyncing {
    struct MemberStateUpdate: Equatable {
        let memberId: UUID
        let householdId: UUID
        let isActive: Bool
    }

    struct OperationEvent: Equatable {
        let name: String
        let scope: CloudKitManager.HouseholdDatabaseScope
        let householdId: UUID?
    }

    private var currentScope: CloudKitManager.HouseholdDatabaseScope = .participantShared
    private var householdsById: [UUID: Household]
    private var inviteTokensByCode: [String: InviteToken]
    private var inviteRedeemResults: [String: Household]
    private var participantMembers: [Member]
    private var ownerMembers: [Member]
    private var tasks: [Task]
    private var shoppingItems: [ShoppingItem]
    private var shoppingBundles: [ShoppingBundle]
    private var backlogItems: [BacklogItem]
    private var backlogCategories: [BacklogCategory]
    private var memberStateUpdates: [MemberStateUpdate] = []
    private var leftSharedHouseholds: [UUID] = []
    private var acceptedSharedHouseholdIDs: Set<UUID>
    private let requiresAcceptedShareForParticipantScope: Bool
    private let participantSharedWriteDeniedHouseholds: Set<UUID>
    private let participantSharedReadDeniedHouseholds: Set<UUID>
    private let participantSharedVerificationDeniedHouseholds: Set<UUID>
    private var operationEvents: [OperationEvent] = []

    init(
        households: [Household] = [],
        inviteTokens: [InviteToken] = [],
        inviteRedeemResults: [String: Household] = [:],
        participantMembers: [Member] = [],
        ownerMembers: [Member] = [],
        tasks: [Task] = [],
        shoppingItems: [ShoppingItem] = [],
        shoppingBundles: [ShoppingBundle] = [],
        backlogItems: [BacklogItem] = [],
        backlogCategories: [BacklogCategory] = [],
        acceptedSharedHouseholdIDs: Set<UUID> = [],
        requiresAcceptedShareForParticipantScope: Bool = true,
        participantSharedWriteDeniedHouseholds: Set<UUID> = [],
        participantSharedReadDeniedHouseholds: Set<UUID> = [],
        participantSharedVerificationDeniedHouseholds: Set<UUID> = []
    ) {
        householdsById = Dictionary(uniqueKeysWithValues: households.map { ($0.id, $0) })
        inviteTokensByCode = Dictionary(uniqueKeysWithValues: inviteTokens.map { ($0.code, $0) })
        self.inviteRedeemResults = inviteRedeemResults
        self.participantMembers = participantMembers
        self.ownerMembers = ownerMembers
        self.tasks = tasks
        self.shoppingItems = shoppingItems
        self.shoppingBundles = shoppingBundles
        self.backlogItems = backlogItems
        self.backlogCategories = backlogCategories
        self.acceptedSharedHouseholdIDs = acceptedSharedHouseholdIDs.union(Set(participantMembers.map(\.householdId)))
        self.requiresAcceptedShareForParticipantScope = requiresAcceptedShareForParticipantScope
        self.participantSharedWriteDeniedHouseholds = participantSharedWriteDeniedHouseholds
        self.participantSharedReadDeniedHouseholds = participantSharedReadDeniedHouseholds
        self.participantSharedVerificationDeniedHouseholds = participantSharedVerificationDeniedHouseholds
    }

    private func resolvedScope(_ explicitScope: CloudKitManager.HouseholdDatabaseScope?)
        -> CloudKitManager.HouseholdDatabaseScope
    {
        explicitScope ?? currentScope
    }

    private func members(for scope: CloudKitManager.HouseholdDatabaseScope) -> [Member] {
        switch scope {
        case .participantShared:
            participantMembers
        case .ownerPrivate:
            ownerMembers
        }
    }

    private func setMembers(_ members: [Member], for scope: CloudKitManager.HouseholdDatabaseScope) {
        switch scope {
        case .participantShared:
            participantMembers = members
        case .ownerPrivate:
            ownerMembers = members
        }
    }

    private func appendOperation(
        _ name: String,
        scope: CloudKitManager.HouseholdDatabaseScope,
        householdId: UUID? = nil
    ) {
        operationEvents.append(
            OperationEvent(name: name, scope: scope, householdId: householdId)
        )
    }

    private func ensureParticipantSharedAccess(
        householdId: UUID?,
        operation: String,
        forWrite: Bool
    ) throws {
        guard requiresAcceptedShareForParticipantScope else { return }
        guard let householdId else { return }

        if forWrite, participantSharedWriteDeniedHouseholds.contains(householdId) {
            throw CKError(.permissionFailure)
        }

        if !forWrite, participantSharedReadDeniedHouseholds.contains(householdId) {
            throw CKError(.zoneNotFound)
        }

        if !forWrite,
           operation == "fetchMemberByUserId",
           participantSharedVerificationDeniedHouseholds.contains(householdId)
        {
            throw CKError(.zoneNotFound)
        }

        guard acceptedSharedHouseholdIDs.contains(householdId) else {
            throw CKError(forWrite ? .permissionFailure : .zoneNotFound)
        }
    }

    private func mirrorParticipantMemberIntoOwnerScope(_ member: Member) {
        if let existingIndex = ownerMembers.firstIndex(where: { $0.id == member.id }) {
            ownerMembers[existingIndex] = member
        } else {
            ownerMembers.append(member)
        }
    }

    private func makeRecord(recordType: String, id: UUID) -> CKRecord {
        CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: id.uuidString))
    }

    func ensureReady() async {}
    func checkAvailability() async throws {}
    func setHouseholdScope(_ scope: CloudKitManager.HouseholdDatabaseScope) {
        currentScope = scope
    }

    func getContainer() async -> CKContainer {
        CKContainer(identifier: "iCloud.com.example.familytodo")
    }

    func ensureHouseholdOwnerZone(householdId _: UUID) async throws -> CKRecordZone.ID {
        CKRecordZone.default().zoneID
    }

    func migrateHouseholdToCustomZoneIfNeeded(householdId _: UUID) async throws {}
    func repairSharedHouseholdGraphIfNeeded(householdId _: UUID) async throws {}
    func migrateMemberColorsIfNeeded(householdId _: UUID) async {}

    func saveHousehold(
        _ household: Household,
        scope _: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord {
        householdsById[household.id] = household
        return makeRecord(recordType: "Household", id: household.id)
    }

    func fetchHousehold(
        id: UUID,
        scope _: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> Household {
        guard let household = householdsById[id] else {
            throw CKError(.unknownItem)
        }
        return household
    }

    func deleteHousehold(
        id: UUID,
        scope _: CloudKitManager.HouseholdDatabaseScope?
    ) async throws {
        householdsById.removeValue(forKey: id)
    }

    func updateHouseholdMetadata(
        householdId: UUID,
        newName: String,
        newIconSymbol: String,
        scope _: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord {
        guard var household = householdsById[householdId] else {
            throw CKError(.unknownItem)
        }
        household.name = newName
        household.iconSymbol = newIconSymbol
        household.updatedAt = Date()
        householdsById[householdId] = household
        return makeRecord(recordType: "Household", id: householdId)
    }

    func createShare(for _: Household) async throws -> CKShare {
        throw HouseholdJoinTestError.unimplemented
    }

    func fetchShare(for _: UUID) async throws -> CKShare? {
        nil
    }

    func getShareURL(for _: UUID) async throws -> URL? {
        nil
    }

    func createInviteCode(for household: Household) async throws -> InviteToken {
        let token = InviteToken(
            id: "A7B9XQ2M",
            code: "A7B9XQ2M",
            householdId: household.id,
            shareURL: "https://www.icloud.com/share/test",
            createdAt: Date(timeIntervalSince1970: 0),
            expiresAt: Date(timeIntervalSince1970: InviteToken.ttl),
            isRevoked: false,
            usesCount: 0
        )
        inviteTokensByCode[token.code] = token
        return token
    }

    func fetchInviteToken(code rawCode: String) async throws -> InviteToken {
        guard let token = inviteTokensByCode[rawCode] else {
            throw HouseholdJoinTestError.missingInviteToken(rawCode)
        }
        return token
    }

    func deleteInviteTokens(for householdId: UUID) async throws {
        inviteTokensByCode = inviteTokensByCode.filter { $0.value.householdId != householdId }
    }

    func redeemInviteCode(_ rawCode: String) async throws -> Household {
        if let household = inviteRedeemResults[rawCode] {
            return household
        }
        guard let token = inviteTokensByCode[rawCode],
              let household = householdsById[token.householdId]
        else {
            throw HouseholdJoinTestError.missingInviteToken(rawCode)
        }
        return household
    }

    func acceptShare(inviteCode rawCode: String) async throws -> Household {
        let context = try await resolveAcceptedShareContext(fromInviteCode: rawCode)
        return context.household
    }

    func acceptShare(metadata _: CKShare.Metadata) async throws -> Household {
        throw HouseholdJoinTestError.unimplemented
    }

    func resolveAcceptedShareContext(fromInviteCode rawCode: String) async throws -> AcceptedShareContext {
        let household: Household
        let shareURL: URL?

        if let householdFromRedeem = inviteRedeemResults[rawCode] {
            household = householdFromRedeem
            shareURL = URL(string: inviteTokensByCode[rawCode]?.shareURL ?? "https://www.icloud.com/share/test")
        } else if let token = inviteTokensByCode[rawCode],
                  let tokenHousehold = householdsById[token.householdId]
        {
            household = tokenHousehold
            shareURL = URL(string: token.shareURL)
        } else {
            throw HouseholdJoinTestError.missingInviteToken(rawCode)
        }

        acceptedSharedHouseholdIDs.insert(household.id)
        let zoneID = CKRecordZone.ID(
            zoneName: "shared-\(household.id.uuidString)",
            ownerName: "owner"
        )
        return AcceptedShareContext(
            household: household,
            householdId: household.id,
            zoneID: zoneID,
            shareURL: shareURL
        )
    }

    func resolveAcceptedShareContext(metadata _: CKShare.Metadata) async throws -> AcceptedShareContext {
        throw HouseholdJoinTestError.unimplemented
    }

    func saveMember(
        _ member: Member,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        appendOperation("saveMember", scope: scope, householdId: member.householdId)
        if scope == .participantShared {
            try ensureParticipantSharedAccess(
                householdId: member.householdId,
                operation: "saveMember",
                forWrite: true
            )
        }
        var members = members(for: scope)
        if let index = members.firstIndex(where: { $0.id == member.id }) {
            members[index] = member
        } else {
            members.append(member)
        }
        setMembers(members, for: scope)
        if scope == .participantShared {
            mirrorParticipantMemberIntoOwnerScope(member)
        }
        return makeRecord(recordType: "Member", id: member.id)
    }

    func fetchMemberByUserId(
        _ userId: String,
        householdId: UUID?,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> Member? {
        let scope = resolvedScope(explicitScope)
        appendOperation(
            "fetchMemberByUserId",
            scope: scope,
            householdId: householdId
        )
        if scope == .participantShared {
            try ensureParticipantSharedAccess(
                householdId: householdId,
                operation: "fetchMemberByUserId",
                forWrite: false
            )
        }
        return try await fetchActiveMembersByUserId(
            userId,
            householdId: householdId,
            scope: explicitScope
        ).first
    }

    func fetchActiveMembersByUserId(
        _ userId: String,
        householdId: UUID?,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [Member] {
        let scope = resolvedScope(explicitScope)
        appendOperation("fetchActiveMembersByUserId", scope: scope, householdId: householdId)
        if scope == .participantShared {
            try ensureParticipantSharedAccess(
                householdId: householdId,
                operation: "fetchActiveMembersByUserId",
                forWrite: false
            )
        }
        return members(for: scope)
            .filter { member in
                member.userId == userId &&
                    member.isActive &&
                    (householdId == nil || member.householdId == householdId)
            }
            .sorted { $0.joinedAt > $1.joinedAt }
    }

    func fetchMembers(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [Member] {
        let scope = resolvedScope(explicitScope)
        appendOperation("fetchMembers", scope: scope, householdId: householdId)
        if scope == .participantShared {
            try ensureParticipantSharedAccess(
                householdId: householdId,
                operation: "fetchMembers",
                forWrite: false
            )
        }
        return members(for: scope)
            .filter { $0.householdId == householdId }
            .sorted { $0.joinedAt < $1.joinedAt }
    }

    func updateMemberState(
        memberId: UUID,
        householdId: UUID,
        newDisplayName: String,
        newRole: Member.MemberRole,
        isActive: Bool,
        colorHex: String,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        appendOperation("updateMemberState", scope: scope, householdId: householdId)
        if scope == .participantShared {
            try ensureParticipantSharedAccess(
                householdId: householdId,
                operation: "updateMemberState",
                forWrite: true
            )
        }
        var members = members(for: scope)
        guard let index = members.firstIndex(where: { $0.id == memberId }) else {
            throw CKError(.unknownItem)
        }

        let existing = members[index]
        members[index] = Member(
            id: existing.id,
            householdId: householdId,
            userId: existing.userId,
            displayName: newDisplayName,
            role: newRole,
            joinedAt: existing.joinedAt,
            isActive: isActive,
            colorHex: colorHex
        )
        setMembers(members, for: scope)
        if scope == .participantShared {
            mirrorParticipantMemberIntoOwnerScope(members[index])
        }
        memberStateUpdates.append(
            MemberStateUpdate(memberId: memberId, householdId: householdId, isActive: isActive)
        )
        return makeRecord(recordType: "Member", id: memberId)
    }

    func deleteMember(
        id: UUID,
        householdId _: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws {
        let scope = resolvedScope(explicitScope)
        setMembers(members(for: scope).filter { $0.id != id }, for: scope)
    }

    func leaveSharedHousehold(householdId: UUID) async throws {
        leftSharedHouseholds.append(householdId)
    }

    func deleteHouseholdZoneIfCustom(id _: UUID) async throws -> Bool {
        false
    }

    func clearAllCachedZones(for _: UUID) {}

    func fetchTasks(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [Task] {
        let scope = resolvedScope(explicitScope)
        appendOperation("fetchTasks", scope: scope, householdId: householdId)
        if scope == .participantShared {
            try ensureParticipantSharedAccess(
                householdId: householdId,
                operation: "fetchTasks",
                forWrite: false
            )
        }
        return tasks
            .filter { $0.householdId == householdId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func deleteTask(
        id _: UUID,
        householdId _: UUID,
        scope _: CloudKitManager.HouseholdDatabaseScope?
    ) async throws {}

    func fetchShoppingItems(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [ShoppingItem] {
        let scope = resolvedScope(explicitScope)
        appendOperation("fetchShoppingItems", scope: scope, householdId: householdId)
        if scope == .participantShared {
            try ensureParticipantSharedAccess(
                householdId: householdId,
                operation: "fetchShoppingItems",
                forWrite: false
            )
        }
        return shoppingItems
            .filter { $0.householdId == householdId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func deleteShoppingItem(
        id _: UUID,
        householdId _: UUID,
        scope _: CloudKitManager.HouseholdDatabaseScope?
    ) async throws {}

    func fetchShoppingBundles(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [ShoppingBundle] {
        let scope = resolvedScope(explicitScope)
        appendOperation("fetchShoppingBundles", scope: scope, householdId: householdId)
        if scope == .participantShared {
            try ensureParticipantSharedAccess(
                householdId: householdId,
                operation: "fetchShoppingBundles",
                forWrite: false
            )
        }
        return shoppingBundles
            .filter { $0.householdId == householdId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func deleteShoppingBundle(
        id _: UUID,
        householdId _: UUID,
        scope _: CloudKitManager.HouseholdDatabaseScope?
    ) async throws {}

    func fetchBacklogItems(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [BacklogItem] {
        let scope = resolvedScope(explicitScope)
        appendOperation("fetchBacklogItems", scope: scope, householdId: householdId)
        if scope == .participantShared {
            try ensureParticipantSharedAccess(
                householdId: householdId,
                operation: "fetchBacklogItems",
                forWrite: false
            )
        }
        return backlogItems
            .filter { $0.householdId == householdId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func deleteBacklogItem(
        id _: UUID,
        householdId _: UUID,
        scope _: CloudKitManager.HouseholdDatabaseScope?
    ) async throws {}

    func fetchBacklogCategories(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [BacklogCategory] {
        let scope = resolvedScope(explicitScope)
        appendOperation("fetchBacklogCategories", scope: scope, householdId: householdId)
        if scope == .participantShared {
            try ensureParticipantSharedAccess(
                householdId: householdId,
                operation: "fetchBacklogCategories",
                forWrite: false
            )
        }
        return backlogCategories
            .filter { $0.householdId == householdId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func deleteBacklogCategory(
        id _: UUID,
        householdId _: UUID,
        scope _: CloudKitManager.HouseholdDatabaseScope?
    ) async throws {}

    func fetchAreas(householdId _: UUID) async throws -> [Area] {
        []
    }

    func deleteArea(id _: UUID, householdId _: UUID) async throws {}

    func fetchRecurringChores(householdId _: UUID) async throws -> [RecurringChore] {
        []
    }

    func deleteRecurringChore(id _: UUID, householdId _: UUID) async throws {}

    func inactiveUpdateCount(for householdId: UUID) async -> Int {
        memberStateUpdates.filter { $0.householdId == householdId && !$0.isActive }.count
    }

    func leftSharedHouseholdsSnapshot() async -> [UUID] {
        leftSharedHouseholds
    }

    func operationEventsSnapshot() async -> [OperationEvent] {
        operationEvents
    }

    func hasAcceptedSharedHousehold(_ householdId: UUID) async -> Bool {
        acceptedSharedHouseholdIDs.contains(householdId)
    }
}

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
}
