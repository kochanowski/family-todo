import CloudKit
@testable import HousePulse

private enum HouseholdJoinTestError: Error {
    case unimplemented
    case missingInviteToken(String)
}

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

    func createHouseholdWithMember(
        _ household: Household,
        member: Member
    ) async throws -> (householdRecord: CKRecord, memberRecord: CKRecord) {
        householdsById[household.id] = household
        var members = members(for: .ownerPrivate)
        if let index = members.firstIndex(where: { $0.id == member.id }) {
            members[index] = member
        } else {
            members.append(member)
        }
        setMembers(members, for: .ownerPrivate)
        return (
            makeRecord(recordType: "Household", id: household.id),
            makeRecord(recordType: "Member", id: member.id)
        )
    }

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
