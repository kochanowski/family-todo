import CloudKit
import Combine
import SwiftData
import SwiftUI
import UIKit

@MainActor
// swiftlint:disable type_body_length
class HouseholdStore: ObservableObject {
    private enum DefaultsKey {
        static let suppressedHouseholdRecoveries = "suppressedHouseholdRecoveries"
    }

    enum LeaveResolution: Equatable {
        case deleteHousehold
        case requireTransfer
        case deactivateMembership
    }

    @Published var currentHousehold: Household?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var share: CKShare?
    @Published var activeInviteCode: String?

    private var modelContext: ModelContext?
    private lazy var cloudKit = CloudKitManager.shared
    private var syncMode: SyncMode = .cloud
    private let userDefaults: UserDefaults
    private let recoverySuppressionDuration: TimeInterval

    // Cache for sharing controller
    private var activeShare: CKShare?
    private(set) var activeContainer: CKContainer?

    init(
        modelContext: ModelContext? = nil,
        userDefaults: UserDefaults = .standard,
        recoverySuppressionDuration: TimeInterval = 300
    ) {
        self.modelContext = modelContext
        self.userDefaults = userDefaults
        self.recoverySuppressionDuration = recoverySuppressionDuration
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
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
        await loadHousehold(userId: userId, preferredHouseholdId: preferredHouseholdId)
    }

