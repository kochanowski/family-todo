import Foundation
@testable import HousePulse
import UIKit
import XCTest

@MainActor
final class HouseholdSyncCoordinatorTests: XCTestCase {
    func testPerformSyncPublishesEngineEventsAndReturnsFetchResult() async {
        let householdId = UUID()
        let expectedEvents = [
            HouseholdSyncEvent(
                householdId: householdId,
                batchID: UUID(),
                source: .remote,
                reason: .remotePush(context: .sharedDatabase),
                timestamp: Date(timeIntervalSince1970: 100),
                direction: .ownerToParticipant,
                kind: .shoppingAdded(ids: Set([UUID()]), titles: ["Milk"])
            ),
            HouseholdSyncEvent(
                householdId: householdId,
                batchID: UUID(),
                source: .remote,
                reason: .remotePush(context: .sharedDatabase),
                timestamp: Date(timeIntervalSince1970: 101),
                direction: .ownerToParticipant,
                kind: .householdMetadataChanged
            ),
        ]

        let engine = FakeHouseholdSyncEngine(
            results: [
                HouseholdSyncPassResult(
                    fetchResult: .newData,
                    events: expectedEvents,
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .remotePush(context: .sharedDatabase),
                        direction: .ownerToParticipant,
                        triggerReceivedAt: Date(timeIntervalSince1970: 99),
                        syncStartedAt: Date(timeIntervalSince1970: 100),
                        syncFinishedAt: Date(timeIntervalSince1970: 101),
                        changedDomains: Set([.shopping, .household]),
                        changedIDsByDomain: [:]
                    )
                ),
            ]
        )
        let coordinator = HouseholdSyncCoordinator(engine: engine)

        let result = await coordinator.performSync(
            reason: .remotePush(context: .sharedDatabase)
        )

        XCTAssertEqual(result, .newData)
        XCTAssertEqual(engine.recordedReasons, [.remotePush(context: .sharedDatabase)])
        XCTAssertEqual(coordinator.lastPublishedEvents, expectedEvents)
        XCTAssertEqual(coordinator.lastDiagnostics?.changedDomains, Set([.shopping, .household]))
    }

    func testPerformSyncCoalescesPendingReasonsIntoFollowUpPass() async {
        let engine = BlockingHouseholdSyncEngine()
        let coordinator = HouseholdSyncCoordinator(engine: engine)

        let firstTask = Task {
            await coordinator.performSync(reason: .remotePush(context: .privateDatabase))
        }

        await engine.waitForInvocationCount(1)

        let secondTask = Task {
            await coordinator.performSync(reason: .appBecameActive)
        }
        let thirdTask = Task {
            await coordinator.performSync(reason: .manualRefresh)
        }

        await Task.yield()
        XCTAssertEqual(engine.recordedReasons, [.remotePush(context: .privateDatabase)])

        engine.finishNextInvocation(
            with: HouseholdSyncPassResult(
                fetchResult: .noData,
                events: [],
                diagnostics: HouseholdSyncDiagnostics(
                    batchID: UUID(),
                    reason: .remotePush(context: .privateDatabase),
                    direction: .unknown,
                    triggerReceivedAt: Date(timeIntervalSince1970: 10),
                    syncStartedAt: Date(timeIntervalSince1970: 11),
                    syncFinishedAt: Date(timeIntervalSince1970: 12),
                    changedDomains: [],
                    changedIDsByDomain: [:]
                )
            )
        )

        await engine.waitForInvocationCount(2)

        XCTAssertEqual(
            engine.recordedReasons,
            [
                .remotePush(context: .privateDatabase),
                .manualRefresh,
            ]
        )

        engine.finishNextInvocation(
            with: HouseholdSyncPassResult(
                fetchResult: .newData,
                events: [],
                diagnostics: HouseholdSyncDiagnostics(
                    batchID: UUID(),
                    reason: .manualRefresh,
                    direction: .unknown,
                    triggerReceivedAt: Date(timeIntervalSince1970: 13),
                    syncStartedAt: Date(timeIntervalSince1970: 14),
                    syncFinishedAt: Date(timeIntervalSince1970: 15),
                    changedDomains: Set([.tasks]),
                    changedIDsByDomain: [:]
                )
            )
        )

        let firstResult = await firstTask.value
        let secondResult = await secondTask.value
        let thirdResult = await thirdTask.value

        XCTAssertEqual(firstResult, .newData)
        XCTAssertEqual(secondResult, .newData)
        XCTAssertEqual(thirdResult, .newData)
        XCTAssertEqual(coordinator.lastDiagnostics?.reason, .manualRefresh)
    }
}

@MainActor
private final class FakeHouseholdSyncEngine: HouseholdSyncEngine {
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
private final class BlockingHouseholdSyncEngine: HouseholdSyncEngine {
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
