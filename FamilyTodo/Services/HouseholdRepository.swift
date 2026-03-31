import Foundation

struct HouseholdScopedMembership {
    let member: Member
    let scope: CloudKitManager.HouseholdDatabaseScope
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
        try await prepareCloud(for: context)
        return try await HouseholdCloudSnapshotLoader(cloud: cloud).loadSnapshot(
            householdId: context.householdId,
            scope: context.scope
        )
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

    private func prepareCloud(for context: HouseholdSyncContext) async throws {
        _ = try await zoneResolver.resolveZone(for: context)
    }
}