    func loadHousehold(userId: String, preferredHouseholdId: UUID? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // 1. Try to load from cache first
        if let cached = fetchCachedHousehold(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        ) {
            currentHousehold = cached.toHousehold()
        }

        guard syncMode == .cloud else { return }

        // 2. Load from CloudKit
        do {
            // Ensure CloudKit is ready before accessing
            await cloudKit.ensureReady()
            try await cloudKit.checkAvailability()

            // In a real app with private DB + sharing, finding the "current" household
            // often involves querying for the one owned by user or shared with them.
            // For MVP/HousePulse, we check if we have one locally, otherwise we might look
            // for the one where we are a member.

            if let current = currentHousehold {
                do {
                    await setCloudScope(for: current, userId: userId)
                    let fresh = try await cloudKit.fetchHousehold(id: current.id)
                    await cloudKit.migrateMemberColorsIfNeeded(householdId: fresh.id)
                    updateCache(with: fresh)
                    currentHousehold = fresh
                    return
                } catch {
                    // Cached household can be stale. Fall through to membership lookup.
                    print("DEBUG: Cached household refresh failed, retrying membership lookup: \(error)")
                    currentHousehold = nil
                }
            }

            // If checking cloud for the first time on this device
            print("DEBUG: Checking CloudKit for existing household membership...")
            var resolvedMember: Member?

            // Prefer participant scope first.
            await cloudKit.setHouseholdScope(.participantShared)
            if let participantMember = try await cloudKit.fetchMemberByUserId(userId),
               !isRecoverySuppressed(for: participantMember.householdId)
            {
                resolvedMember = participantMember
            }

            // Fallback to owner scope if not found.
            if resolvedMember == nil {
                await cloudKit.setHouseholdScope(.ownerPrivate)
                if let ownerMember = try await cloudKit.fetchMemberByUserId(userId),
                   !isRecoverySuppressed(for: ownerMember.householdId)
                {
                    resolvedMember = ownerMember
                }
            }

            if let member = resolvedMember {
                print("DEBUG: Found member membership for household: \(member.householdId)")
                let fresh = try await cloudKit.fetchHousehold(id: member.householdId)
                await setCloudScope(for: fresh, userId: userId)
                await cloudKit.migrateMemberColorsIfNeeded(householdId: fresh.id)
                updateCache(with: fresh)
                currentHousehold = fresh
            } else {
                print("DEBUG: No existing membership found in cloud.")
            }
        } catch {
            print("Error loading household: \(error)")
            // Don't show error to user if we have cached data
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

        isLoading = true
        defer { isLoading = false }

        let validatedDisplayName = normalizedMembershipDisplayName(from: displayName)
        let trimmedHouseholdName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHouseholdName.isEmpty else {
            throw HouseholdError.invalidInviteCode
        }

        let newHousehold = Household(
            name: trimmedHouseholdName,
            iconSymbol: iconSymbol,
            ownerId: userId
        )

        // 1. Save to CloudKit (if cloud sync is enabled and available)
        if syncMode == .cloud {
            // Check CloudKit availability first
            try await cloudKit.checkAvailability()
            await cloudKit.setHouseholdScope(.ownerPrivate)
            _ = try await cloudKit.ensureHouseholdOwnerZone(householdId: newHousehold.id)

            _ = try await cloudKit.saveHousehold(newHousehold)

            // Create initial member (owner)
            let owner = Member(
                householdId: newHousehold.id,
                userId: userId,
                displayName: validatedDisplayName,
                role: .owner,
                colorHex: MemberColorToken.randomHex()
            )
            _ = try await cloudKit.saveMember(owner)
            await cloudKit.migrateMemberColorsIfNeeded(householdId: newHousehold.id)
        }

        // 2. Seed default data in local-only mode
        if syncMode == .localOnly {
            try seedDefaultData(
                householdId: newHousehold.id,
                userId: userId,
                displayName: validatedDisplayName
            )
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

        let validatedDisplayName = normalizedMembershipDisplayName(from: displayName)

        try await cloudKit.checkAvailability()
        let normalizedInvite = try InviteInputNormalizer.normalizeInput(input)
        let isInviteCodeFlow = InviteInputNormalizer.normalizeInviteCodeToken(normalizedInvite.inviteCode) != nil
        let household: Household
        if isInviteCodeFlow {
            household = try await cloudKit.redeemInviteCode(normalizedInvite.inviteCode)
        } else {
            await cloudKit.setHouseholdScope(.participantShared)
            household = try await cloudKit.acceptShare(inviteCode: normalizedInvite.inviteCode)
        }
        await cloudKit.setHouseholdScope(.participantShared)
        await cloudKit.migrateMemberColorsIfNeeded(householdId: household.id)

        try await upsertMembership(
            householdId: household.id,
            userId: userId,
            displayName: validatedDisplayName,
            role: household.ownerId == userId ? .owner : .member
        )

        // Update local cache
        updateCache(with: household)
        currentHousehold = household
    }

    func joinHousehold(metadata: CKShare.Metadata, userId: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard syncMode == .cloud else {
            throw HouseholdError.cloudSyncRequired
        }

        let validatedDisplayName = normalizedMembershipDisplayName(from: displayName)

        try await cloudKit.checkAvailability()
        await cloudKit.setHouseholdScope(.participantShared)

        let household = try await cloudKit.acceptShare(metadata: metadata)
        await cloudKit.setHouseholdScope(.participantShared)
        await cloudKit.migrateMemberColorsIfNeeded(householdId: household.id)

        try await upsertMembership(
            householdId: household.id,
            userId: userId,
            displayName: validatedDisplayName,
            role: household.ownerId == userId ? .owner : .member
        )

        updateCache(with: household)
        currentHousehold = household
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
        guard var household = currentHousehold else {
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

        household.name = trimmedName
        household.iconSymbol = resolvedIconSymbol
        household.updatedAt = Date()
        updateCache(with: household)
        currentHousehold = household

        if syncMode == .cloud {
            do {
                await setCloudScope(for: household, userId: userId)
                let members = try await cloudKit.fetchMembers(householdId: household.id)
                guard members.contains(where: { $0.userId == userId && $0.isActive }) else {
                    throw HouseholdError.notAuthorized
                }
                _ = try await cloudKit.updateHouseholdMetadata(
                    householdId: household.id,
                    newName: household.name,
                    newIconSymbol: resolvedIconSymbol
                )
            } catch {
                self.error = error
                throw error
            }
        }
    }

    func resolveMembershipDisplayName(userId: String) async -> String? {
        guard syncMode == .cloud else { return nil }

        if let household = currentHousehold {
            await setCloudScope(for: household, userId: userId)
            if let member = try? await cloudKit.fetchMemberByUserId(userId, householdId: household.id),
               member.isActive
            {
                return member.displayName
            }
        }

        await cloudKit.setHouseholdScope(.participantShared)
        if let member = try? await cloudKit.fetchMemberByUserId(userId), member.isActive {
            return member.displayName
        }

        await cloudKit.setHouseholdScope(.ownerPrivate)
        if let member = try? await cloudKit.fetchMemberByUserId(userId), member.isActive {
            return member.displayName
        }

        return nil
    }

    func leaveCurrentHousehold(userId: String) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }

        if syncMode == .cloud {
            await setCloudScope(for: household, userId: userId)

            guard let member = try await cloudKit.fetchMemberByUserId(userId, householdId: household.id),
                  member.householdId == household.id
            else {
                throw HouseholdError.memberNotFound
            }

            let members = try await cloudKit.fetchMembers(householdId: household.id)
            let activeMembers = members.filter(\.isActive)
            switch resolveLeaveBehavior(for: member, activeMembers: activeMembers) {
            case .deleteHousehold:
                try await deleteCurrentHousehold(requestedBy: userId)
                return
            case .requireTransfer:
                throw HouseholdError.transferOwnershipRequired
            case .deactivateMembership:
                break
            }

            _ = try await cloudKit.updateMemberState(
                memberId: member.id,
                householdId: member.householdId,
                newDisplayName: member.displayName,
                newRole: member.role,
                isActive: false,
                colorHex: member.colorHex
            )
        }

        suppressRecovery(for: household.id)
        removeHouseholdFromCache(id: household.id)
        clearCurrentHousehold()
    }

    func deleteCurrentHousehold(requestedBy userId: String) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }

