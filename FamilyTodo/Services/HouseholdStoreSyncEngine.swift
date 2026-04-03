import CloudKit
import Foundation
import UIKit

@MainActor
protocol HouseholdRemoteSyncDataSource: AnyObject {
    var remoteSyncMode: SyncMode { get }

    func recordRemoteSyncError(_ error: Error)
    func emptyHouseholdSyncPassResult(
        reason: HouseholdSyncReason,
        direction: HouseholdSyncDirection,
        triggerReceivedAt: Date,
        syncStartedAt: Date,
        syncFinishedAt: Date,
        fetchResult: UIBackgroundFetchResult
    ) -> HouseholdSyncPassResult
    func makeRemoteSyncBaseline(
        userId: String,
        preferredHouseholdId: UUID?,
        context: RemoteCloudChangeContext
    ) -> RemoteSyncBaseline
    func refreshCurrentHouseholdForRemoteCloudChange(
        userId: String,
        preferredHouseholdId: UUID?,
        reason: HouseholdSyncReason,
        context: RemoteCloudChangeContext
    ) async throws -> HouseholdStore.JoinedHouseholdHydrationSnapshot?
    func processRemoteVisibleContentChangeIfNeeded(
        beforeSnapshot: HouseholdStore.RemoteCloudRefreshSnapshot,
        beforeVisibleContentSnapshot: RemoteVisibleContentSnapshot?,
        userId: String,
        context: RemoteCloudChangeContext
    ) async -> RemoteVisibleContentResolution?
    func buildRemoteSyncPassResult(
        userId: String,
        preferredHouseholdId: UUID?,
        context: RemoteSyncPassBuildContext
    ) -> HouseholdSyncPassResult
}

@MainActor
struct HouseholdRemoteSyncExecutor {
    private let dataSource: HouseholdRemoteSyncDataSource

    init(dataSource: HouseholdRemoteSyncDataSource) {
        self.dataSource = dataSource
    }

    func execute(
        userId: String?,
        preferredHouseholdId: UUID?,
        reason: HouseholdSyncReason,
        context: RemoteCloudChangeContext = .unknown
    ) async -> HouseholdSyncPassResult {
        let refreshStartedAt = Date()
        let triggerReceivedAt = remoteSyncTriggerReceivedAt(
            from: context,
            refreshStartedAt: refreshStartedAt
        )

        guard dataSource.remoteSyncMode == .cloud else {
            print("[RemoteSync] Ignoring remote push because sync mode is local-only.")
            return dataSource.emptyHouseholdSyncPassResult(
                reason: reason,
                direction: .unknown,
                triggerReceivedAt: triggerReceivedAt,
                syncStartedAt: refreshStartedAt,
                syncFinishedAt: Date(),
                fetchResult: .noData
            )
        }

        guard let userId else {
            print("[RemoteSync] Ignoring remote push because there is no active cloud user.")
            return dataSource.emptyHouseholdSyncPassResult(
                reason: reason,
                direction: .unknown,
                triggerReceivedAt: triggerReceivedAt,
                syncStartedAt: refreshStartedAt,
                syncFinishedAt: Date(),
                fetchResult: .noData
            )
        }

        let syncBaseline = dataSource.makeRemoteSyncBaseline(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId,
            context: context
        )
        print(
            "[RemoteSync] Starting background household refresh. before=\(describeRemoteCloudRefreshSnapshot(syncBaseline.beforeSnapshot))"
        )

        let refreshedHydrationSnapshot: HouseholdStore.JoinedHouseholdHydrationSnapshot?
        do {
            refreshedHydrationSnapshot = try await dataSource.refreshCurrentHouseholdForRemoteCloudChange(
                userId: userId,
                preferredHouseholdId: preferredHouseholdId,
                reason: reason,
                context: context
            ) ?? syncBaseline.beforeSnapshot.hydrationSnapshot
        } catch {
            dataSource.recordRemoteSyncError(error)
            print("[RemoteSync] Hydration pass failed: \(error)")
            return dataSource.emptyHouseholdSyncPassResult(
                reason: reason,
                direction: syncBaseline.direction,
                triggerReceivedAt: triggerReceivedAt,
                syncStartedAt: refreshStartedAt,
                syncFinishedAt: Date(),
                fetchResult: .failed
            )
        }

        let visibleContentResolution = await dataSource.processRemoteVisibleContentChangeIfNeeded(
            beforeSnapshot: syncBaseline.beforeSnapshot,
            beforeVisibleContentSnapshot: syncBaseline.beforeVisibleContentSnapshot,
            userId: userId,
            context: context
        )

        let buildContext = RemoteSyncPassBuildContext(
            reason: reason,
            cloudContext: context,
            triggerReceivedAt: triggerReceivedAt,
            refreshStartedAt: refreshStartedAt,
            baseline: syncBaseline,
            refreshedHydrationSnapshot: refreshedHydrationSnapshot,
            visibleContentResolution: visibleContentResolution
        )

        return dataSource.buildRemoteSyncPassResult(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId,
            context: buildContext
        )
    }

