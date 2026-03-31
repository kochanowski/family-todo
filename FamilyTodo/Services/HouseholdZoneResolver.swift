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
        try await prepare(
            householdId: context.householdId,
            scope: context.scope,
            role: context.role
        )
    }

    func prepare(
        householdId: UUID?,
        scope: CloudKitManager.HouseholdDatabaseScope
    ) async throws -> CKRecordZone.ID? {
        try await prepare(
            householdId: householdId,
            scope: scope,
            role: inferredRole(for: scope)
        )
    }

    private func prepare(
        householdId: UUID?,
        scope: CloudKitManager.HouseholdDatabaseScope,
        role: HouseholdSyncRole
    ) async throws -> CKRecordZone.ID? {
        await cloud.ensureReady()
        await cloud.setHouseholdScope(scope)

        guard let householdId else {
            return nil
        }

        switch role {
        case .owner:
            return try await cloud.ensureHouseholdOwnerZone(householdId: householdId)
        case .participant:
            return try await cloud.resolveSubscriptionZone(
                householdId: householdId,
                scope: scope
            )
        }
    }

    private func inferredRole(
        for scope: CloudKitManager.HouseholdDatabaseScope
    ) -> HouseholdSyncRole {
        switch scope {
        case .ownerPrivate:
            .owner
        case .participantShared:
            .participant
        }
    }
}
