import CloudKit
import Foundation
@testable import HousePulse
import UIKit
import XCTest

@MainActor
final class HouseholdStoreSyncEngineTests: XCTestCase {
    func testRemoteSyncExecutorRunsRemoteSyncPipeline() async {
        let householdId = UUID()
        let beforeSnapshot = HouseholdStore.RemoteCloudRefreshSnapshot(
            currentHouseholdId: householdId,
            observedHouseholdId: householdId,
            householdName: "Before",
            householdIconSymbol: "house.fill",
            hydrationSnapshot: nil
        )
        let baseline = RemoteSyncBaseline(
            beforeSnapshot: beforeSnapshot,
            beforeVisibleContentSnapshot: nil,
            direction: .ownerToParticipant
        )
        let refreshedSnapshot = HouseholdStore.JoinedHouseholdHydrationSnapshot(
            activeMemberCount: 2,
            currentUserHasCachedMembership: true,
            remoteMembershipConfirmed: true,
            taskCount: 1,
            ideaCount: 1,
            categoryCount: 1,
            shoppingItemCount: 3,
            bundleCount: 1
        )
        let visibleResolution = RemoteVisibleContentResolution(
            snapshot: RemoteVisibleContentSnapshot(
                shoppingItemsByID: [:],
                shoppingBundlesByID: [:],
                workItemsByID: [:],
                backlogCategoriesByID: [:]
            ),
            diff: RemoteVisibleContentDiff(
                addedMemberIDs: [],
                removedMemberIDs: [],
                changedMemberIDs: [],
                addedShoppingItemIDs: [],
                addedShoppingTitles: [],
                addedShoppingBundleIDs: [],
                addedTaskIDs: [],
                addedIdeaIDs: [],
                addedBacklogCategoryIDs: [],
                removedShoppingItemIDs: [],
                removedShoppingBundleIDs: [],
                removedTaskIDs: [],
                removedIdeaIDs: [],
                removedBacklogCategoryIDs: [],
                changedShoppingItemIDs: [],
                changedShoppingBundleIDs: [],
                changedWorkItemIDs: [],
                changedTaskIDs: [],
                changedIdeaIDs: [],
                changedBacklogCategoryIDs: []
            ),
            followUpPassCount: 2,
            cacheUpdatedAt: Date(timeIntervalSince1970: 123)
        )
        let expectedResult = HouseholdSyncPassResult(
            fetchResult: .newData,
            events: [],
            diagnostics: HouseholdSyncDiagnostics(
                batchID: UUID(),
                reason: .remotePush(context: .sharedDatabase),
                direction: .ownerToParticipant,
                triggerReceivedAt: Date(timeIntervalSince1970: 100),
                syncStartedAt: Date(timeIntervalSince1970: 101),
                syncFinishedAt: Date(timeIntervalSince1970: 123),
                changedDomains: [],
                changedIDsByDomain: [:],
                activeMemberCount: 2
            )
        )
        let dataSource = FakeHouseholdRemoteSyncDataSource(
            syncMode: .cloud,
            baseline: baseline,
            refreshedHydrationSnapshot: refreshedSnapshot,
            visibleContentResolution: visibleResolution,
            buildResult: expectedResult
        )
        let executor = HouseholdRemoteSyncExecutor(dataSource: dataSource)

        let result = await executor.execute(
            userId: "user-1",
            preferredHouseholdId: householdId,
            reason: .remotePush(context: .sharedDatabase),
            context: RemoteCloudChangeContext(
                databaseScope: .shared,
                notificationType: .database,
                receivedAt: Date(timeIntervalSince1970: 100)
            )
        )

        XCTAssertEqual(result, expectedResult)
        XCTAssertEqual(
            dataSource.recordedCalls,
            [
                "baseline",
                "refresh",
                "visibleChange",
                "build",
            ]
        )
    }

    func testRemoteSyncExecutorReturnsFailedResultWhenRefreshThrows() async {
        let householdId = UUID()
        let beforeSnapshot = HouseholdStore.RemoteCloudRefreshSnapshot(
            currentHouseholdId: householdId,
            observedHouseholdId: householdId,
            householdName: "Before",
            householdIconSymbol: "house.fill",
            hydrationSnapshot: nil
        )
        let baseline = RemoteSyncBaseline(
            beforeSnapshot: beforeSnapshot,
            beforeVisibleContentSnapshot: nil,
            direction: .participantToOwner
        )
        let expectedError = TestSyncError.refreshFailed
        let dataSource = FakeHouseholdRemoteSyncDataSource(
            syncMode: .cloud,
            baseline: baseline,
            refreshError: expectedError
        )
        let executor = HouseholdRemoteSyncExecutor(dataSource: dataSource)

        let result = await executor.execute(
            userId: "user-1",
            preferredHouseholdId: householdId,
            reason: .remotePush(context: .privateDatabase),
            context: RemoteCloudChangeContext(
                databaseScope: .private,
                notificationType: .database,
                receivedAt: Date(timeIntervalSince1970: 200)
            )
        )

        XCTAssertEqual(result.fetchResult, .failed)
        XCTAssertEqual(dataSource.recordedCalls, ["baseline", "refresh", "empty"])
        XCTAssertEqual(dataSource.recordedError as? TestSyncError, expectedError)
    }

    func testRemoteCloudChangeContextResolverInfersPrivateScopeForOwnerRecordZonePushWithoutDeclaredScope() {
        let householdId = UUID()
        let resolver = RemoteCloudChangeContextResolver {
            HouseholdSyncContext(
                householdId: householdId,
                currentUserId: "owner-1",
                ownerUserId: "owner-1",
                role: .owner,
                scope: .ownerPrivate
            )
        }

        let resolvedScope = resolver.resolveDatabaseScope(
            declaredScope: nil,
            notificationType: .recordZone
        )

        XCTAssertEqual(resolvedScope, .private)
    }

