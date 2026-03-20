import CloudKit
import Combine
import SwiftData
import SwiftUI
import UIKit

struct AcceptedShareContext {
    let household: Household
    let householdId: UUID
    let zoneID: CKRecordZone.ID
    let shareURL: URL?
}

protocol HouseholdCloudSyncing: Actor {
    func ensureReady() async
    func checkAvailability() async throws
    func setHouseholdScope(_ scope: CloudKitManager.HouseholdDatabaseScope)
    func getContainer() async -> CKContainer

    func ensureHouseholdOwnerZone(householdId: UUID) async throws -> CKRecordZone.ID
    func migrateHouseholdToCustomZoneIfNeeded(householdId: UUID) async throws
    func repairSharedHouseholdGraphIfNeeded(householdId: UUID) async throws
    func migrateMemberColorsIfNeeded(householdId: UUID) async

    func saveHousehold(
        _ household: Household,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord
    func fetchHousehold(
        id: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> Household
    func deleteHousehold(
        id: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws
    func updateHouseholdMetadata(
        householdId: UUID,
        newName: String,
        newIconSymbol: String,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord

    func createShare(for household: Household) async throws -> CKShare
    func fetchShare(for householdId: UUID) async throws -> CKShare?
    func getShareURL(for householdId: UUID) async throws -> URL?

    func createInviteCode(for household: Household) async throws -> InviteToken
    func fetchInviteToken(code rawCode: String) async throws -> InviteToken
    func deleteInviteTokens(for householdId: UUID) async throws
    func redeemInviteCode(_ rawCode: String) async throws -> Household
    func acceptShare(inviteCode: String) async throws -> Household
    func acceptShare(metadata: CKShare.Metadata) async throws -> Household
    func resolveAcceptedShareContext(fromInviteCode rawCode: String) async throws -> AcceptedShareContext
    func resolveAcceptedShareContext(metadata: CKShare.Metadata) async throws -> AcceptedShareContext

    func saveMember(
        _ member: Member,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord
    func fetchMemberByUserId(
        _ userId: String,
        householdId: UUID?,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> Member?
    func fetchActiveMembersByUserId(
        _ userId: String,
        householdId: UUID?,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [Member]
    func fetchMembers(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [Member]
    func updateMemberState(
        memberId: UUID,
        householdId: UUID,
        newDisplayName: String,
        newRole: Member.MemberRole,
        isActive: Bool,
        colorHex: String,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord
    func deleteMember(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func leaveSharedHousehold(householdId: UUID) async throws
    func deleteHouseholdZoneIfCustom(id householdId: UUID) async throws -> Bool
    func clearAllCachedZones(for householdId: UUID)

    func fetchTasks(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [Task]
    func deleteTask(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func fetchShoppingItems(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [ShoppingItem]
    func deleteShoppingItem(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func fetchShoppingBundles(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [ShoppingBundle]
    func deleteShoppingBundle(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func fetchBacklogItems(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [BacklogItem]
    func deleteBacklogItem(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func fetchBacklogCategories(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [BacklogCategory]
    func deleteBacklogCategory(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func fetchAreas(householdId: UUID) async throws -> [Area]
    func deleteArea(id: UUID, householdId: UUID) async throws

    func fetchRecurringChores(householdId: UUID) async throws -> [RecurringChore]
    func deleteRecurringChore(id: UUID, householdId: UUID) async throws
}

extension CloudKitManager: HouseholdCloudSyncing {
    func repairSharedHouseholdGraphIfNeeded(householdId: UUID) async throws {
        try await repairSharedHouseholdGraphIfNeeded(householdId: householdId, force: false)
    }
}

@MainActor
// swiftlint:disable type_body_length file_length
class HouseholdStore: ObservableObject {
    private enum DefaultsKey {
        static let suppressedHouseholdRecoveries = "suppressedHouseholdRecoveries"
        static let pendingExitOperations = "pendingHouseholdExitOperations"
    }

    static let pendingExitOperationsDefaultsKey = DefaultsKey.pendingExitOperations

    enum PendingExitOperationKind: String, Codable, Equatable {
        case leaveSharedHousehold
        case deleteOwnedHousehold
    }

    struct PendingExitOperation: Codable, Equatable {
        let kind: PendingExitOperationKind
        let householdId: UUID
        let userId: String?
    }

    private struct PendingHouseholdMetadataSync {
        let household: Household
        let userId: String
    }

    private struct JoinTarget {
        let acceptedShareContext: AcceptedShareContext

        var householdId: UUID {
            acceptedShareContext.householdId
        }

        var household: Household {
            acceptedShareContext.household
        }

        var zoneID: CKRecordZone.ID {
            acceptedShareContext.zoneID
        }
    }

    private struct ScopedMembership {
        let member: Member
        let source: RecoverableMembershipSource
    }

    struct JoinHydrationConfiguration {
        let initialHydrationBudgetNanoseconds: UInt64
        let initialRetryDelaysNanoseconds: [UInt64]
        let backgroundRetryDelaysNanoseconds: [UInt64]
        let pendingJoinGraceDuration: TimeInterval

        static let `default` = JoinHydrationConfiguration(
            initialHydrationBudgetNanoseconds: 5_000_000_000,
            initialRetryDelaysNanoseconds: [
                0,
                900_000_000,
                1_350_000_000,
                1_850_000_000,
            ],
            backgroundRetryDelaysNanoseconds: [
                1_000_000_000,
                2_000_000_000,
                4_000_000_000,
                8_000_000_000,
                15_000_000_000,
            ],
            pendingJoinGraceDuration: 30
        )
    }

    private struct PendingJoinState {
        let householdId: UUID
        let userId: String
        let startedAt: Date
        var expiresAt: Date
        var hasConfirmedRemoteMembership = false
        var hasCompletedHydrationPass = false
        var hasPublishedVisibleContentNotifications = false
    }

    private struct JoinedHouseholdHydrationSnapshot: Equatable {
        let activeMemberCount: Int
        let currentUserHasCachedMembership: Bool
        let remoteMembershipConfirmed: Bool
        let taskCount: Int
        let ideaCount: Int
        let categoryCount: Int
        let shoppingItemCount: Int
        let bundleCount: Int

        var hasVisibleSharedContent: Bool {
            taskCount > 0 ||
                ideaCount > 0 ||
                categoryCount > 0 ||
                shoppingItemCount > 0 ||
                bundleCount > 0
        }
    }

    private struct RemoteCloudRefreshSnapshot: Equatable {
        let currentHouseholdId: UUID?
        let observedHouseholdId: UUID?
        let hydrationSnapshot: JoinedHouseholdHydrationSnapshot?
    }

    private enum JoinHydrationTimeoutError: Error {
        case timedOut
    }

    enum LeaveResolution: Equatable {
        case deleteHousehold
        case requireTransfer
        case deactivateMembership
    }

    enum SetupResolutionState: Equatable {
        case idle
        case loading(key: String)
        case resolved(key: String, householdCount: Int)

        func matches(key: String) -> Bool {
            switch self {
            case let .loading(storedKey):
                storedKey == key
            case let .resolved(storedKey, _):
                storedKey == key
            case .idle:
                false
            }
        }

        var resolvedHouseholdCount: Int? {
            switch self {
            case let .resolved(_, householdCount):
                householdCount
            case .idle, .loading:
                nil
            }
        }
    }

    enum RecoverableMembershipSource: String {
        case participantShared
        case ownerPrivate
    }

    @Published var currentHousehold: Household?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var share: CKShare?
    @Published var activeInviteCode: String?
    @Published private(set) var setupResolutionState: SetupResolutionState = .idle

    private var modelContext: ModelContext?
    private let cloudKit: any HouseholdCloudSyncing
    private var syncMode: SyncMode = .cloud
    private let userDefaults: UserDefaults
    private let recoverySuppressionDuration: TimeInterval
    private let joinHydrationConfiguration: JoinHydrationConfiguration
    private var isRefreshingCloudHousehold = false
    private var isReplayingPendingExitOperations = false
    private var pendingHouseholdMetadataSync: PendingHouseholdMetadataSync?
    private var isReplayingPendingHouseholdMetadataSync = false
    private let joinedHouseholdPrewarmOverride: ((Household, String, ModelContext?) async throws -> Void)?
    private var pendingJoinState: PendingJoinState?
    private var joinHydrationTask: _Concurrency.Task<Void, Never>?

    // Cache for sharing controller
    private var activeShare: CKShare?
    private(set) var activeContainer: CKContainer?

    init(
        modelContext: ModelContext? = nil,
        cloudKit: any HouseholdCloudSyncing = CloudKitManager.shared,
        joinedHouseholdPrewarmOverride: ((Household, String, ModelContext?) async throws -> Void)? = nil,
        userDefaults: UserDefaults = .standard,
        recoverySuppressionDuration: TimeInterval = 300,
        joinHydrationConfiguration: JoinHydrationConfiguration = .default
    ) {
        self.modelContext = modelContext
        self.cloudKit = cloudKit
        self.joinedHouseholdPrewarmOverride = joinedHouseholdPrewarmOverride
        self.userDefaults = userDefaults
        self.recoverySuppressionDuration = recoverySuppressionDuration
        self.joinHydrationConfiguration = joinHydrationConfiguration
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
    }

    var isModelContextReady: Bool {
        modelContext != nil
    }

    @discardableResult
    private func saveContextOrSetError(
        _ context: ModelContext? = nil,
        operation: String = "persist household cache",
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        StoreContextSaver.saveContextOrSetError(
            context ?? modelContext,
            store: "HouseholdStore",
            operation: operation,
            file: file,
            line: line
        ) { [self] saveError in
            error = saveError
        }
    }

    // MARK: - Lifecycle

    /// Preferred entry point for restoring session household context.
    /// It loads cached data first and refreshes membership from CloudKit when enabled.
    func loadCurrentHouseholdAndMembership(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) async {
        restoreCachedHousehold(userId: userId, preferredHouseholdId: preferredHouseholdId)
        await refreshCurrentHouseholdAndMembershipFromCloud(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )
    }

    /// Launch-safe local-first resolver for startup routing.
    /// It never touches CloudKit and only inspects in-memory/current cached household state.
    @discardableResult
    func resolveStartupHouseholdLocally(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) -> Household? {
        if let household = currentHousehold {
            guard !isRecoverySuppressed(for: household.id) else {
                clearCurrentHousehold()
                return nil
            }
            return household
        }

        return restoreCachedHousehold(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )
    }

    @discardableResult
    func restoreCachedHousehold(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) -> Household? {
        guard let cached = fetchCachedHousehold(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        ) else {
            return nil
        }

        let restoredHousehold = cached.toHousehold()
        guard isValidCachedMembershipForRecoveredHousehold(
            householdId: restoredHousehold.id,
            userId: userId
        ) else {
            print(
                "DEBUG: Ignoring cached household \(restoredHousehold.id) because the current user has no cached membership."
            )
            removeHouseholdFromCache(id: restoredHousehold.id)
            currentHousehold = nil
            return nil
        }
        currentHousehold = restoredHousehold
        return restoredHousehold
    }

    func refreshCurrentHouseholdAndMembershipFromCloud(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) async {
        guard syncMode == .cloud else { return }
        guard !isRefreshingCloudHousehold else { return }

        isRefreshingCloudHousehold = true
        isLoading = true
        defer {
            isRefreshingCloudHousehold = false
            isLoading = false
        }

        do {
            await replayPendingExitOperationsIfNeeded()
            await cloudKit.ensureReady()
            try await cloudKit.checkAvailability()

            let localHousehold = currentHousehold
            var resolvedCloudHousehold: Household?

            if let current = localHousehold {
                do {
                    await setCloudScope(for: current, userId: userId)
                    let fresh = try await cloudKit.fetchHousehold(id: current.id, scope: nil)
                    if try await validateRecoveredMembershipOrAbandon(
                        household: fresh,
                        userId: userId
                    ) {
                        await cloudKit.migrateMemberColorsIfNeeded(householdId: fresh.id)
                        await refreshMemberCacheFromCloudIfNeeded(
                            household: fresh,
                            userId: userId
                        )
                        resolvedCloudHousehold = fresh
                    }
                } catch {
                    if shouldProtectPendingJoin(householdId: current.id, userId: userId) {
                        print(
                            "DEBUG: Preserving pending-join household \(current.id) despite refresh error: \(error)"
                        )
                        scheduleBackgroundJoinHydrationIfNeeded(
                            household: current,
                            userId: userId
                        )
                        resolvedCloudHousehold = current
                    }
                    print("DEBUG: Cached household refresh failed, retrying membership lookup: \(error)")
                }
            }

            if resolvedCloudHousehold == nil {
                print("DEBUG: Checking CloudKit for existing household membership...")
                resolvedCloudHousehold = try await resolveRecoverableCloudHousehold(
                    userId: userId,
                    preferredHouseholdId: preferredHouseholdId
                )
            }

            if let resolvedCloudHousehold {
                print("DEBUG: Found recoverable household in cloud: \(resolvedCloudHousehold.id)")
                await setCloudScope(for: resolvedCloudHousehold, userId: userId)
                if resolvedCloudHousehold.ownerId == userId {
                    try? await cloudKit.repairSharedHouseholdGraphIfNeeded(
                        householdId: resolvedCloudHousehold.id
                    )
                }
                await cloudKit.migrateMemberColorsIfNeeded(householdId: resolvedCloudHousehold.id)
                await refreshMemberCacheFromCloudIfNeeded(
                    household: resolvedCloudHousehold,
                    userId: userId
                )
                updateCache(with: resolvedCloudHousehold)
                currentHousehold = resolvedCloudHousehold
            } else {
                if let localHousehold,
                   shouldProtectPendingJoin(householdId: localHousehold.id, userId: userId)
                {
                    currentHousehold = localHousehold
                    scheduleBackgroundJoinHydrationIfNeeded(
                        household: localHousehold,
                        userId: userId
                    )
                    return
                }
                print("DEBUG: No existing membership found in cloud.")
            }
        } catch {
            print("Error loading household: \(error)")
            if currentHousehold == nil {
                self.error = error
            }
        }
    }

    func createHousehold(
        name: String,
        userId: String,
        displayName: String,
        iconSymbol: String = "house.fill"
    ) async throws -> Household {
        // CloudKit safety check
        precondition(
            syncMode == .localOnly || syncMode == .cloud,
            "Invalid sync mode for household creation"
        )

        try ensureUserCanStartSingleHouseholdLocally(userId: userId)
        if syncMode == .cloud, !shouldSkipRemoteSingleHouseholdDiscoveryForCreate {
            try await ensureUserCanStartSingleHouseholdRemotely(userId: userId)
        }

        isLoading = true
        defer { isLoading = false }

        let validatedDisplayName = try requiredMembershipDisplayName(from: displayName)
        let trimmedHouseholdName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHouseholdName.isEmpty else {
            throw HouseholdError.invalidInviteCode
        }
        if syncMode == .localOnly, modelContext == nil {
            throw HouseholdError.cacheNotAvailable
        }

        let newHousehold = Household(
            name: trimmedHouseholdName,
            iconSymbol: iconSymbol,
            ownerId: userId
        )

        let ownerMember = Member(
            householdId: newHousehold.id,
            userId: userId,
            displayName: validatedDisplayName,
            role: .owner,
            colorHex: MemberColorToken.randomHex()
        )

        // 1. Save to CloudKit (if cloud sync is enabled and available)
        if syncMode == .cloud {
            // Check CloudKit availability first
            try await cloudKit.checkAvailability()
            await cloudKit.setHouseholdScope(.ownerPrivate)
            _ = try await cloudKit.ensureHouseholdOwnerZone(householdId: newHousehold.id)

            _ = try await cloudKit.saveHousehold(newHousehold, scope: nil)
            _ = try await cloudKit.saveMember(ownerMember, scope: nil)
            updateCache(with: ownerMember)
            updateCache(with: newHousehold)
            currentHousehold = newHousehold
            runCreateHouseholdPostflight(household: newHousehold, userId: userId)
            return newHousehold
        }

        // 2. Cache the local owner membership for immediate UI availability.
        if syncMode == .localOnly {
            updateCache(with: ownerMember)
        }

        // 3. Update Cache
        updateCache(with: newHousehold)
        currentHousehold = newHousehold

        return newHousehold
    }

    // MARK: - Sharing

    func createShare() async throws -> (CKShare, CKContainer) {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }

        // Check availability and get container from CloudKitManager
        try await cloudKit.checkAvailability()
        await cloudKit.setHouseholdScope(.ownerPrivate)
        _ = try await cloudKit.ensureHouseholdOwnerZone(householdId: household.id)
        try await cloudKit.migrateHouseholdToCustomZoneIfNeeded(householdId: household.id)
        try await cloudKit.repairSharedHouseholdGraphIfNeeded(householdId: household.id)
        let container = await cloudKit.getContainer()

        let share = try await cloudKit.createShare(for: household)
        self.share = share
        activeContainer = container
        return (share, container)
    }

    func fetchInviteURL() async throws -> URL {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }

        try await cloudKit.checkAvailability()
        await cloudKit.setHouseholdScope(.ownerPrivate)
        try await cloudKit.migrateHouseholdToCustomZoneIfNeeded(householdId: household.id)
        try await cloudKit.repairSharedHouseholdGraphIfNeeded(householdId: household.id)

        if let existingURL = share?.url {
            return existingURL
        }

        do {
            let (createdShare, container) = try await createShare()
            share = createdShare
            activeContainer = container
            if let createdURL = createdShare.url {
                return createdURL
            }
        } catch CloudKitManager.CloudKitManagerError.shareNotCreated {
            // Fallbacks below.
        }

        if let fallbackShare = try await cloudKit.fetchShare(for: household.id) {
            share = fallbackShare
            activeContainer = await cloudKit.getContainer()
            if let shareURL = fallbackShare.url {
                return shareURL
            }
        }

        if let shareURL = try await cloudKit.getShareURL(for: household.id) {
            return shareURL
        }

        throw CloudKitManager.CloudKitManagerError.shareNotCreated
    }

    func fetchOrCreateInviteCode() async throws -> String {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }
        guard syncMode == .cloud else {
            throw HouseholdError.cloudSyncRequired
        }

        await cloudKit.setHouseholdScope(.ownerPrivate)
        try await cloudKit.repairSharedHouseholdGraphIfNeeded(householdId: household.id)

        if let activeInviteCode {
            do {
                let token = try await cloudKit.fetchInviteToken(code: activeInviteCode)
                if token.householdId == household.id, token.isActive() {
                    self.activeInviteCode = token.code
                    return token.code
                }
            } catch {
                // Token may no longer exist or be inactive - fall through and recreate.
            }
        }

        let token = try await cloudKit.createInviteCode(for: household)
        activeInviteCode = token.code
        return token.code
    }

    // MARK: - Join Household

    func joinHousehold(inviteCode: String, userId: String, displayName: String) async throws {
        try await joinHousehold(
            withInviteInput: inviteCode,
            userId: userId,
            displayName: displayName
        )
    }

    func joinHousehold(withInviteInput input: String, userId: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard syncMode == .cloud else {
            throw HouseholdError.cloudSyncRequired
        }

        let validatedDisplayName = try requiredMembershipDisplayName(from: displayName)

        try await cloudKit.checkAvailability()
        let normalizedInvite = try InviteInputNormalizer.normalizeInput(input)
        let target = try await resolveJoinTarget(for: normalizedInvite)
        try await clearConflictingJoinStateBeforeTargetedJoin(
            targetHouseholdId: target.householdId,
            userId: userId
        )
        await cloudKit.setHouseholdScope(.participantShared)
        await cloudKit.migrateMemberColorsIfNeeded(householdId: target.householdId)

        print("DEBUG: Join member upsert starting for household \(target.householdId) in participantShared scope.")
        _ = try await upsertMembership(
            householdId: target.householdId,
            userId: userId,
            displayName: validatedDisplayName,
            role: target.household.ownerId == userId ? .owner : .member,
            scope: .participantShared
        )
        print("DEBUG: Join member verification starting for household \(target.householdId) in participantShared scope.")
        let verifiedMember = try await verifyParticipantSharedMembership(
            householdId: target.householdId,
            userId: userId
        )

        updateCache(with: verifiedMember)
        updateCache(with: target.household)
        currentHousehold = target.household
        beginPendingJoinProtection(
            householdId: target.household.id,
            userId: userId
        )
        await prewarmJoinedHouseholdGraphIfNeeded(household: target.household, userId: userId)
    }

    func joinHousehold(metadata: CKShare.Metadata, userId: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard syncMode == .cloud else {
            throw HouseholdError.cloudSyncRequired
        }

        let validatedDisplayName = try requiredMembershipDisplayName(from: displayName)

        try await cloudKit.checkAvailability()
        let target = try await resolveJoinTarget(for: metadata)
        try await clearConflictingJoinStateBeforeTargetedJoin(
            targetHouseholdId: target.householdId,
            userId: userId
        )
        await cloudKit.setHouseholdScope(.participantShared)
        await cloudKit.migrateMemberColorsIfNeeded(householdId: target.householdId)

        print("DEBUG: Join member upsert starting for household \(target.householdId) in participantShared scope.")
        _ = try await upsertMembership(
            householdId: target.householdId,
            userId: userId,
            displayName: validatedDisplayName,
            role: target.household.ownerId == userId ? .owner : .member,
            scope: .participantShared
        )
        print("DEBUG: Join member verification starting for household \(target.householdId) in participantShared scope.")
        let verifiedMember = try await verifyParticipantSharedMembership(
            householdId: target.householdId,
            userId: userId
        )

        updateCache(with: verifiedMember)
        updateCache(with: target.household)
        currentHousehold = target.household
        beginPendingJoinProtection(
            householdId: target.household.id,
            userId: userId
        )
        await prewarmJoinedHouseholdGraphIfNeeded(household: target.household, userId: userId)
    }

    // MARK: - Household Management

    func renameCurrentHousehold(_ name: String) async throws {
        guard let currentHousehold else {
            throw HouseholdError.householdNotFound
        }
        try await updateCurrentHousehold(
            name: name,
            userId: currentHousehold.ownerId
        )
    }

    func updateCurrentHousehold(
        name: String,
        userId: String,
        iconSymbol: String? = nil
    ) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }
        guard household.ownerId == userId else {
            throw HouseholdError.notAuthorized
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw HouseholdError.invalidInviteCode
        }

        let resolvedIconSymbol = iconSymbol ?? household.iconSymbol
        guard trimmedName != household.name || resolvedIconSymbol != household.iconSymbol else {
            return
        }

        error = nil

        let previousHousehold = household
        var updatedHousehold = household
        updatedHousehold.name = trimmedName
        updatedHousehold.iconSymbol = resolvedIconSymbol
        updatedHousehold.updatedAt = Date()

        currentHousehold = updatedHousehold
        guard updateCache(with: updatedHousehold) else {
            currentHousehold = previousHousehold
            _ = updateCache(with: previousHousehold)
            throw error ?? HouseholdError.cacheNotAvailable
        }

        guard syncMode == .cloud else {
            return
        }

        queueHouseholdMetadataSync(updatedHousehold, userId: userId)
    }

    private func queueHouseholdMetadataSync(_ household: Household, userId: String) {
        guard syncMode == .cloud else { return }
        pendingHouseholdMetadataSync = PendingHouseholdMetadataSync(
            household: household,
            userId: userId
        )
        replayPendingHouseholdMetadataSyncInBackground()
    }

    private func replayPendingHouseholdMetadataSyncInBackground() {
        guard syncMode == .cloud else {
            pendingHouseholdMetadataSync = nil
            return
        }
        guard !isReplayingPendingHouseholdMetadataSync else { return }

        isReplayingPendingHouseholdMetadataSync = true
        _ = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isReplayingPendingHouseholdMetadataSync = false }

            while let pendingSync = pendingHouseholdMetadataSync {
                pendingHouseholdMetadataSync = nil

                do {
                    await setCloudScope(for: pendingSync.household, userId: pendingSync.userId)
                    _ = try await cloudKit.updateHouseholdMetadata(
                        householdId: pendingSync.household.id,
                        newName: pendingSync.household.name,
                        newIconSymbol: pendingSync.household.iconSymbol,
                        scope: nil
                    )
                } catch {
                    self.error = error
                }
            }
        }
    }

    func resolveMembershipDisplayName(userId: String) async -> String? {
        guard syncMode == .cloud else { return nil }

        if let household = currentHousehold {
            await setCloudScope(for: household, userId: userId)
            if let member = try? await cloudKit.fetchMemberByUserId(
                userId,
                householdId: household.id,
                scope: nil
            ),
                member.isActive
            {
                return member.displayName
            }
        }

        await cloudKit.setHouseholdScope(.participantShared)
        if let member = try? await cloudKit.fetchMemberByUserId(userId, householdId: nil, scope: nil),
           member.isActive
        {
            return member.displayName
        }

        await cloudKit.setHouseholdScope(.ownerPrivate)
        if let member = try? await cloudKit.fetchMemberByUserId(userId, householdId: nil, scope: nil),
           member.isActive
        {
            return member.displayName
        }

        return nil
    }

    func leaveCurrentHousehold(
        userId: String,
        activeMembersSnapshot: [Member]? = nil
    ) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }

        switch try resolveLocalLeaveBehavior(
            for: household,
            userId: userId,
            activeMembersSnapshot: activeMembersSnapshot
        ) {
        case .deleteHousehold:
            try await deleteCurrentHousehold(requestedBy: userId)
            return
        case .requireTransfer:
            throw HouseholdError.transferOwnershipRequired
        case .deactivateMembership:
            break
        }

        let pendingOperation: PendingExitOperation? = if syncMode == .cloud {
            PendingExitOperation(
                kind: .leaveSharedHousehold,
                householdId: household.id,
                userId: userId
            )
        } else {
            nil
        }

        if let pendingOperation {
            enqueuePendingExitOperation(pendingOperation)
        }

        performLocalHouseholdExit(householdId: household.id)

        if pendingOperation != nil {
            replayPendingExitOperationsInBackground()
        }
    }

    func deleteCurrentHousehold(requestedBy userId: String) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }

        guard household.ownerId == userId else {
            throw HouseholdError.notAuthorized
        }

        let pendingOperation: PendingExitOperation? = if syncMode == .cloud {
            PendingExitOperation(
                kind: .deleteOwnedHousehold,
                householdId: household.id,
                userId: userId
            )
        } else {
            nil
        }

        if let pendingOperation {
            enqueuePendingExitOperation(pendingOperation)
        }

        performLocalHouseholdExit(householdId: household.id)

        if pendingOperation != nil {
            replayPendingExitOperationsInBackground()
        }
    }

    /// Removes the current household from CloudKit as part of a hard reset.
    /// Owner → deletes the entire household. Participant → deactivates membership and leaves.
    /// Errors are swallowed; local reset proceeds regardless of network state.
    func hardResetCloudHousehold(userId: String) async {
        guard syncMode == .cloud, let household = currentHousehold else { return }

        do {
            await cloudKit.ensureReady()
            try await cloudKit.checkAvailability()

            if household.ownerId == userId {
                try await deleteRemoteOwnedHousehold(householdId: household.id)
            } else {
                try await leaveSharedHouseholdRemotely(
                    householdId: household.id,
                    userId: userId
                )
            }
        } catch {
            print("[HouseholdStore] Hard reset cloud cleanup non-fatal: \(error)")
        }
    }

    private func setCloudScope(for household: Household, userId: String) async {
        let scope: CloudKitManager.HouseholdDatabaseScope =
            household.ownerId == userId ? .ownerPrivate : .participantShared
        await cloudKit.setHouseholdScope(scope)
    }

    private func resolveLocalLeaveBehavior(
        for household: Household,
        userId: String,
        activeMembersSnapshot: [Member]?
    ) throws -> LeaveResolution {
        let activeMembers = resolvedActiveMembersForExit(
            householdId: household.id,
            activeMembersSnapshot: activeMembersSnapshot
        )

        guard let member = activeMembers.first(where: { $0.userId == userId }) else {
            if syncMode == .localOnly, household.ownerId == userId {
                return .deleteHousehold
            }
            throw HouseholdError.memberNotFound
        }

        return resolveLeaveBehavior(for: member, activeMembers: activeMembers)
    }

    private func performLocalHouseholdExit(householdId: UUID) {
        suppressRecovery(for: householdId)
        removeHouseholdFromCache(id: householdId)
        clearCurrentHousehold()
        _ = _Concurrency.Task { [cloudKit] in
            await cloudKit.clearAllCachedZones(for: householdId)
        }
    }

    private func replayPendingExitOperationsInBackground() {
        guard syncMode == .cloud else { return }
        _ = _Concurrency.Task { [self] in
            await replayPendingExitOperationsIfNeeded()
        }
    }

    private func replayPendingExitOperationsIfNeeded() async {
        guard syncMode == .cloud else { return }
        guard !isReplayingPendingExitOperations else { return }

        let operations = loadPendingExitOperations()
        guard !operations.isEmpty else { return }

        isReplayingPendingExitOperations = true
        defer { isReplayingPendingExitOperations = false }

        do {
            await cloudKit.ensureReady()
            try await cloudKit.checkAvailability()
        } catch {
            print("DEBUG: Pending household exit replay deferred: \(error)")
            return
        }

        for operation in operations {
            do {
                try await performRemoteExitOperation(operation)
                removePendingExitOperation(operation)
            } catch {
                print("DEBUG: Pending household exit replay failed for \(operation.householdId): \(error)")
            }
        }
    }

    private func performRemoteExitOperation(_ operation: PendingExitOperation) async throws {
        switch operation.kind {
        case .leaveSharedHousehold:
            guard let userId = operation.userId else {
                throw HouseholdError.memberNotFound
            }
            try await leaveSharedHouseholdRemotely(
                householdId: operation.householdId,
                userId: userId
            )
        case .deleteOwnedHousehold:
            try await deleteRemoteOwnedHousehold(householdId: operation.householdId)
        }
    }

    private func leaveSharedHouseholdRemotely(
        householdId: UUID,
        userId: String
    ) async throws {
        await cloudKit.setHouseholdScope(.participantShared)

        if let member = try? await cloudKit.fetchMemberByUserId(
            userId,
            householdId: householdId,
            scope: nil
        ),
            member.householdId == householdId
        {
            do {
                _ = try await cloudKit.updateMemberState(
                    memberId: member.id,
                    householdId: member.householdId,
                    newDisplayName: member.displayName,
                    newRole: member.role,
                    isActive: false,
                    colorHex: member.colorHex,
                    scope: nil
                )
            } catch {
                print("DEBUG: Member deactivation during leave failed: \(error)")
            }
        }

        try await cloudKit.leaveSharedHousehold(householdId: householdId)
        await cloudKit.clearAllCachedZones(for: householdId)
    }

    // swiftlint:disable cyclomatic_complexity
    private func deleteRemoteOwnedHousehold(householdId: UUID) async throws {
        await cloudKit.setHouseholdScope(.ownerPrivate)
        let deletedByZone = try await cloudKit.deleteHouseholdZoneIfCustom(id: householdId)

        if !deletedByZone {
            let members = try await cloudKit.fetchMembers(householdId: householdId, scope: nil)
            for member in members {
                try await cloudKit.deleteMember(id: member.id, householdId: householdId, scope: nil)
            }

            let tasks = try await cloudKit.fetchTasks(householdId: householdId, scope: nil)
            for task in tasks {
                try await cloudKit.deleteTask(id: task.id, householdId: householdId, scope: nil)
            }

            let shoppingItems = try await cloudKit.fetchShoppingItems(householdId: householdId, scope: nil)
            for item in shoppingItems {
                try await cloudKit.deleteShoppingItem(id: item.id, householdId: householdId, scope: nil)
            }

            let shoppingBundles = try await cloudKit.fetchShoppingBundles(householdId: householdId, scope: nil)
            for bundle in shoppingBundles {
                try await cloudKit.deleteShoppingBundle(id: bundle.id, householdId: householdId, scope: nil)
            }

            let backlogItems = try await cloudKit.fetchBacklogItems(householdId: householdId, scope: nil)
            for item in backlogItems {
                try await cloudKit.deleteBacklogItem(id: item.id, householdId: householdId, scope: nil)
            }

            let categories = try await cloudKit.fetchBacklogCategories(householdId: householdId, scope: nil)
            for category in categories {
                try await cloudKit.deleteBacklogCategory(id: category.id, householdId: householdId, scope: nil)
            }

            let areas = try await cloudKit.fetchAreas(householdId: householdId)
            for area in areas {
                try await cloudKit.deleteArea(id: area.id, householdId: householdId)
            }

            let recurringChores = try await cloudKit.fetchRecurringChores(householdId: householdId)
            for chore in recurringChores {
                try await cloudKit.deleteRecurringChore(id: chore.id, householdId: householdId)
            }

            try await cloudKit.deleteHousehold(id: householdId, scope: nil)
        }

        try await cloudKit.deleteInviteTokens(for: householdId)

        do {
            _ = try await cloudKit.fetchHousehold(id: householdId, scope: nil)
            throw NSError(
                domain: "HouseholdStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Household deletion could not be verified."]
            )
        } catch {
            guard isRecordMissingError(error) else { throw error }
        }

        await cloudKit.clearAllCachedZones(for: householdId)
    }

    // swiftlint:enable cyclomatic_complexity

    private func enqueuePendingExitOperation(_ operation: PendingExitOperation) {
        var operations = loadPendingExitOperations()
        if !operations.contains(operation) {
            operations.append(operation)
            savePendingExitOperations(operations)
        }
    }

    private func removePendingExitOperation(_ operation: PendingExitOperation) {
        let filtered = loadPendingExitOperations().filter { $0 != operation }
        savePendingExitOperations(filtered)
    }

    private func hasPendingExitOperation(for householdId: UUID) -> Bool {
        loadPendingExitOperations().contains(where: { $0.householdId == householdId })
    }

    private func loadPendingExitOperations() -> [PendingExitOperation] {
        guard let data = userDefaults.data(forKey: DefaultsKey.pendingExitOperations) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PendingExitOperation].self, from: data)
        } catch {
            print("DEBUG: Failed to decode pending household exit operations: \(error)")
            return []
        }
    }

    private func savePendingExitOperations(_ operations: [PendingExitOperation]) {
        if operations.isEmpty {
            userDefaults.removeObject(forKey: DefaultsKey.pendingExitOperations)
            return
        }

        do {
            let data = try JSONEncoder().encode(operations)
            userDefaults.set(data, forKey: DefaultsKey.pendingExitOperations)
        } catch {
            print("DEBUG: Failed to persist pending household exit operations: \(error)")
        }
    }

    private func resolveJoinTarget(for normalizedInvite: NormalizedInviteInput)
        async throws -> JoinTarget
    {
        let acceptedShareContext = try await cloudKit.resolveAcceptedShareContext(
            fromInviteCode: normalizedInvite.inviteCode
        )
        return JoinTarget(acceptedShareContext: acceptedShareContext)
    }

    private func resolveJoinTarget(for metadata: CKShare.Metadata) async throws -> JoinTarget {
        let acceptedShareContext = try await cloudKit.resolveAcceptedShareContext(metadata: metadata)
        guard UUID(uuidString: metadata.rootRecordID.recordName) == acceptedShareContext.household.id else {
            throw HouseholdError.invalidInviteCode
        }
        return JoinTarget(acceptedShareContext: acceptedShareContext)
    }

    private func clearConflictingJoinStateBeforeTargetedJoin(
        targetHouseholdId: UUID,
        userId: String
    ) async throws {
        let scopedMemberships = try await fetchScopedActiveMemberships(userId: userId)
        let conflictingMemberships = scopedMemberships.filter { $0.member.householdId != targetHouseholdId }

        for scopedMembership in conflictingMemberships {
            try await severMembershipAssociation(scopedMembership)
            removeHouseholdFromCache(id: scopedMembership.member.householdId)
            suppressRecovery(for: scopedMembership.member.householdId)
        }

        let staleCachedHouseholdIds = fetchRecoverableCachedHouseholds(
            userId: userId,
            preferredHouseholdId: nil
        )
        .map(\.id)
        .filter { $0 != targetHouseholdId }

        for householdId in staleCachedHouseholdIds {
            removeHouseholdFromCache(id: householdId)
            suppressRecovery(for: householdId)
        }

        if let currentHousehold, currentHousehold.id != targetHouseholdId {
            suppressRecovery(for: currentHousehold.id)
            clearCurrentHousehold()
        }
    }

    private func fetchScopedActiveMemberships(
        userId: String,
        householdId: UUID? = nil
    ) async throws -> [ScopedMembership] {
        await cloudKit.setHouseholdScope(.participantShared)
        let participantMembers = try await cloudKit.fetchActiveMembersByUserId(
            userId,
            householdId: householdId,
            scope: .participantShared
        )
        await cloudKit.setHouseholdScope(.ownerPrivate)
        let ownerMembers = try await cloudKit.fetchActiveMembersByUserId(
            userId,
            householdId: householdId,
            scope: .ownerPrivate
        )

        let participantScoped = participantMembers.map { ScopedMembership(member: $0, source: .participantShared) }
        let ownerScoped = ownerMembers.map { ScopedMembership(member: $0, source: .ownerPrivate) }
        return deduplicatedScopedMemberships(participantScoped + ownerScoped)
    }

    private func deduplicatedScopedMemberships(_ memberships: [ScopedMembership]) -> [ScopedMembership] {
        var byHouseholdId: [UUID: ScopedMembership] = [:]

        for membership in memberships {
            let householdId = membership.member.householdId
            guard let existing = byHouseholdId[householdId] else {
                byHouseholdId[householdId] = membership
                continue
            }

            if membership.member.joinedAt >= existing.member.joinedAt {
                byHouseholdId[householdId] = membership
            }
        }

        return byHouseholdId.values.sorted { lhs, rhs in
            lhs.member.joinedAt > rhs.member.joinedAt
        }
    }

    private func severMembershipAssociation(_ scopedMembership: ScopedMembership) async throws {
        let member = scopedMembership.member
        let scope: CloudKitManager.HouseholdDatabaseScope =
            scopedMembership.source == .ownerPrivate ? .ownerPrivate : .participantShared

        await cloudKit.setHouseholdScope(scope)
        _ = try await cloudKit.updateMemberState(
            memberId: member.id,
            householdId: member.householdId,
            newDisplayName: member.displayName,
            newRole: member.role,
            isActive: false,
            colorHex: member.colorHex,
            scope: scope
        )

        if scopedMembership.source == .participantShared {
            try await cloudKit.leaveSharedHousehold(householdId: member.householdId)
        }

        await cloudKit.clearAllCachedZones(for: member.householdId)
    }

    private func upsertMembership(
        householdId: UUID,
        userId: String,
        displayName: String,
        role: Member.MemberRole,
        scope: CloudKitManager.HouseholdDatabaseScope
    ) async throws -> Member {
        let normalizedKey = DisplayNameValidator.normalizedKey(displayName)
        let allMembers = try await cloudKit.fetchMembers(householdId: householdId, scope: scope)
        if allMembers.contains(where: {
            $0.isActive &&
                $0.userId != userId &&
                DisplayNameValidator.normalizedKey($0.displayName) == normalizedKey
        }) {
            throw HouseholdError.displayNameAlreadyTaken
        }

        if let existing = try await cloudKit.fetchMemberByUserId(
            userId,
            householdId: householdId,
            scope: scope
        ) {
            let resolvedRole: Member.MemberRole = existing.role == .owner ? .owner : role
            let shouldUpdate =
                existing.displayName != displayName ||
                !existing.isActive ||
                existing.role != resolvedRole

            guard shouldUpdate else { return existing }

            _ = try await cloudKit.updateMemberState(
                memberId: existing.id,
                householdId: existing.householdId,
                newDisplayName: displayName,
                newRole: resolvedRole,
                isActive: true,
                colorHex: existing.colorHex,
                scope: scope
            )
            return Member(
                id: existing.id,
                householdId: existing.householdId,
                userId: existing.userId,
                displayName: displayName,
                role: resolvedRole,
                joinedAt: existing.joinedAt,
                isActive: true,
                colorHex: existing.colorHex
            )
        }

        let member = Member(
            householdId: householdId,
            userId: userId,
            displayName: displayName,
            role: role,
            colorHex: MemberColorToken.randomHex()
        )
        _ = try await cloudKit.saveMember(member, scope: scope)
        return member
    }

    private func verifyParticipantSharedMembership(
        householdId: UUID,
        userId: String
    ) async throws -> Member {
        let retryDelaysNanoseconds: [UInt64] = [0, 250_000_000, 750_000_000]

        for delay in retryDelaysNanoseconds {
            if delay > 0 {
                try await _Concurrency.Task.sleep(nanoseconds: delay)
            }

            await cloudKit.setHouseholdScope(.participantShared)
            let verifiedMember = try await cloudKit.fetchMemberByUserId(
                userId,
                householdId: householdId,
                scope: .participantShared
            )

            if let verifiedMember, verifiedMember.isActive {
                print(
                    "DEBUG: Join verification succeeded for household \(householdId) user \(userId) in participantShared scope."
                )
                return verifiedMember
            }
        }

        print(
            "DEBUG: Join verification failed for household \(householdId) user \(userId) in participantShared scope."
        )
        throw HouseholdError.sharedAccessNotEstablished
    }

    private func requiredMembershipDisplayName(from rawDisplayName: String) throws -> String {
        guard let validated = try? DisplayNameValidator.validate(rawDisplayName) else {
            throw HouseholdError.displayNameRequired
        }
        return validated
    }

    private func runCreateHouseholdPostflight(household: Household, userId: String) {
        _ = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }

            await cloudKit.migrateMemberColorsIfNeeded(householdId: household.id)

            do {
                try await validateOwnerMembershipBootstrap(
                    household: household,
                    userId: userId
                )
            } catch {
                self.error = error
                print("DEBUG: Owner membership postflight validation failed: \(error)")
            }
        }
    }

    private func validateOwnerMembershipBootstrap(
        household: Household,
        userId: String
    ) async throws {
        let retryBackoffNanoseconds: [UInt64] = [0, 250_000_000, 750_000_000]
        var lastError: Error?

        for (attempt, delay) in retryBackoffNanoseconds.enumerated() {
            if delay > 0 {
                try await _Concurrency.Task.sleep(nanoseconds: delay)
            }

            let memberStore = MemberStore(householdId: household.id, modelContext: modelContext)
            memberStore.setSyncMode(syncMode)
            memberStore.setCloudContext(currentUserId: userId, householdOwnerId: household.ownerId)
            await memberStore.loadMembers()

            if let error = memberStore.error {
                lastError = error
            } else if let ownerMember = memberStore.members.first(where: {
                $0.userId == userId && $0.role == .owner && $0.isActive
            }) {
                updateCache(with: ownerMember)
                return
            } else {
                lastError = HouseholdError.memberNotFound
            }

            let isLastAttempt = attempt == retryBackoffNanoseconds.count - 1
            if isLastAttempt {
                throw lastError ?? HouseholdError.memberNotFound
            }
        }
    }

    private func prewarmJoinedHouseholdGraphIfNeeded(household: Household, userId: String) async {
        guard syncMode == .cloud else { return }

        let hydratedWithinBudget = await attemptInitialJoinHydrationWithinBudget(
            household: household,
            userId: userId
        )

        if !hydratedWithinBudget || pendingJoinStateMatches(householdId: household.id, userId: userId) {
            scheduleBackgroundJoinHydrationIfNeeded(
                household: household,
                userId: userId
            )
        }
    }

    private func attemptInitialJoinHydrationWithinBudget(
        household: Household,
        userId: String
    ) async -> Bool {
        do {
            return try await withJoinHydrationTimeout(
                nanoseconds: joinHydrationConfiguration.initialHydrationBudgetNanoseconds
            ) { [self] in
                await runJoinHydrationAttemptsUntilVisibleContent(
                    household: household,
                    userId: userId,
                    retryDelaysNanoseconds: joinHydrationConfiguration.initialRetryDelaysNanoseconds,
                    publishVisibleContentNotifications: true
                )
            }
        } catch JoinHydrationTimeoutError.timedOut {
            return false
        } catch {
            self.error = error
            return false
        }
    }

    private func scheduleBackgroundJoinHydrationIfNeeded(
        household: Household,
        userId: String
    ) {
        let shouldReplaceCurrentTask =
            joinHydrationTask == nil ||
            !pendingJoinStateMatches(householdId: household.id, userId: userId)

        guard shouldReplaceCurrentTask else { return }

        joinHydrationTask?.cancel()
        joinHydrationTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                joinHydrationTask = nil
            }

            await runBackgroundJoinHydrationLoop(
                household: household,
                userId: userId,
                retryDelaysNanoseconds: joinHydrationConfiguration.backgroundRetryDelaysNanoseconds
            )
        }
    }

    private func runBackgroundJoinHydrationLoop(
        household: Household,
        userId: String,
        retryDelaysNanoseconds: [UInt64]
    ) async {
        for delay in retryDelaysNanoseconds {
            guard pendingJoinStateMatches(householdId: household.id, userId: userId) ||
                currentHousehold?.id == household.id
            else {
                return
            }

            if delay > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: delay)
            }
            guard !_Concurrency.Task.isCancelled else { return }

            let snapshot = await performJoinedHouseholdHydrationPass(
                household: household,
                userId: userId,
                publishVisibleContentNotifications: true
            )

            if snapshot.hasVisibleSharedContent, snapshot.remoteMembershipConfirmed {
                return
            }
        }
    }

    private func runJoinHydrationAttemptsUntilVisibleContent(
        household: Household,
        userId: String,
        retryDelaysNanoseconds: [UInt64],
        publishVisibleContentNotifications: Bool
    ) async -> Bool {
        var attemptIndex = 0

        while !_Concurrency.Task.isCancelled {
            let delay = retryDelay(
                for: attemptIndex,
                from: retryDelaysNanoseconds
            )
            if delay > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: delay)
            }
            guard !_Concurrency.Task.isCancelled else { return false }

            let snapshot = await performJoinedHouseholdHydrationPass(
                household: household,
                userId: userId,
                publishVisibleContentNotifications: publishVisibleContentNotifications
            )
            if snapshot.hasVisibleSharedContent {
                return true
            }

            attemptIndex += 1
        }

        return false
    }

    private func retryDelay(
        for attemptIndex: Int,
        from retryDelaysNanoseconds: [UInt64]
    ) -> UInt64 {
        guard !retryDelaysNanoseconds.isEmpty else { return 0 }
        if attemptIndex < retryDelaysNanoseconds.count {
            return retryDelaysNanoseconds[attemptIndex]
        }
        return retryDelaysNanoseconds.last ?? 0
    }

    private func performJoinedHouseholdHydrationPass(
        household: Household,
        userId: String,
        publishVisibleContentNotifications: Bool
    ) async -> JoinedHouseholdHydrationSnapshot {
        do {
            let snapshot = try await runJoinedHouseholdHydrationPass(
                household: household,
                userId: userId
            )
            applyPendingJoinHydrationSnapshot(
                snapshot,
                householdId: household.id,
                userId: userId,
                publishVisibleContentNotifications: publishVisibleContentNotifications
            )
            return snapshot
        } catch {
            self.error = error
            let snapshot = cachedJoinHydrationSnapshot(
                householdId: household.id,
                userId: userId,
                remoteMembershipConfirmed: false
            )
            applyPendingJoinHydrationSnapshot(
                snapshot,
                householdId: household.id,
                userId: userId,
                publishVisibleContentNotifications: false
            )
            return snapshot
        }
    }

    private func runJoinedHouseholdHydrationPass(
        household: Household,
        userId: String
    ) async throws -> JoinedHouseholdHydrationSnapshot {
        if let joinedHouseholdPrewarmOverride {
            try await joinedHouseholdPrewarmOverride(household, userId, modelContext)
            let remoteMembershipConfirmed = try await confirmRemoteMembershipPresence(
                household: household,
                userId: userId
            )
            return cachedJoinHydrationSnapshot(
                householdId: household.id,
                userId: userId,
                remoteMembershipConfirmed: remoteMembershipConfirmed
            )
        }

        guard syncMode == .cloud, let modelContext else {
            return cachedJoinHydrationSnapshot(
                householdId: household.id,
                userId: userId,
                remoteMembershipConfirmed: false
            )
        }

        let ownerId = household.ownerId

        let memberStore = MemberStore(householdId: household.id, modelContext: modelContext)
        memberStore.setSyncMode(syncMode)
        memberStore.setCloudContext(currentUserId: userId, householdOwnerId: ownerId)
        await memberStore.loadMembers()
        if let error = memberStore.error {
            throw error
        }

        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(household.id)
        taskStore.setSyncMode(syncMode)
        taskStore.setCloudContext(currentUserId: userId, householdOwnerId: ownerId)

        let shoppingStore = ShoppingListStore(householdId: household.id, modelContext: modelContext)
        shoppingStore.setSyncMode(syncMode)
        shoppingStore.setCloudContext(currentUserId: userId, householdOwnerId: ownerId)

        let bundleStore = ShoppingBundleStore(householdId: household.id, modelContext: modelContext)
        bundleStore.setSyncMode(syncMode)
        bundleStore.setCloudContext(currentUserId: userId, householdOwnerId: ownerId)

        let backlogStore = BacklogStore(householdId: household.id, modelContext: modelContext)
        backlogStore.setSyncMode(syncMode)
        backlogStore.setCloudContext(currentUserId: userId, householdOwnerId: ownerId)

        async let loadTasks: Void = taskStore.loadTasks()
        async let loadShoppingItems: Void = shoppingStore.loadItems()
        async let loadBundles: Void = bundleStore.loadBundles()
        async let loadBacklog: Void = backlogStore.loadData()
        _ = await (loadTasks, loadShoppingItems, loadBundles, loadBacklog)

        if let error = taskStore.error ?? shoppingStore.error ?? bundleStore.error ?? backlogStore.error {
            throw error
        }

        let remoteMembershipConfirmed = try await confirmRemoteMembershipPresence(
            household: household,
            userId: userId
        )

        return cachedJoinHydrationSnapshot(
            householdId: household.id,
            userId: userId,
            remoteMembershipConfirmed: remoteMembershipConfirmed
        )
    }

    private func confirmRemoteMembershipPresence(
        household: Household,
        userId: String
    ) async throws -> Bool {
        await setCloudScope(for: household, userId: userId)
        return try await cloudKit.fetchMemberByUserId(
            userId,
            householdId: household.id,
            scope: nil
        )?.isActive ?? false
    }

    private func cachedJoinHydrationSnapshot(
        householdId: UUID,
        userId: String,
        remoteMembershipConfirmed: Bool
    ) -> JoinedHouseholdHydrationSnapshot {
        let activeMembers = fetchCachedMembers(householdId: householdId).filter(\.isActive)

        let taskCount: Int = fetchCachedWorkItems(householdId: householdId).filter {
            $0.syncStatusRaw != "pendingDelete" &&
                $0.statusRaw != WorkItem.Status.idea.rawValue
        }.count

        let ideaCount: Int = fetchCachedWorkItems(householdId: householdId).filter {
            $0.syncStatusRaw != "pendingDelete" &&
                $0.statusRaw == WorkItem.Status.idea.rawValue
        }.count

        let categoryCount: Int = fetchCachedBacklogCategories(householdId: householdId).count
        let shoppingItemCount: Int = fetchCachedShoppingItems(householdId: householdId).filter {
            $0.syncStatusRaw != "pendingDelete"
        }.count
        let bundleCount: Int = fetchCachedShoppingBundles(householdId: householdId).filter {
            $0.syncStatusRaw != "pendingDelete" &&
                $0.syncStatusRaw != "awaitingDeleteEcho"
        }.count

        return JoinedHouseholdHydrationSnapshot(
            activeMemberCount: activeMembers.count,
            currentUserHasCachedMembership: activeMembers.contains(where: { $0.userId == userId }),
            remoteMembershipConfirmed: remoteMembershipConfirmed,
            taskCount: taskCount,
            ideaCount: ideaCount,
            categoryCount: categoryCount,
            shoppingItemCount: shoppingItemCount,
            bundleCount: bundleCount
        )
    }

    private func remoteCloudRefreshSnapshot(
        userId: String,
        preferredHouseholdId: UUID?
    ) -> RemoteCloudRefreshSnapshot {
        let currentHouseholdId = currentHousehold?.id
        let observedHouseholdId = currentHouseholdId ?? preferredHouseholdId
        let hydrationSnapshot = observedHouseholdId.map { householdId in
            cachedJoinHydrationSnapshot(
                householdId: householdId,
                userId: userId,
                remoteMembershipConfirmed: isValidCachedMembershipForRecoveredHousehold(
                    householdId: householdId,
                    userId: userId
                )
            )
        }

        return RemoteCloudRefreshSnapshot(
            currentHouseholdId: currentHouseholdId,
            observedHouseholdId: observedHouseholdId,
            hydrationSnapshot: hydrationSnapshot
        )
    }

    private func publishRemoteCloudRefreshNotifications(source: String) {
        NotificationCenter.default.post(name: .householdDataDidChange, object: source)
        NotificationCenter.default.post(name: .taskBoardDataDidChange, object: source)
        NotificationCenter.default.post(name: .shoppingListDataDidChange, object: source)
        NotificationCenter.default.post(name: .backlogDataDidChange, object: source)
    }

    private func describeRemoteCloudRefreshSnapshot(_ snapshot: RemoteCloudRefreshSnapshot) -> String {
        guard let hydrationSnapshot = snapshot.hydrationSnapshot else {
            return "current=nil observed=\(snapshot.observedHouseholdId?.uuidString ?? "none") data=empty"
        }

        return [
            "current=\(snapshot.currentHouseholdId?.uuidString ?? "none")",
            "observed=\(snapshot.observedHouseholdId?.uuidString ?? "none")",
            "members=\(hydrationSnapshot.activeMemberCount)",
            "currentUser=\(hydrationSnapshot.currentUserHasCachedMembership)",
            "tasks=\(hydrationSnapshot.taskCount)",
            "ideas=\(hydrationSnapshot.ideaCount)",
            "categories=\(hydrationSnapshot.categoryCount)",
            "shopping=\(hydrationSnapshot.shoppingItemCount)",
            "bundles=\(hydrationSnapshot.bundleCount)",
        ].joined(separator: " ")
    }

    private func describeBackgroundFetchResult(_ result: UIBackgroundFetchResult) -> String {
        switch result {
        case .newData:
            "newData"
        case .noData:
            "noData"
        case .failed:
            "failed"
        @unknown default:
            "unknown"
        }
    }

    private func applyPendingJoinHydrationSnapshot(
        _ snapshot: JoinedHouseholdHydrationSnapshot,
        householdId: UUID,
        userId: String,
        publishVisibleContentNotifications: Bool
    ) {
        guard pendingJoinStateMatches(householdId: householdId, userId: userId) else { return }
        guard var pendingJoinState else { return }

        pendingJoinState.hasCompletedHydrationPass = true
        if snapshot.remoteMembershipConfirmed {
            pendingJoinState.hasConfirmedRemoteMembership = true
        }

        if publishVisibleContentNotifications,
           snapshot.hasVisibleSharedContent,
           !pendingJoinState.hasPublishedVisibleContentNotifications
        {
            NotificationCenter.default.post(name: .taskBoardDataDidChange, object: "local")
            NotificationCenter.default.post(name: .shoppingListDataDidChange, object: "local")
            NotificationCenter.default.post(name: .backlogDataDidChange, object: "local")
            pendingJoinState.hasPublishedVisibleContentNotifications = true
        }

        if pendingJoinState.hasCompletedHydrationPass, pendingJoinState.hasConfirmedRemoteMembership {
            self.pendingJoinState = nil
        } else {
            self.pendingJoinState = pendingJoinState
        }
    }

    private func withJoinHydrationTimeout<T>(
        nanoseconds: UInt64,
        operation: @escaping @MainActor () async -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try await _Concurrency.Task.sleep(nanoseconds: nanoseconds)
                throw JoinHydrationTimeoutError.timedOut
            }

            guard let result = try await group.next() else {
                throw JoinHydrationTimeoutError.timedOut
            }
            group.cancelAll()
            return result
        }
    }

    func resolveLeaveBehavior(for member: Member, activeMembers: [Member]) -> LeaveResolution {
        guard member.role == .owner else {
            return .deactivateMembership
        }

        let otherActiveMembers = activeMembers.filter { $0.id != member.id }
        let hasOtherActiveOwners = otherActiveMembers.contains(where: { $0.role == .owner })

        if activeMembers.count <= 1 {
            return .deleteHousehold
        }
        if !otherActiveMembers.isEmpty, !hasOtherActiveOwners {
            return .requireTransfer
        }
        return .deactivateMembership
    }

    private func isRecordMissingError(_ error: Error) -> Bool {
        if let ckError = error as? CKError {
            return ckError.code == .unknownItem
        }
        if let managerError = error as? CloudKitManager.CloudKitManagerError,
           case let .unknownError(underlying) = managerError
        {
            return isRecordMissingError(underlying)
        }
        return false
    }

    func clearCurrentHousehold() {
        joinHydrationTask?.cancel()
        joinHydrationTask = nil
        pendingJoinState = nil
        currentHousehold = nil
        share = nil
        activeInviteCode = nil
        activeContainer = nil
        activeShare = nil
        _ = _Concurrency.Task { [cloudKit] in
            await cloudKit.setHouseholdScope(.participantShared)
        }
    }

    func resolveMembershipDisplayNameLocally(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) -> String? {
        var householdIds: [UUID] = []

        if let currentHouseholdId = currentHousehold?.id {
            householdIds.append(currentHouseholdId)
        }

        if let preferredHouseholdId,
           !householdIds.contains(preferredHouseholdId)
        {
            householdIds.append(preferredHouseholdId)
        }

        for cachedHousehold in fetchRecoverableCachedHouseholds(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        ) where !householdIds.contains(cachedHousehold.id) {
            householdIds.append(cachedHousehold.id)
        }

        for householdId in householdIds {
            if let member = fetchCachedMembers(householdId: householdId).first(where: {
                $0.userId == userId && $0.isActive
            }) {
                return member.displayName
            }
        }

        return nil
    }

    func isRecoverySuppressed(for householdId: UUID) -> Bool {
        let suppressions = loadSuppressedRecoveries(cleaningExpired: true)
        return suppressions[householdId.uuidString] != nil || hasPendingExitOperation(for: householdId)
    }

    func prepareForSetupResolution(key: String) {
        guard !setupResolutionState.matches(key: key)
            || setupResolutionState.resolvedHouseholdCount != nil
        else {
            return
        }
        setupResolutionState = .loading(key: key)
    }

    func completeSetupResolution(key: String, householdCount: Int) {
        setupResolutionState = .resolved(
            key: key,
            householdCount: normalizedSingleHouseholdCount(householdCount)
        )
    }

    func resetSetupResolution() {
        setupResolutionState = .idle
    }

    func cachedRecoverableHouseholdCount(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) -> Int {
        normalizedSingleHouseholdCount(fetchRecoverableCachedHouseholds(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        ).count)
    }

    func hasTrustedLocalHouseholdContext(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) -> Bool {
        currentHousehold != nil ||
            fetchCachedHousehold(userId: userId, preferredHouseholdId: preferredHouseholdId) != nil
    }

    // MARK: - SwiftData Helpers

    private func fetchCachedHousehold(
        userId: String,
        preferredHouseholdId: UUID?
    ) -> CachedHousehold? {
        let cachedHouseholds = fetchRecoverableCachedHouseholds(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )
        guard !cachedHouseholds.isEmpty else { return nil }

        if let preferredHouseholdId,
           let preferredMatch = cachedHouseholds.first(where: { $0.id == preferredHouseholdId })
        {
            return preferredMatch
        }

        if let ownerMatch = cachedHouseholds.first(where: { $0.ownerId == userId }) {
            return ownerMatch
        }

        return cachedHouseholds.first
    }

    private func fetchCachedMembers(householdId: UUID) -> [Member] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedMember>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.joinedAt)]
        )

        do {
            return try context.fetch(descriptor).map { $0.toMember() }
        } catch {
            print("Fetch cached members error: \(error)")
            return []
        }
    }

    private func isValidCachedMembershipForRecoveredHousehold(
        householdId: UUID,
        userId: String
    ) -> Bool {
        guard syncMode == .cloud else { return true }
        return fetchCachedMembers(householdId: householdId).contains {
            $0.userId == userId && $0.isActive
        }
    }

    private func resolvedActiveMembersForExit(
        householdId: UUID,
        activeMembersSnapshot: [Member]?
    ) -> [Member] {
        let source = activeMembersSnapshot ?? fetchCachedMembers(householdId: householdId)
        return source.filter(\.isActive)
    }

    private func fetchRecoverableCachedHouseholds(
        userId _: String,
        preferredHouseholdId _: UUID?
    ) -> [CachedHousehold] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedHousehold>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        do {
            let cachedHouseholds = try context.fetch(descriptor).filter { !isRecoverySuppressed(for: $0.id) }
            if cachedHouseholds.count > 1 {
                print("DEBUG: Multiple recoverable households found locally; enforcing single-household mode.")
            }
            return cachedHouseholds
        } catch {
            print("Fetch error: \(error)")
            return []
        }
    }

    private var shouldSkipRemoteSingleHouseholdDiscoveryForCreate: Bool {
        setupResolutionState.resolvedHouseholdCount == 0
    }

    private func ensureUserCanStartSingleHouseholdLocally(userId: String) throws {
        if let household = currentHousehold,
           !isRecoverySuppressed(for: household.id)
        {
            throw HouseholdError.alreadyInHousehold
        }

        if fetchCachedHousehold(userId: userId, preferredHouseholdId: nil) != nil {
            throw HouseholdError.alreadyInHousehold
        }
    }

    private func ensureUserCanStartSingleHouseholdRemotely(userId: String) async throws {
        await replayPendingExitOperationsIfNeeded()
        await cloudKit.ensureReady()
        try await cloudKit.checkAvailability()

        let activeMemberships = try await fetchScopedActiveMemberships(userId: userId)
        if !activeMemberships.isEmpty {
            throw HouseholdError.alreadyInHousehold
        }
    }

    private func ensureUserCanStartSingleHousehold(userId: String) async throws {
        try ensureUserCanStartSingleHouseholdLocally(userId: userId)

        guard syncMode == .cloud else { return }
        try await ensureUserCanStartSingleHouseholdRemotely(userId: userId)
    }

    func hasPendingJoinProtection(for householdId: UUID?, userId: String?) -> Bool {
        guard let householdId, let userId else { return false }
        return shouldProtectPendingJoin(householdId: householdId, userId: userId)
    }

    func forceCloudSyncDebug(userId: String) async {
        guard syncMode == .cloud, let household = currentHousehold else { return }

        isLoading = true
        defer { isLoading = false }

        await refreshCurrentHouseholdAndMembershipFromCloud(
            userId: userId,
            preferredHouseholdId: household.id
        )

        let refreshedHousehold = currentHousehold ?? household
        _ = await performJoinedHouseholdHydrationPass(
            household: refreshedHousehold,
            userId: userId,
            publishVisibleContentNotifications: true
        )
    }

    func handleRemoteCloudChange(
        userId: String?,
        preferredHouseholdId: UUID?
    ) async -> UIBackgroundFetchResult {
        guard syncMode == .cloud else {
            print("[RemoteSync] Ignoring remote push because sync mode is local-only.")
            return .noData
        }

        guard let userId else {
            print("[RemoteSync] Ignoring remote push because there is no active cloud user.")
            return .noData
        }

        let beforeSnapshot = remoteCloudRefreshSnapshot(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )
        print(
            "[RemoteSync] Starting background household refresh. before=\(describeRemoteCloudRefreshSnapshot(beforeSnapshot))"
        )

        await refreshCurrentHouseholdAndMembershipFromCloud(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )

        if let household = currentHousehold {
            do {
                let hydrationSnapshot = try await runJoinedHouseholdHydrationPass(
                    household: household,
                    userId: userId
                )
                applyPendingJoinHydrationSnapshot(
                    hydrationSnapshot,
                    householdId: household.id,
                    userId: userId,
                    publishVisibleContentNotifications: false
                )
                print(
                    "[RemoteSync] Hydration pass finished for household \(household.id). members=\(hydrationSnapshot.activeMemberCount) tasks=\(hydrationSnapshot.taskCount) ideas=\(hydrationSnapshot.ideaCount) shopping=\(hydrationSnapshot.shoppingItemCount) bundles=\(hydrationSnapshot.bundleCount)"
                )
            } catch {
                self.error = error
                print("[RemoteSync] Hydration pass failed: \(error)")
                return .failed
            }
        }

        let afterSnapshot = remoteCloudRefreshSnapshot(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )
        let didChange = beforeSnapshot != afterSnapshot

        if didChange {
            publishRemoteCloudRefreshNotifications(source: "remotePush")
        }

        let fetchResult: UIBackgroundFetchResult = didChange ? .newData : .noData
        print(
            "[RemoteSync] Background household refresh completed with result=\(describeBackgroundFetchResult(fetchResult)). after=\(describeRemoteCloudRefreshSnapshot(afterSnapshot))"
        )
        return fetchResult
    }

    private func resolveRecoverableCloudHousehold(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) async throws -> Household? {
        if let preferredHouseholdId, !isRecoverySuppressed(for: preferredHouseholdId) {
            let preferredMemberships = try await fetchScopedActiveMemberships(
                userId: userId,
                householdId: preferredHouseholdId
            )
            for scopedMembership in preferredMemberships {
                if let recoveredHousehold = try await recoverableHousehold(
                    from: scopedMembership.member,
                    source: scopedMembership.source
                ) {
                    return recoveredHousehold
                }
            }

            print(
                "DEBUG: Preferred household \(preferredHouseholdId) has no active membership for user \(userId); abandoning recovery."
            )
            await invalidateRecoveredHousehold(preferredHouseholdId)
        }

        let scopedMemberships = try await fetchScopedActiveMemberships(userId: userId)
        guard !scopedMemberships.isEmpty else { return nil }

        var recoveredByHouseholdId: [UUID: Household] = [:]
        for scopedMembership in scopedMemberships {
            if let recoveredHousehold = try await recoverableHousehold(
                from: scopedMembership.member,
                source: scopedMembership.source
            ) {
                recoveredByHouseholdId[recoveredHousehold.id] = recoveredHousehold
            }
        }

        if recoveredByHouseholdId.count > 1 {
            let householdIds = recoveredByHouseholdId.keys.map(\.uuidString).sorted().joined(separator: ", ")
            print("DEBUG: Ambiguous active memberships for user \(userId); refusing automatic recovery: \(householdIds)")
            return nil
        }

        return recoveredByHouseholdId.values.first
    }

    func validateRecoveredMembershipOrAbandon(
        household: Household,
        userId: String,
        retryDelaysNanoseconds: [UInt64] = [0, 250_000_000, 750_000_000],
        fetchActiveMember: ((Household, String) async throws -> Member?)? = nil
    ) async throws -> Bool {
        guard syncMode == .cloud else { return true }

        let fetchActiveMember = fetchActiveMember ?? { [cloudKit] household, userId in
            let scope: CloudKitManager.HouseholdDatabaseScope = household.ownerId == userId
                ? .ownerPrivate
                : .participantShared
            return try await cloudKit.fetchMemberByUserId(
                userId,
                householdId: household.id,
                scope: scope
            )
        }

        for delay in retryDelaysNanoseconds {
            if delay > 0 {
                try await _Concurrency.Task.sleep(nanoseconds: delay)
            }

            if let member = try await fetchActiveMember(household, userId), member.isActive {
                if pendingJoinStateMatches(householdId: household.id, userId: userId) {
                    pendingJoinState?.hasConfirmedRemoteMembership = true
                    if pendingJoinState?.hasCompletedHydrationPass == true {
                        pendingJoinState = nil
                    }
                }
                return true
            }
        }

        if shouldProtectPendingJoin(householdId: household.id, userId: userId) {
            print(
                "DEBUG: Preserving pending-join household \(household.id) while waiting for remote membership confirmation."
            )
            scheduleBackgroundJoinHydrationIfNeeded(
                household: household,
                userId: userId
            )
            return true
        }

        print(
            "DEBUG: Abandoning recovered household \(household.id) because no active membership exists for user \(userId)."
        )
        await invalidateRecoveredHousehold(household.id)
        return false
    }

    func recoverableHousehold(
        from member: Member?,
        source: RecoverableMembershipSource,
        fetchHousehold: ((UUID) async throws -> Household)? = nil,
        onMissingHousehold: ((Member, RecoverableMembershipSource) async -> Void)? = nil
    ) async throws -> Household? {
        guard let member, !isRecoverySuppressed(for: member.householdId) else {
            return nil
        }

        let fetchHousehold = fetchHousehold ?? { [cloudKit] householdId in
            try await cloudKit.fetchHousehold(id: householdId, scope: nil)
        }

        do {
            return try await fetchHousehold(member.householdId)
        } catch {
            guard isRecordMissingError(error) else {
                throw error
            }

            print(
                "DEBUG: Ignoring stale \(source.rawValue) membership for missing household \(member.householdId)"
            )
            suppressRecovery(for: member.householdId)
            if let onMissingHousehold {
                await onMissingHousehold(member, source)
            } else {
                await cleanupStaleRecoverableMembership(member, source: source)
            }
            return nil
        }
    }

    private func invalidateRecoveredHousehold(_ householdId: UUID) async {
        suppressRecovery(for: householdId)
        removeHouseholdFromCache(id: householdId)
        if currentHousehold?.id == householdId {
            clearCurrentHousehold()
        }
        await cloudKit.clearAllCachedZones(for: householdId)
    }

    private func cleanupStaleRecoverableMembership(
        _ member: Member,
        source: RecoverableMembershipSource
    ) async {
        await cloudKit.clearAllCachedZones(for: member.householdId)

        do {
            _ = try await cloudKit.updateMemberState(
                memberId: member.id,
                householdId: member.householdId,
                newDisplayName: member.displayName,
                newRole: member.role,
                isActive: false,
                colorHex: member.colorHex,
                scope: nil
            )
        } catch {
            guard !isRecordMissingError(error) else { return }
            print(
                "DEBUG: Failed to deactivate stale \(source.rawValue) membership for household \(member.householdId): \(error)"
            )
        }
    }

    private func normalizedSingleHouseholdCount(_ count: Int) -> Int {
        count > 0 ? 1 : 0
    }

    @discardableResult
    private func updateCache(with household: Household) -> Bool {
        guard let context = modelContext else { return true }

        let descriptor = FetchDescriptor<CachedHousehold>(
            predicate: #Predicate { $0.id == household.id }
        )

        do {
            let results = try context.fetch(descriptor)
            if let existing = results.first {
                existing.update(from: household)
            } else {
                context.insert(CachedHousehold(from: household))
            }
            return saveContextOrSetError(context, operation: "upsert cached household")
        } catch {
            print("Cache update error: \(error)")
            self.error = error
            return false
        }
    }

    // swiftlint:disable function_body_length
    private func removeHouseholdFromCache(id: UUID) {
        guard let context = modelContext else { return }

        let householdId = id
        let householdDescriptor = FetchDescriptor<CachedHousehold>(
            predicate: #Predicate { $0.id == householdId }
        )
        let memberDescriptor = FetchDescriptor<CachedMember>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let taskDescriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let shoppingDescriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let shoppingBundleDescriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let backlogCategoryDescriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let backlogItemDescriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let recurringChoreDescriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        do {
            if let cachedHousehold = try context.fetch(householdDescriptor).first {
                context.delete(cachedHousehold)
            }

            for member in try context.fetch(memberDescriptor) {
                context.delete(member)
            }
            for task in try context.fetch(taskDescriptor) {
                context.delete(task)
            }
            for item in try context.fetch(shoppingDescriptor) {
                context.delete(item)
            }
            for bundle in try context.fetch(shoppingBundleDescriptor) {
                context.delete(bundle)
            }
            for category in try context.fetch(backlogCategoryDescriptor) {
                context.delete(category)
            }
            for item in try context.fetch(backlogItemDescriptor) {
                context.delete(item)
            }
            for chore in try context.fetch(recurringChoreDescriptor) {
                context.delete(chore)
            }

            saveContextOrSetError(context, operation: "remove household cache graph")
        } catch {
            print("Cache household removal error: \(error)")
            self.error = error
        }
    }

    // swiftlint:enable function_body_length

    private func suppressRecovery(for householdId: UUID) {
        var suppressions = loadSuppressedRecoveries(cleaningExpired: true)
        suppressions[householdId.uuidString] = Date().addingTimeInterval(recoverySuppressionDuration)
        userDefaults.set(
            suppressions.mapValues(\.timeIntervalSince1970),
            forKey: DefaultsKey.suppressedHouseholdRecoveries
        )
    }

    private func loadSuppressedRecoveries(cleaningExpired: Bool) -> [String: Date] {
        let raw = userDefaults.dictionary(forKey: DefaultsKey.suppressedHouseholdRecoveries) as? [String: TimeInterval] ?? [:]
        let now = Date()
        let mapped = raw.reduce(into: [String: Date]()) { partialResult, entry in
            let date = Date(timeIntervalSince1970: entry.value)
            if !cleaningExpired || date > now {
                partialResult[entry.key] = date
            }
        }

        if cleaningExpired, mapped.count != raw.count {
            userDefaults.set(
                mapped.mapValues(\.timeIntervalSince1970),
                forKey: DefaultsKey.suppressedHouseholdRecoveries
            )
        }

        return mapped
    }

    // MARK: - Local Household Bootstrap

    private func updateCache(with member: Member) {
        guard let context = modelContext else { return }

        let memberId = member.id
        let descriptor = FetchDescriptor<CachedMember>(
            predicate: #Predicate { $0.id == memberId }
        )

        do {
            if let cached = try context.fetch(descriptor).first {
                cached.update(from: member)
            } else {
                context.insert(CachedMember(from: member))
            }
            saveContextOrSetError(context, operation: "upsert cached household member")
        } catch {
            print("Cache update error: \(error)")
            self.error = error
        }
    }

    private func updateCache(with members: [Member]) {
        for member in members {
            updateCache(with: member)
        }
    }

    private func beginPendingJoinProtection(householdId: UUID, userId: String) {
        joinHydrationTask?.cancel()
        joinHydrationTask = nil
        pendingJoinState = PendingJoinState(
            householdId: householdId,
            userId: userId,
            startedAt: Date(),
            expiresAt: Date().addingTimeInterval(joinHydrationConfiguration.pendingJoinGraceDuration)
        )
    }

    private func pendingJoinStateMatches(householdId: UUID, userId: String) -> Bool {
        guard let pendingJoinState else { return false }
        guard pendingJoinState.householdId == householdId, pendingJoinState.userId == userId else {
            return false
        }

        if pendingJoinState.expiresAt <= Date() {
            self.pendingJoinState = nil
            return false
        }

        return true
    }

    private func shouldProtectPendingJoin(householdId: UUID, userId: String) -> Bool {
        guard pendingJoinStateMatches(householdId: householdId, userId: userId) else {
            return false
        }
        return hasActiveCachedMembership(householdId: householdId, userId: userId)
    }

    private func hasActiveCachedMembership(householdId: UUID, userId: String) -> Bool {
        fetchCachedMembers(householdId: householdId).contains {
            $0.userId == userId && $0.isActive
        }
    }

    private func refreshMemberCacheFromCloudIfNeeded(
        household: Household,
        userId: String
    ) async {
        do {
            await setCloudScope(for: household, userId: userId)
            let remoteMembers = try await cloudKit.fetchMembers(
                householdId: household.id,
                scope: nil
            )
            let mergedMembers = mergeRemoteMembersWithLocalJoinFallback(
                remoteMembers,
                householdId: household.id,
                currentUserId: userId
            )
            updateCache(with: mergedMembers)
        } catch {
            if !shouldProtectPendingJoin(householdId: household.id, userId: userId) {
                self.error = error
            }
        }
    }

    private func mergeRemoteMembersWithLocalJoinFallback(
        _ remoteMembers: [Member],
        householdId: UUID,
        currentUserId: String
    ) -> [Member] {
        let cachedMembers = fetchCachedMembers(householdId: householdId)
        var mergedById = Dictionary(uniqueKeysWithValues: remoteMembers.map { ($0.id, $0) })

        if let cachedCurrentUserMember = cachedMembers.first(where: {
            $0.userId == currentUserId && $0.isActive
        }),
            !mergedById.values.contains(where: { $0.userId == currentUserId && $0.isActive })
        {
            mergedById[cachedCurrentUserMember.id] = cachedCurrentUserMember
        }

        return mergedById.values.sorted { $0.joinedAt < $1.joinedAt }
    }

    private func fetchCachedWorkItems(householdId: UUID) -> [CachedWorkItem] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Fetch cached work items error: \(error)")
            return []
        }
    }

    private func fetchCachedBacklogCategories(householdId: UUID) -> [CachedBacklogCategory] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Fetch cached backlog categories error: \(error)")
            return []
        }
    }

    private func fetchCachedShoppingItems(householdId: UUID) -> [CachedShoppingItem] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Fetch cached shopping items error: \(error)")
            return []
        }
    }

    private func fetchCachedShoppingBundles(householdId: UUID) -> [CachedShoppingBundle] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Fetch cached shopping bundles error: \(error)")
            return []
        }
    }
}

// swiftlint:enable type_body_length file_length
