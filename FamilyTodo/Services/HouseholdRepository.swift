import Foundation

actor HouseholdRepository {
    private let cloud: any HouseholdCloudSyncing

    init(cloud: any HouseholdCloudSyncing) {
        self.cloud = cloud
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

    private func prepareCloud(for context: HouseholdSyncContext) async throws {
        await cloud.ensureReady()
        await cloud.setHouseholdScope(context.scope)
    }
}
