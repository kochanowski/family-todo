import CloudKit
import Foundation

actor HouseholdZoneResolver {
    private let cloud: any HouseholdCloudSyncing

    init(cloud: any HouseholdCloudSyncing) {
        self.cloud = cloud
    }

    func resolveZone(
        for context: HouseholdSyncContext
    ) async throws -> CKRecordZone.ID? {
        await cloud.ensureReady()
        await cloud.setHouseholdScope(context.scope)

        switch context.role {
        case .owner:
            return try await cloud.ensureHouseholdOwnerZone(householdId: context.householdId)
        case .participant:
            return try await cloud.resolveSubscriptionZone(
                householdId: context.householdId,
                scope: context.scope
            )
        }
    }
}
