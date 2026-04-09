import Foundation
@testable import HousePulse
import UIKit
import XCTest

@MainActor
final class HouseholdSyncCoordinatorLifecycleTests: XCTestCase {
    func testPerformHouseholdLifecycleSyncUsesJoinedForFirstSelectionAndDedupesSameHousehold() async {
        let householdId = UUID()
        let engine = LifecycleFakeHouseholdSyncEngine(
            results: [
                makeLifecycleNoDataPassResult(
                    reason: .householdJoined,
                    direction: .unknown,
                    syncRole: .owner,
                    syncScope: .ownerPrivate,
                    timelineStart: 99,
                    activeMemberCount: 1
                ),
            ]
        )
        let coordinator = HouseholdSyncCoordinator(engine: engine)

        let firstResult = await coordinator.performHouseholdLifecycleSyncIfNeeded(
            currentHouseholdID: householdId
        )
        let secondResult = await coordinator.performHouseholdLifecycleSyncIfNeeded(
            currentHouseholdID: householdId
        )

        XCTAssertEqual(firstResult, .noData)
        XCTAssertEqual(secondResult, .noData)
        XCTAssertEqual(engine.recordedReasons, [.householdJoined])
        XCTAssertEqual(coordinator.lastDiagnostics?.reason, .householdJoined)
    }

    func testPerformHouseholdLifecycleSyncUsesSwitchedAndResetsAfterClearingSelection() async {
        let firstHouseholdId = UUID()
        let secondHouseholdId = UUID()
        let thirdHouseholdId = UUID()
        let engine = LifecycleFakeHouseholdSyncEngine(
            results: [
                makeLifecycleNoDataPassResult(
                    reason: .householdJoined,
                    direction: .unknown,
                    syncRole: .owner,
                    syncScope: .ownerPrivate,
                    timelineStart: 99,
                    activeMemberCount: 1
                ),
                makeLifecycleNoDataPassResult(
                    reason: .householdSwitched,
                    direction: .unknown,
                    syncRole: .owner,
                    syncScope: .ownerPrivate,
                    timelineStart: 102,
                    activeMemberCount: 1
                ),
                makeLifecycleNoDataPassResult(
                    reason: .householdJoined,
                    direction: .unknown,
                    syncRole: .owner,
                    syncScope: .ownerPrivate,
                    timelineStart: 105,
                    activeMemberCount: 1
                ),
            ]
        )
        let coordinator = HouseholdSyncCoordinator(engine: engine)

        _ = await coordinator.performHouseholdLifecycleSyncIfNeeded(
            currentHouseholdID: firstHouseholdId
        )
        _ = await coordinator.performHouseholdLifecycleSyncIfNeeded(
            currentHouseholdID: secondHouseholdId
        )
        let clearedResult = await coordinator.performHouseholdLifecycleSyncIfNeeded(
            currentHouseholdID: nil
        )
        _ = await coordinator.performHouseholdLifecycleSyncIfNeeded(
            currentHouseholdID: thirdHouseholdId
        )

        XCTAssertEqual(clearedResult, .noData)
        XCTAssertEqual(
            engine.recordedReasons,
            [
                .householdJoined,
                .householdSwitched,
                .householdJoined,
            ]
        )
        XCTAssertEqual(coordinator.lastDiagnostics?.reason, .householdJoined)
    }
}

private func makeLifecycleNoDataPassResult(
    reason: HouseholdSyncReason,
    direction: HouseholdSyncDirection,
    syncRole: HouseholdSyncRole,
    syncScope: CloudKitManager.HouseholdDatabaseScope,
    timelineStart: TimeInterval,
    activeMemberCount: Int = 2
) -> HouseholdSyncPassResult {
    HouseholdSyncPassResult(
        fetchResult: .noData,
        events: [],
        diagnostics: HouseholdSyncDiagnostics(
            batchID: UUID(),
            reason: reason,
            direction: direction,
            syncRole: syncRole,
            syncScope: syncScope,
            triggerReceivedAt: Date(timeIntervalSince1970: timelineStart),
            syncStartedAt: Date(timeIntervalSince1970: timelineStart + 1),
            syncFinishedAt: Date(timeIntervalSince1970: timelineStart + 2),
            changedDomains: [],
            changedIDsByDomain: [:],
            activeMemberCount: activeMemberCount
        )
    )
}

@MainActor
private final class LifecycleFakeHouseholdSyncEngine: HouseholdSyncEngine {
    private(set) var recordedReasons: [HouseholdSyncReason] = []
    private var results: [HouseholdSyncPassResult]

    init(results: [HouseholdSyncPassResult]) {
        self.results = results
    }

    func runSync(for reason: HouseholdSyncReason) async -> HouseholdSyncPassResult {
        recordedReasons.append(reason)
        return results.removeFirst()
    }
}