        guard household.ownerId == userId else {
            throw HouseholdError.notAuthorized
        }

        if syncMode == .cloud {
            await cloudKit.setHouseholdScope(.ownerPrivate)
            let deletedByZone = try await cloudKit.deleteHouseholdZoneIfCustom(id: household.id)

            if !deletedByZone {
                let members = try await cloudKit.fetchMembers(householdId: household.id)
                for member in members {
                    try await cloudKit.deleteMember(id: member.id, householdId: household.id)
                }

                let tasks = try await cloudKit.fetchTasks(householdId: household.id)
                for task in tasks {
                    try await cloudKit.deleteTask(id: task.id, householdId: household.id)
                }

                let shoppingItems = try await cloudKit.fetchShoppingItems(householdId: household.id)
                for item in shoppingItems {
                    try await cloudKit.deleteShoppingItem(id: item.id, householdId: household.id)
                }

                let backlogItems = try await cloudKit.fetchBacklogItems(householdId: household.id)
                for item in backlogItems {
                    try await cloudKit.deleteBacklogItem(id: item.id, householdId: household.id)
                }

                let categories = try await cloudKit.fetchBacklogCategories(householdId: household.id)
                for category in categories {
                    try await cloudKit.deleteBacklogCategory(id: category.id, householdId: household.id)
                }

                try await cloudKit.deleteHousehold(id: household.id)
            }

            do {
                _ = try await cloudKit.fetchHousehold(id: household.id)
                throw NSError(
                    domain: "HouseholdStore",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Household deletion could not be verified."]
                )
            } catch {
                guard isRecordMissingError(error) else { throw error }
            }
        }

