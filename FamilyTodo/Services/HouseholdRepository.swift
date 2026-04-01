import CloudKit
import Foundation

struct HouseholdScopedMembership {
    let member: Member
    let scope: CloudKitManager.HouseholdDatabaseScope
}

struct HouseholdRecoveryCandidate {
    let membership: HouseholdScopedMembership
    let household: Household?
}

actor HouseholdRepository {
    private let cloud: any HouseholdCloudSyncing
    private let zoneResolver: HouseholdZoneResolver

    init(cloud: any HouseholdCloudSyncing) {
        self.cloud = cloud
        zoneResolver = HouseholdZoneResolver(cloud: cloud)
    }

    func loadCloudSnapshot(
        for context: HouseholdSyncContext
    ) async throws -> HouseholdCloudSnapshot {
        await recordSnapshotProgress(
            "snapshot.load.started scope=\(scopeLabel(context.scope)) householdId=\(context.householdId.uuidString)"
        )
        do {
            try await prepareCloud(for: context)
            let snapshot = try await HouseholdCloudSnapshotLoader(cloud: cloud).loadSnapshot(
                householdId: context.householdId,
                scope: context.scope
            )
            await recordSnapshotProgress(
                "snapshot.load.completed scope=\(scopeLabel(context.scope)) householdId=\(context.householdId.uuidString) members=\(snapshot.members.count) shopping=\(snapshot.shoppingItems.count) bundles=\(snapshot.shoppingBundles.count) workItems=\(snapshot.unifiedWorkItems.count) categories=\(snapshot.backlogCategories.count) backlogItems=\(snapshot.backlogItems.count)"
            )
            return snapshot
        } catch {
            await recordSnapshotProgress(
                "snapshot.load.failed scope=\(scopeLabel(context.scope)) householdId=\(context.householdId.uuidString) error=\(String(describing: error))"
            )
            throw error
        }
    }

    func hasActiveMembership(
        userId: String,
        in context: HouseholdSyncContext
    ) async throws -> Bool {
        try await prepareCloud(for: context)
        return try await cloud.fetchMemberByUserId(
            userId,
            householdId: context.householdId,
            scope: context.scope
        )?.isActive ?? false
    }

    func fetchActiveScopedMemberships(
        userId: String,
        householdId: UUID? = nil
    ) async throws -> [HouseholdScopedMembership] {
        let participantMembers = try await fetchActiveMembers(
            userId: userId,
            householdId: householdId,
            scope: .participantShared
        )
        let ownerMembers = try await fetchActiveMembers(
            userId: userId,
            householdId: householdId,
            scope: .ownerPrivate
        )

        return participantMembers.map {
            HouseholdScopedMembership(member: $0, scope: .participantShared)
        } + ownerMembers.map {
            HouseholdScopedMembership(member: $0, scope: .ownerPrivate)
        }
    }

    func fetchRecoverableCandidates(
        userId: String,
        householdId: UUID? = nil
    ) async throws -> [HouseholdRecoveryCandidate] {
        let participantMembers = try await fetchActiveMembersForRecovery(
            userId: userId,
            householdId: householdId,
            scope: .participantShared
        )
        let ownerMembers = try await fetchActiveMembersForRecovery(
            userId: userId,
            householdId: householdId,
            scope: .ownerPrivate
        )
        let memberships = participantMembers.map {
            HouseholdScopedMembership(member: $0, scope: .participantShared)
        } + ownerMembers.map {
            HouseholdScopedMembership(member: $0, scope: .ownerPrivate)
        }

        var candidates: [HouseholdRecoveryCandidate] = []
        candidates.reserveCapacity(memberships.count)

        for membership in memberships {
            let household = try await fetchRecoverableHousehold(for: membership)
            candidates.append(
                HouseholdRecoveryCandidate(
                    membership: membership,
                    household: household
                )
            )
        }

        return candidates
    }

    func fetchHousehold(
        for membership: HouseholdScopedMembership
    ) async throws -> Household {
        _ = try await zoneResolver.prepare(
            householdId: membership.member.householdId,
            scope: membership.scope
        )
        return try await cloud.fetchHousehold(
            id: membership.member.householdId,
            scope: membership.scope
        )
    }

    func cleanupStaleRecoverableMembership(
        _ membership: HouseholdScopedMembership
    ) async throws {
        await cloud.clearAllCachedZones(for: membership.member.householdId)

        do {
            _ = try await cloud.updateMemberState(
                memberId: membership.member.id,
                householdId: membership.member.householdId,
                newDisplayName: membership.member.displayName,
                newRole: membership.member.role,
                isActive: false,
                colorHex: membership.member.colorHex,
                scope: membership.scope
            )
        } catch {
            guard !isRecordMissingError(error) else {
                return
            }
            throw error
        }
    }

    private func fetchActiveMembers(
        userId: String,
        householdId: UUID?,
        scope: CloudKitManager.HouseholdDatabaseScope
    ) async throws -> [Member] {
        _ = try await zoneResolver.prepare(householdId: householdId, scope: scope)
        return try await cloud.fetchActiveMembersByUserId(
            userId,
            householdId: householdId,
            scope: scope
        )
    }

    private func fetchRecoverableHousehold(
        for membership: HouseholdScopedMembership
    ) async throws -> Household? {
        do {
            return try await fetchHousehold(for: membership)
        } catch {
            guard isRecordMissingError(error) else {
                throw error
            }
            return nil
        }
    }

    private func fetchActiveMembersForRecovery(
        userId: String,
        householdId: UUID?,
        scope: CloudKitManager.HouseholdDatabaseScope
    ) async throws -> [Member] {
        do {
            return try await fetchActiveMembers(
                userId: userId,
                householdId: householdId,
                scope: scope
            )
        } catch {
            guard shouldTreatMissingRecoveryMembershipsAsEmpty(
                error,
                householdId: householdId,
                scope: scope
            ) else {
                throw error
            }
            return []
        }
    }

    private func prepareCloud(for context: HouseholdSyncContext) async throws {
        _ = try await zoneResolver.resolveZone(for: context)
    }

    private func recordSnapshotProgress(_ operation: String) async {
        await MainActor.run {
            CloudKitDiagnosticsState.shared.recordProgress(operation: operation)
        }
    }

    private func scopeLabel(_ scope: CloudKitManager.HouseholdDatabaseScope) -> String {
        switch scope {
        case .ownerPrivate:
            "ownerPrivate"
        case .participantShared:
            "participantShared"
        }
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

    private func shouldTreatMissingRecoveryMembershipsAsEmpty(
        _ error: Error,
        householdId: UUID?,
        scope: CloudKitManager.HouseholdDatabaseScope
    ) -> Bool {
        guard scope == .participantShared, householdId != nil else {
            return false
        }

        if let ckError = error as? CKError {
            switch ckError.code {
            case .zoneNotFound, .permissionFailure, .unknownItem:
                return true
            default:
                return false
            }
        }

        if let managerError = error as? CloudKitManager.CloudKitManagerError,
           case let .unknownError(underlying) = managerError
        {
            return shouldTreatMissingRecoveryMembershipsAsEmpty(
                underlying,
                householdId: householdId,
                scope: scope
            )
        }

        return false
    }
}
