import CloudKit
import Combine
import SwiftData
import SwiftUI

@MainActor
class MemberStore: ObservableObject {
    @Published var members: [Member] = []
    @Published private(set) var hasHydratedLocalSnapshot = false
    @Published var isLoading = false
    @Published private(set) var isRefreshingInBackground = false
    @Published var error: Error?

    private var modelContext: ModelContext?
    private lazy var cloudKit = CloudKitManager.shared
    private var householdId: UUID?
    private var syncMode: SyncMode = .cloud
    private var currentUserId: String?
    private var householdOwnerId: String?
    private var activeLoadTask: _Concurrency.Task<Void, Never>?
    private var shouldReloadAfterCurrentLoad = false
    private var hasHydratedVisibleSnapshot = false

    init(householdId: UUID?, modelContext: ModelContext? = nil) {
        self.householdId = householdId
        self.modelContext = modelContext
        hydrateVisibleSnapshotFromCacheIfNeeded(force: true)
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
        hydrateVisibleSnapshotFromCacheIfNeeded(force: true)
    }

    func setHousehold(_ id: UUID?) {
        let didChangeHousehold = householdId != id
        householdId = id
        if didChangeHousehold {
            hasHydratedVisibleSnapshot = false
            hasHydratedLocalSnapshot = false
        }
        hydrateVisibleSnapshotFromCacheIfNeeded(force: didChangeHousehold || !hasHydratedVisibleSnapshot)
    }

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
    }

    func setCloudContext(currentUserId: String?, householdOwnerId: String?) {
        self.currentUserId = currentUserId
        self.householdOwnerId = householdOwnerId
    }

    private var cloudScope: CloudKitManager.HouseholdDatabaseScope {
        guard let currentUserId, let householdOwnerId else {
            return .participantShared
        }
        return currentUserId == householdOwnerId ? .ownerPrivate : .participantShared
    }

    @discardableResult
    private func saveContextOrSetError(
        _ context: ModelContext? = nil,
        operation: String = "persist member cache",
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        StoreContextSaver.saveContextOrSetError(
            context ?? modelContext,
            store: "MemberStore",
            operation: operation,
            file: file,
            line: line
        ) { [self] saveError in
            error = saveError
        }
    }

    // MARK: - Data Loading

    func loadMembersForDisplay() async {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: !hasHydratedVisibleSnapshot || members.isEmpty)
        guard syncMode == .cloud else { return }
        scheduleBackgroundRefresh()
    }

    func loadMembers() async {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: !hasHydratedVisibleSnapshot || members.isEmpty)
        guard syncMode == .cloud else { return }
        let loadTask = ensureBackgroundRefreshTask()
        await loadTask.value
    }

    private func scheduleBackgroundRefresh() {
        _ = ensureBackgroundRefreshTask()
    }

    private func ensureBackgroundRefreshTask() -> _Concurrency.Task<Void, Never> {
        if let activeLoadTask {
            shouldReloadAfterCurrentLoad = true
            return activeLoadTask
        }

        let loadTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }

            repeat {
                shouldReloadAfterCurrentLoad = false
                await performLoadMembersPass()
            } while shouldReloadAfterCurrentLoad

            activeLoadTask = nil
        }

        activeLoadTask = loadTask
        return loadTask
    }

    private func performLoadMembersPass() async {
        guard let householdId else {
            hydrateVisibleSnapshotFromCacheIfNeeded(force: true)
            return
        }

        isLoading = true
        isRefreshingInBackground = true
        defer {
            isLoading = false
            isRefreshingInBackground = false
        }

        hydrateVisibleSnapshotFromCacheIfNeeded(force: !hasHydratedVisibleSnapshot || members.isEmpty)

        guard syncMode == .cloud else { return }

        do {
            await cloudKit.ensureReady()
            let fetchedMembers = try await cloudKit.fetchMembers(
                householdId: householdId,
                scope: cloudScope
            )
            updateCache(with: fetchedMembers, for: householdId)
            members = fetchedMembers
        } catch {
            print("Error loading members: \(error)")
            self.error = error
        }
    }

    private func hydrateVisibleSnapshotFromCacheIfNeeded(force: Bool = false) {
        guard force || !hasHydratedVisibleSnapshot || members.isEmpty else { return }

        guard let householdId else {
            members = []
            hasHydratedVisibleSnapshot = true
            hasHydratedLocalSnapshot = true
            return
        }

        members = fetchCachedMembers(householdId: householdId)
        hasHydratedVisibleSnapshot = true
        hasHydratedLocalSnapshot = true
    }

    func activeMember(for userId: String?) -> Member? {
        guard let userId else { return nil }
        return members.first(where: { $0.userId == userId && $0.isActive })
    }

    // MARK: - Operations

    func updateMember(id: UUID, displayName: String, currentUserId: String?) async throws {
        let trimmedName = try DisplayNameValidator.validate(displayName)
        try assertCanEditMember(id: id, currentUserId: currentUserId)

        let normalizedKey = DisplayNameValidator.normalizedKey(trimmedName)
        if members.contains(where: {
            $0.id != id &&
                $0.isActive &&
                DisplayNameValidator.normalizedKey($0.displayName) == normalizedKey
        }) {
            throw HouseholdError.displayNameAlreadyTaken
        }

        guard let index = members.firstIndex(where: { $0.id == id }) else { return }
        var member = members[index]
        if member.displayName == trimmedName {
            return
        }

        // Optimistic Update
        let oldName = member.displayName
        member.displayName = trimmedName
        members[index] = member

        // Update Cache
        updateCachedMember(member)

        if syncMode == .cloud {
            do {
                _ = try await cloudKit.updateMemberDisplayName(
                    memberId: member.id,
                    householdId: member.householdId,
                    newDisplayName: trimmedName,
                    scope: cloudScope
                )
            } catch {
                // Revert
                member.displayName = oldName
                members[index] = member
                updateCachedMember(member)
                throw error
            }
        }
    }

    func updateCurrentUserProfile(
        displayName: String,
        colorHex: String,
        currentUserId: String?
    ) async throws {
        let trimmedName = try DisplayNameValidator.validate(displayName)
        guard let normalizedColorHex = MemberColorToken.normalize(hex: colorHex),
              MemberColorToken.isAllowed(hex: normalizedColorHex)
        else {
            throw MemberStoreError.invalidColorSelection
        }

        guard let userId = currentUserId,
              let memberId = members.first(where: { $0.userId == userId && $0.isActive })?.id
        else {
            throw MemberStoreError.profileMemberNotFound
        }

        let normalizedKey = DisplayNameValidator.normalizedKey(trimmedName)
        if members.contains(where: {
            $0.id != memberId &&
                $0.isActive &&
                DisplayNameValidator.normalizedKey($0.displayName) == normalizedKey
        }) {
            throw HouseholdError.displayNameAlreadyTaken
        }

        guard let index = members.firstIndex(where: { $0.id == memberId }) else { return }
        var member = members[index]
        if member.displayName == trimmedName, member.colorHex == normalizedColorHex {
            return
        }

        let oldName = member.displayName
        let oldColorHex = member.colorHex
        member.displayName = trimmedName
        member.colorHex = normalizedColorHex
        members[index] = member
        guard upsertCachedMember(
            member,
            operation: "persist current user profile update"
        ) else {
            member.displayName = oldName
            member.colorHex = oldColorHex
            members[index] = member
            _ = upsertCachedMember(
                member,
                operation: "rollback current user profile update"
            )
            throw MemberStoreError.profileLocalSaveFailed
        }

        NotificationCenter.default.post(name: .memberProfileDidChange, object: nil)

        guard syncMode == .cloud else { return }

        let remoteMemberId = member.id
        let remoteHouseholdId = member.householdId
        let scope = cloudScope
        _ = _Concurrency.Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                _ = try await cloudKit.updateMemberProfile(
                    memberId: remoteMemberId,
                    householdId: remoteHouseholdId,
                    newDisplayName: trimmedName,
                    newColorHex: normalizedColorHex,
                    scope: scope
                )
            } catch {
                await MainActor.run {
                    self.error = error
                }
            }
        }
    }

    func updateRole(id: UUID, newRole: Member.MemberRole, currentUserId: String?) async throws {
        try assertOwnerPermissions(currentUserId: currentUserId)
        guard let index = members.firstIndex(where: { $0.id == id }) else { return }
        let member = members[index]

        if isCurrentUserMember(member, currentUserId: currentUserId), newRole != .owner {
            throw MemberStoreError.transferOwnershipRequired
        }

        if member.role == .owner, newRole != .owner, activeOwnersCount <= 1 {
            throw MemberStoreError.lastOwnerRequired
        }

        // Optimistic
        // Since 'role' is let in Member struct (immutable), we need to create a new Member
        let updatedMember = Member(
            id: member.id,
            householdId: member.householdId,
            userId: member.userId,
            displayName: member.displayName,
            role: newRole,
            joinedAt: member.joinedAt,
            isActive: member.isActive,
            colorHex: member.colorHex
        )

        members[index] = updatedMember
        updateCachedMember(updatedMember)

        if syncMode == .cloud {
            do {
                _ = try await cloudKit.updateMemberRole(
                    memberId: updatedMember.id,
                    householdId: updatedMember.householdId,
                    newRole: updatedMember.role,
                    scope: cloudScope
                )
            } catch {
                members[index] = member // revert
                updateCachedMember(member)
                throw error
            }
        }
    }

    func deleteMember(id: UUID, currentUserId: String?) async throws {
        try assertOwnerPermissions(currentUserId: currentUserId)
        guard let index = members.firstIndex(where: { $0.id == id }) else { return }
        let member = members[index]

        if isCurrentUserMember(member, currentUserId: currentUserId) {
            throw MemberStoreError.cannotRemoveSelf
        }
        if member.role == .owner, activeOwnersCount <= 1 {
            throw MemberStoreError.lastOwnerRequired
        }

        // Optimistic
        members.remove(at: index)
        deleteCachedMember(id: id)

        if syncMode == .cloud {
            do {
                try await cloudKit.deleteMember(
                    id: id,
                    householdId: member.householdId,
                    scope: cloudScope
                )
            } catch {
                // Revert
                members.insert(member, at: index)
                updateCachedMember(member)
                throw error
            }
        }
    }

    // MARK: - SwiftData Helpers

    private func fetchCachedMembers(householdId: UUID) -> [Member] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedMember>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.joinedAt)]
        )

        do {
            let cachedMembers = try context.fetch(descriptor)
            var didMigrate = false
            let resolvedMembers = cachedMembers.map { cached -> Member in
                let resolvedColor: String = if let normalized = MemberColorToken.normalize(hex: cached.colorHex),
                                               MemberColorToken.isAllowed(hex: normalized)
                {
                    normalized
                } else {
                    MemberColorToken.migratedHex(for: cached.id)
                }

                if cached.colorHex != resolvedColor {
                    cached.colorHex = resolvedColor
                    didMigrate = true
                }
                return cached.toMember()
            }

            if didMigrate {
                saveContextOrSetError(context, operation: "migrate cached member colors")
            }

            return resolvedMembers
        } catch {
            print("Cache fetch error: \(error)")
            return []
        }
    }

    private func updateCache(with members: [Member], for _: UUID) {
        guard modelContext != nil else { return }

        // Simple strategy: Delete all for household and regarding (inefficient but safe for now)
        // Better: diffing. For now, let's just update existing and add new.

        for member in members {
            updateCachedMember(member)
        }

        // TODO: Handle deletions (members in cache but not in fetch)
    }

    private func updateCachedMember(_ member: Member) {
        _ = upsertCachedMember(member, operation: "upsert cached member")
    }

    @discardableResult
    private func upsertCachedMember(_ member: Member, operation: String) -> Bool {
        guard let context = modelContext else { return false }

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
            return saveContextOrSetError(context, operation: operation)
        } catch {
            print("Cache save error: \(error)")
            self.error = error
            return false
        }
    }

    private func deleteCachedMember(id: UUID) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<CachedMember>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            if let cached = try context.fetch(descriptor).first {
                context.delete(cached)
                saveContextOrSetError(context, operation: "delete cached member")
            }
        } catch {
            print("Cache delete error: \(error)")
            self.error = error
        }
    }

    // MARK: - Permissions

    private func assertOwnerPermissions(currentUserId: String?) throws {
        guard let userId = currentUserId,
              let currentMember = members.first(where: { $0.userId == userId }),
              currentMember.role == .owner
        else {
            throw MemberStoreError.ownerPermissionsRequired
        }
    }

    private func assertCanEditMember(id: UUID, currentUserId: String?) throws {
        guard let userId = currentUserId,
              let currentMember = members.first(where: { $0.userId == userId })
        else {
            throw MemberStoreError.ownerPermissionsRequired
        }

        if currentMember.role == .owner {
            return
        }

        guard currentMember.id == id else {
            throw MemberStoreError.ownerPermissionsRequired
        }
    }

    private func isCurrentUserMember(_ member: Member, currentUserId: String?) -> Bool {
        guard let currentUserId else { return false }
        return member.userId == currentUserId
    }

    private var activeOwnersCount: Int {
        members.filter { $0.isActive && $0.role == .owner }.count
    }
}

enum MemberStoreError: LocalizedError, Equatable {
    case ownerPermissionsRequired
    case transferOwnershipRequired
    case cannotRemoveSelf
    case lastOwnerRequired
    case invalidColorSelection
    case profileMemberNotFound
    case profileLocalSaveFailed

    var errorDescription: String? {
        switch self {
        case .ownerPermissionsRequired:
            "Only household owners can manage member roles."
        case .transferOwnershipRequired:
            "Transfer ownership before changing your own owner role."
        case .cannotRemoveSelf:
            "You cannot remove yourself from members management."
        case .lastOwnerRequired:
            "The household must keep at least one owner."
        case .invalidColorSelection:
            "Choose one of the available profile colors."
        case .profileMemberNotFound:
            "Couldn't find your member profile in this household."
        case .profileLocalSaveFailed:
            "Couldn't save your profile locally right now."
        }
    }
}