        suppressRecovery(for: household.id)
        removeHouseholdFromCache(id: household.id)
        clearCurrentHousehold()
    }

    private func setCloudScope(for household: Household, userId: String) async {
        let scope: CloudKitManager.HouseholdDatabaseScope =
            household.ownerId == userId ? .ownerPrivate : .participantShared
        await cloudKit.setHouseholdScope(scope)
    }

    private func upsertMembership(
        householdId: UUID,
        userId: String,
        displayName: String,
        role: Member.MemberRole
    ) async throws {
        let normalizedKey = DisplayNameValidator.normalizedKey(displayName)
        let allMembers = try await cloudKit.fetchMembers(householdId: householdId)
        if allMembers.contains(where: {
            $0.isActive &&
                $0.userId != userId &&
                DisplayNameValidator.normalizedKey($0.displayName) == normalizedKey
        }) {
            throw HouseholdError.displayNameAlreadyTaken
        }

        if let existing = try await cloudKit.fetchMemberByUserId(userId, householdId: householdId) {
            let resolvedRole: Member.MemberRole = existing.role == .owner ? .owner : role
            let shouldUpdate =
                existing.displayName != displayName ||
                !existing.isActive ||
                existing.role != resolvedRole

            guard shouldUpdate else { return }

            _ = try await cloudKit.updateMemberState(
                memberId: existing.id,
                householdId: existing.householdId,
                newDisplayName: displayName,
                newRole: resolvedRole,
                isActive: true,
                colorHex: existing.colorHex
            )
            return
        }

        let member = Member(
            householdId: householdId,
            userId: userId,
            displayName: displayName,
            role: role,
            colorHex: MemberColorToken.randomHex()
        )
        _ = try await cloudKit.saveMember(member)
    }

    private func normalizedMembershipDisplayName(from rawDisplayName: String) -> String {
        if let validated = try? DisplayNameValidator.validate(rawDisplayName) {
            return validated
        }
        return syncMode == .localOnly ? "Guest" : "Member"
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
        currentHousehold = nil
        share = nil
        activeInviteCode = nil
        activeContainer = nil
        activeShare = nil
        _ = _Concurrency.Task { [cloudKit] in
            await cloudKit.setHouseholdScope(.participantShared)
        }
    }

    func isRecoverySuppressed(for householdId: UUID) -> Bool {
        let suppressions = loadSuppressedRecoveries(cleaningExpired: true)
        return suppressions[householdId.uuidString] != nil
    }

    // MARK: - SwiftData Helpers

    private func fetchCachedHousehold(
        userId: String,
        preferredHouseholdId: UUID?
    ) -> CachedHousehold? {
        guard let context = modelContext else { return nil }

        let descriptor = FetchDescriptor<CachedHousehold>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            let cachedHouseholds = try context.fetch(descriptor).filter { !isRecoverySuppressed(for: $0.id) }
            guard !cachedHouseholds.isEmpty else { return nil }

            if let preferredHouseholdId,
               let preferredMatch = cachedHouseholds.first(where: { $0.id == preferredHouseholdId })
            {
                return preferredMatch
            }

            if let ownerMatch = cachedHouseholds.first(where: { $0.ownerId == userId }) {
                return ownerMatch
            }

            if cachedHouseholds.count == 1 {
                return cachedHouseholds.first
            }

            return cachedHouseholds.first
        } catch {
            print("Fetch error: \(error)")
            return nil
        }
    }

    private func updateCache(with household: Household) {
        guard let context = modelContext else { return }

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
            saveContextOrSetError(context, operation: "upsert cached household")
        } catch {
            print("Cache update error: \(error)")
            self.error = error
        }
    }

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

    // MARK: - Guest Mode Data Seeding

    private func seedDefaultData(
        householdId: UUID,
        userId: String,
        displayName: String
    ) throws {
        guard let context = modelContext else {
            throw HouseholdError.cacheNotAvailable
        }

        // 1. Create owner member
        let ownerMember = Member(
            householdId: householdId,
            userId: userId,
            displayName: displayName,
            role: .owner,
            colorHex: MemberColorToken.randomHex()
        )
        context.insert(CachedMember(from: ownerMember))

        // 2. Create 8 starter tasks (3 next, 4 backlog, 1 done)
        let tasks = createStarterTasks(
            householdId: householdId,
            memberId: ownerMember.id
        )
        for task in tasks {
            context.insert(CachedTask(from: task))
        }

        // 3. Create 5 shopping items
        let items = createStarterShoppingItems(householdId: householdId)
        for item in items {
            context.insert(CachedShoppingItem(from: item))
        }

        // 4. Create backlog categories and items
        let (categories, backlogItems) = createStarterBacklog(householdId: householdId)
        for category in categories {
            context.insert(CachedBacklogCategory(from: category))
        }
        for item in backlogItems {
            context.insert(CachedBacklogItem(from: item))
        }

        // Save all
        try context.save()
    }

    private func createStarterTasks(
        householdId: UUID,
        memberId: UUID
    ) -> [Task] {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let thisWeek = Calendar.current.date(byAdding: .day, value: 5, to: today) ?? today

        return [
            // Next tasks (3 - respects WIP limit)
            Task(
                householdId: householdId,
                title: "Clean kitchen counters",
                status: .next,
                assigneeId: memberId,
                assigneeIds: [memberId],
                dueDate: today,
                taskType: .oneOff
            ),
            Task(
                householdId: householdId,
                title: "Take out trash",
                status: .next,
                assigneeId: memberId,
                assigneeIds: [memberId],
                dueDate: today,
                taskType: .oneOff
            ),
            Task(
                householdId: householdId,
                title: "Water plants",
                status: .next,
                assigneeId: memberId,
                assigneeIds: [memberId],
                dueDate: thisWeek,
                taskType: .oneOff
            ),

            // Backlog tasks (4)
            Task(
                householdId: householdId,
                title: "Vacuum living room",
                status: .backlog,
                taskType: .oneOff
            ),
            Task(
                householdId: householdId,
                title: "Clean bathroom sink",
                status: .backlog,
                taskType: .oneOff
            ),
            Task(
                householdId: householdId,
                title: "Change bed sheets",
                status: .backlog,
                taskType: .oneOff
            ),
            Task(
                householdId: householdId,
                title: "Organize pantry",
                status: .backlog,
                taskType: .oneOff
            ),

            // Done task (1 - shows completion)
            Task(
                householdId: householdId,
                title: "Wipe dining table",
                status: .done,
                assigneeId: memberId,
                assigneeIds: [memberId],
                completedAt: yesterday,
                completedById: memberId.uuidString,
                taskType: .oneOff
            ),
        ]
    }

    private func createStarterShoppingItems(householdId: UUID) -> [ShoppingItem] {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        return [
            ShoppingItem(
                householdId: householdId,
                title: "Milk",
                quantityValue: "2",
                quantityUnit: "L"
            ),
            ShoppingItem(
                householdId: householdId,
                title: "Bread",
                quantityValue: "1",
                quantityUnit: "loaf"
            ),
            ShoppingItem(
                householdId: householdId,
                title: "Dish soap",
                quantityValue: "1",
                quantityUnit: "bottle"
            ),
            ShoppingItem(
                householdId: householdId,
                title: "Paper towels",
                quantityValue: "2",
                quantityUnit: "rolls",
                isBought: true,
                boughtAt: yesterday,
                restockCount: 1
            ),
            ShoppingItem(
                householdId: householdId,
                title: "Coffee",
                quantityValue: "200",
                quantityUnit: "g"
            ),
        ]
    }

    private func createStarterBacklog(
        householdId: UUID
    ) -> (categories: [BacklogCategory], items: [BacklogItem]) {
        let homeProjectsCategory = BacklogCategory(
            householdId: householdId,
            title: "Home Projects",
            sortOrder: 0
        )

        let routineCategory = BacklogCategory(
            householdId: householdId,
            title: "Weekly Routine",
            sortOrder: 1
        )

        let items = [
            BacklogItem(
                categoryId: homeProjectsCategory.id,
                householdId: householdId,
                title: "Paint bedroom walls",
                notes: "Need to buy paint and brushes"
            ),
            BacklogItem(
                categoryId: homeProjectsCategory.id,
                householdId: householdId,
                title: "Fix leaky faucet"
            ),
            BacklogItem(
                categoryId: homeProjectsCategory.id,
                householdId: householdId,
                title: "Install new shelves in garage"
            ),
            BacklogItem(
                categoryId: routineCategory.id,
                householdId: householdId,
                title: "Deep clean bathroom"
            ),
            BacklogItem(
                categoryId: routineCategory.id,
                householdId: householdId,
                title: "Mow the lawn"
            ),
        ]

        return ([homeProjectsCategory, routineCategory], items)
    }
}

// swiftlint:enable type_body_length
