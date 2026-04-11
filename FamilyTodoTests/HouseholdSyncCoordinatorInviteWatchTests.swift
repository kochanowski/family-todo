import Foundation
@testable import HousePulse
import UIKit
import XCTest

@MainActor
final class HouseholdSyncCoordinatorInviteWatchTests: XCTestCase {
    func testInviteAcceptanceWatchRunsImmediateBurstAndSteadyPasses() async {
        CloudKitDiagnosticsState.shared.clear()
        let householdId = UUID()
        let engine = InviteWatchFakeHouseholdSyncEngine(
            results: [
                makeInviteWatchNoDataPassResult(timelineStart: 100),
                makeInviteWatchNoDataPassResult(timelineStart: 103),
                makeInviteWatchNoDataPassResult(timelineStart: 106),
                makeInviteWatchNoDataPassResult(timelineStart: 109),
            ]
        )
        let coordinator = makeInviteWatchCoordinator(
            engine: engine,
            householdId: householdId,
            watchConfiguration: InviteAcceptanceWatchConfiguration(
                isEnabled: true,
                burstIntervalNanoseconds: 0,
                burstMaxPassCount: 2,
                steadyIntervalNanoseconds: 0,
                steadyMaxPassCount: 1
            )
        )

        coordinator.startInviteAcceptanceWatch(for: householdId)
        await waitUntilInviteWatch {
            engine.recordedReasons.count == 4
        }

        XCTAssertEqual(
            engine.recordedReasons,
            [
                .localMutationFollowUp,
                .localMutationFollowUp,
                .localMutationFollowUp,
                .localMutationFollowUp,
            ]
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.scheduler.inviteWatch.started householdId=\(householdId.uuidString)")
            }
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.scheduler.inviteWatch.completed householdId=\(householdId.uuidString)")
            }
        )
    }

    func testInviteAcceptanceWatchStopsAfterOwnerSeesSecondMember() async {
        CloudKitDiagnosticsState.shared.clear()
        let householdId = UUID()
        let engine = InviteWatchFakeHouseholdSyncEngine(
            results: [
                makeInviteWatchNoDataPassResult(timelineStart: 100),
                HouseholdSyncPassResult(
                    fetchResult: .newData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .localMutationFollowUp,
                        direction: .unknown,
                        syncRole: .owner,
                        syncScope: .ownerPrivate,
                        triggerReceivedAt: Date(timeIntervalSince1970: 103),
                        syncStartedAt: Date(timeIntervalSince1970: 104),
                        syncFinishedAt: Date(timeIntervalSince1970: 105),
                        changedDomains: Set([.members]),
                        changedIDsByDomain: [:],
                        activeMemberCount: 2
                    )
                ),
            ]
        )
        let coordinator = makeInviteWatchCoordinator(
            engine: engine,
            householdId: householdId,
            watchConfiguration: InviteAcceptanceWatchConfiguration(
                isEnabled: true,
                burstIntervalNanoseconds: 0,
                burstMaxPassCount: 3,
                steadyIntervalNanoseconds: 0,
                steadyMaxPassCount: 0
            )
        )

        coordinator.startInviteAcceptanceWatch(for: householdId)
        await waitUntilInviteWatch {
            engine.recordedReasons.count == 2
        }
        try? await _Concurrency.Task.sleep(nanoseconds: 25_000_000)

        XCTAssertEqual(
            engine.recordedReasons,
            [
                .localMutationFollowUp,
                .localMutationFollowUp,
            ]
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.scheduler.inviteWatch.cancelled reason=memberCountSatisfied")
            }
        )
    }

    func testInviteAcceptanceWatchDoesNotScheduleAdditionalPassesAfterStop() async {
        CloudKitDiagnosticsState.shared.clear()
        let householdId = UUID()
        let engine = InviteWatchBlockingHouseholdSyncEngine()
        let coordinator = makeInviteWatchCoordinator(
            engine: engine,
            householdId: householdId,
            watchConfiguration: InviteAcceptanceWatchConfiguration(
                isEnabled: true,
                burstIntervalNanoseconds: 0,
                burstMaxPassCount: 2,
                steadyIntervalNanoseconds: 0,
                steadyMaxPassCount: 0
            )
        )

        coordinator.startInviteAcceptanceWatch(for: householdId)
        await engine.waitForInvocationCount(1)
        coordinator.stopInviteAcceptanceWatch(reason: "testStop")
        engine.finishNextInvocation(with: makeInviteWatchNoDataPassResult(timelineStart: 100))
        try? await _Concurrency.Task.sleep(nanoseconds: 25_000_000)

        XCTAssertEqual(engine.recordedReasons, [.localMutationFollowUp])
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.scheduler.inviteWatch.cancelled reason=testStop")
            }
        )
    }
}

@MainActor
private func makeInviteWatchCoordinator(
    engine: HouseholdSyncEngine,
    householdId: UUID,
    watchConfiguration: InviteAcceptanceWatchConfiguration
) -> HouseholdSyncCoordinator {
    HouseholdSyncCoordinator(
        engine: engine,
        applicationStateProvider: { .active },
        currentHouseholdIDProvider: { householdId },
        foregroundRepairConfiguration: ForegroundRepairConfiguration(
            isEnabled: false,
            burstIntervalNanoseconds: 0,
            burstMaxPassCount: 0,
            maxConsecutiveNoDataBurstPasses: 0,
            steadyIntervalNanoseconds: 0,
            steadyMaxPassCount: 0,
            ownerFallbackIntervalNanoseconds: 0,
            ownerFallbackMaxPassCount: 0
        ),
        inviteAcceptanceWatchConfiguration: watchConfiguration,
        sharedShoppingAlertDelivery: { _, _, _ in }
    )
}

private func makeInviteWatchNoDataPassResult(
    timelineStart: TimeInterval,
    activeMemberCount: Int = 1
) -> HouseholdSyncPassResult {
    HouseholdSyncPassResult(
        fetchResult: .noData,
        events: [],
        diagnostics: HouseholdSyncDiagnostics(
            batchID: UUID(),
            reason: .localMutationFollowUp,
            direction: .unknown,
            syncRole: .owner,
            syncScope: .ownerPrivate,
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
private final class InviteWatchFakeHouseholdSyncEngine: HouseholdSyncEngine {
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

@MainActor
private final class InviteWatchBlockingHouseholdSyncEngine: HouseholdSyncEngine {
    private(set) var recordedReasons: [HouseholdSyncReason] = []
    private var invocationWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuations: [CheckedContinuation<HouseholdSyncPassResult, Never>] = []

    func runSync(for reason: HouseholdSyncReason) async -> HouseholdSyncPassResult {
        recordedReasons.append(reason)
        if !invocationWaiters.isEmpty {
            let waiter = invocationWaiters.removeFirst()
            waiter.resume()
        }

        return await withCheckedContinuation { continuation in
            resultContinuations.append(continuation)
        }
    }

    func waitForInvocationCount(_ count: Int) async {
        while recordedReasons.count < count {
            await withCheckedContinuation { continuation in
                invocationWaiters.append(continuation)
            }
        }
    }

    func finishNextInvocation(with result: HouseholdSyncPassResult) {
        guard !resultContinuations.isEmpty else { return }
        let continuation = resultContinuations.removeFirst()
        continuation.resume(returning: result)
    }
}

@MainActor
private func waitUntilInviteWatch(
    timeoutNanoseconds: UInt64 = 250_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let start = Date()
    while !condition() {
        if Date().timeIntervalSince(start) > Double(timeoutNanoseconds) / 1_000_000_000 {
            return
        }
        await _Concurrency.Task.yield()
    }
}