    func testRemoteCloudChangeContextResolverInfersSharedScopeForParticipantRecordZonePushWithoutDeclaredScope() {
        let householdId = UUID()
        let resolver = RemoteCloudChangeContextResolver {
            HouseholdSyncContext(
                householdId: householdId,
                currentUserId: "member-2",
                ownerUserId: "owner-1",
                role: .participant,
                scope: .participantShared
            )
        }

        let resolvedScope = resolver.resolveDatabaseScope(
            declaredScope: nil,
            notificationType: .recordZone
        )

        XCTAssertEqual(resolvedScope, .shared)
    }

    func testRemoteCloudChangeContextResolverKeepsDeclaredScopeAuthoritative() {
        let householdId = UUID()
        let resolver = RemoteCloudChangeContextResolver {
            HouseholdSyncContext(
                householdId: householdId,
                currentUserId: "owner-1",
                ownerUserId: "owner-1",
                role: .owner,
                scope: .ownerPrivate
            )
        }

        let resolvedScope = resolver.resolveDatabaseScope(
            declaredScope: .shared,
            notificationType: .recordZone
        )

        XCTAssertEqual(resolvedScope, .shared)
    }
}

@MainActor
private final class FakeHouseholdRemoteSyncDataSource: HouseholdRemoteSyncDataSource {
    let syncMode: SyncMode
    let baseline: RemoteSyncBaseline
    let refreshedHydrationSnapshot: HouseholdStore.JoinedHouseholdHydrationSnapshot?
    let visibleContentResolution: RemoteVisibleContentResolution?
    let buildResult: HouseholdSyncPassResult
    let refreshError: Error?

    private(set) var recordedCalls: [String] = []
    private(set) var recordedError: Error?

    init(
        syncMode: SyncMode,
        baseline: RemoteSyncBaseline,
        refreshedHydrationSnapshot: HouseholdStore.JoinedHouseholdHydrationSnapshot? = nil,
        visibleContentResolution: RemoteVisibleContentResolution? = nil,
        buildResult: HouseholdSyncPassResult = HouseholdSyncPassResult(
            fetchResult: .noData,
            events: [],
            diagnostics: HouseholdSyncDiagnostics(
                batchID: UUID(),
                reason: .manualRefresh,
                direction: .unknown,
                triggerReceivedAt: Date(timeIntervalSince1970: 0),
                syncStartedAt: Date(timeIntervalSince1970: 0),
                syncFinishedAt: Date(timeIntervalSince1970: 0),
                changedDomains: [],
                changedIDsByDomain: [:]
            )
        ),
        refreshError: Error? = nil
    ) {
        self.syncMode = syncMode
        self.baseline = baseline
        self.refreshedHydrationSnapshot = refreshedHydrationSnapshot
        self.visibleContentResolution = visibleContentResolution
        self.buildResult = buildResult
        self.refreshError = refreshError
    }

    var remoteSyncMode: SyncMode {
        syncMode
    }

    func makeRemoteSyncBaseline(
        userId _: String,
        preferredHouseholdId _: UUID?,
        context _: RemoteCloudChangeContext
    ) -> RemoteSyncBaseline {
        recordedCalls.append("baseline")
        return baseline
    }

    func refreshCurrentHouseholdForRemoteCloudChange(
        userId _: String,
        preferredHouseholdId _: UUID?,
        reason _: HouseholdSyncReason,
        context _: RemoteCloudChangeContext
    ) async throws -> HouseholdStore.JoinedHouseholdHydrationSnapshot? {
        recordedCalls.append("refresh")
        if let refreshError {
            throw refreshError
        }
        return refreshedHydrationSnapshot
    }

    func processRemoteVisibleContentChangeIfNeeded(
        beforeSnapshot _: HouseholdStore.RemoteCloudRefreshSnapshot,
        beforeVisibleContentSnapshot _: RemoteVisibleContentSnapshot?,
        userId _: String,
        context _: RemoteCloudChangeContext
    ) async -> RemoteVisibleContentResolution? {
        recordedCalls.append("visibleChange")
        return visibleContentResolution
    }

    func buildRemoteSyncPassResult(
        userId _: String,
        preferredHouseholdId _: UUID?,
        context _: RemoteSyncPassBuildContext
    ) -> HouseholdSyncPassResult {
        recordedCalls.append("build")
        return buildResult
    }

    func emptyHouseholdSyncPassResult(
        reason: HouseholdSyncReason,
        direction: HouseholdSyncDirection,
        triggerReceivedAt: Date,
        syncStartedAt: Date,
        syncFinishedAt: Date,
        fetchResult: UIBackgroundFetchResult
    ) -> HouseholdSyncPassResult {
        recordedCalls.append("empty")
        return HouseholdSyncPassResult(
            fetchResult: fetchResult,
            events: [],
            diagnostics: HouseholdSyncDiagnostics(
                batchID: UUID(),
                reason: reason,
                direction: direction,
                triggerReceivedAt: triggerReceivedAt,
                syncStartedAt: syncStartedAt,
                syncFinishedAt: syncFinishedAt,
                changedDomains: [],
                changedIDsByDomain: [:]
            )
        )
    }

    func recordRemoteSyncError(_ error: Error) {
        recordedError = error
    }
}

private enum TestSyncError: Error, Equatable {
    case refreshFailed
}