    private func remoteSyncTriggerReceivedAt(
        from context: RemoteCloudChangeContext,
        refreshStartedAt: Date
    ) -> Date {
        context.receivedAt == .distantPast ? refreshStartedAt : context.receivedAt
    }

    private func describeRemoteCloudRefreshSnapshot(
        _ snapshot: HouseholdStore.RemoteCloudRefreshSnapshot
    ) -> String {
        let name = snapshot.householdName ?? "nil"
        let icon = snapshot.householdIconSymbol ?? "nil"
        let householdId = snapshot.observedHouseholdId?.uuidString ?? "nil"
        let hydrationSummary = if let hydrationSnapshot = snapshot.hydrationSnapshot {
            "members=\(hydrationSnapshot.activeMemberCount),tasks=\(hydrationSnapshot.taskCount),ideas=\(hydrationSnapshot.ideaCount),shopping=\(hydrationSnapshot.shoppingItemCount),bundles=\(hydrationSnapshot.bundleCount)"
        } else {
            "hydration=nil"
        }
        return "householdId=\(householdId) name=\(name) icon=\(icon) \(hydrationSummary)"
    }
}

@MainActor
final class HouseholdStoreSyncEngine: HouseholdSyncEngine {
    private unowned let store: HouseholdStore
    private let userIdProvider: @MainActor () -> String?
    private let preferredHouseholdIdProvider: @MainActor () -> UUID?
    private lazy var executor = HouseholdRemoteSyncExecutor(dataSource: store)

    init(
        store: HouseholdStore,
        userIdProvider: @escaping @MainActor () -> String?,
        preferredHouseholdIdProvider: @escaping @MainActor () -> UUID?
    ) {
        self.store = store
        self.userIdProvider = userIdProvider
        self.preferredHouseholdIdProvider = preferredHouseholdIdProvider
    }

    func runSync(for reason: HouseholdSyncReason) async -> HouseholdSyncPassResult {
        let context: RemoteCloudChangeContext = switch reason {
        case let .remotePush(remoteContext):
            remoteCloudChangeContext(from: remoteContext)
        default:
            .unknown
        }

        CloudKitDiagnosticsState.shared.recordProgress(
            operation: "sync.engine.context reason=\(schedulerReasonLabel(reason)) databaseScope=\(databaseScopeLabel(context.databaseScope)) notificationType=\(context.notificationType.rawValue)"
        )

        return await executor.execute(
            userId: userIdProvider(),
            preferredHouseholdId: preferredHouseholdIdProvider(),
            reason: reason,
            context: context
        )
    }

    private func remoteCloudChangeContext(
        from context: HouseholdSyncRemoteContext
    ) -> RemoteCloudChangeContext {
        let scope: CKDatabase.Scope? = switch context {
        case .sharedDatabase:
            .shared
        case .privateDatabase:
            .private
        case .unknown:
            nil
        }

        return RemoteCloudChangeContext(
            databaseScope: scope,
            notificationType: .database,
            receivedAt: Date()
        )
    }

    private func schedulerReasonLabel(_ reason: HouseholdSyncReason) -> String {
        switch reason {
        case let .remotePush(context):
            switch context {
            case .sharedDatabase:
                "remotePushShared"
            case .privateDatabase:
                "remotePushPrivate"
            case .unknown:
                "remotePushUnknown"
            }
        case .foregroundRepairWindow:
            "foregroundRepairWindow"
        case .appBecameActive:
            "appBecameActive"
        case .manualRefresh:
            "manualRefresh"
        case .localMutationFollowUp:
            "localMutationFollowUp"
        case .householdJoined:
            "householdJoined"
        case .householdSwitched:
            "householdSwitched"
        case .debugRepair:
            "debugRepair"
        }
    }

    private func databaseScopeLabel(_ scope: CKDatabase.Scope?) -> String {
        guard let scope else { return "nil" }
        return switch scope {
        case .private:
            "private"
        case .public:
            "public"
        case .shared:
            "shared"
        @unknown default:
            "unknown"
        }
    }
}
