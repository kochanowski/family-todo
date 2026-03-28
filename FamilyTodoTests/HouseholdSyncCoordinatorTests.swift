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

        let firstTask = _Concurrency.Task<UIBackgroundFetchResult, Never> {
            await coordinator.performSync(reason: .remotePush(context: .privateDatabase))
        }

        await engine.waitForInvocationCount(1)

        let secondTask = _Concurrency.Task<UIBackgroundFetchResult, Never> {
            await coordinator.performSync(reason: .appBecameActive)
        }
        let thirdTask = _Concurrency.Task<UIBackgroundFetchResult, Never> {
            await coordinator.performSync(reason: .manualRefresh)
        }

        await _Concurrency.Task.yield()
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

        let firstResult: UIBackgroundFetchResult = await firstTask.value
        let secondResult: UIBackgroundFetchResult = await secondTask.value
        let thirdResult: UIBackgroundFetchResult = await thirdTask.value

        XCTAssertEqual(firstResult, .newData)
        XCTAssertEqual(secondResult, .newData)
        XCTAssertEqual(thirdResult, .newData)
        XCTAssertEqual(coordinator.lastDiagnostics?.reason, .manualRefresh)
    }

    func testPerformSyncSkipsSharedShoppingAlertDeliveryForBootstrapBatch() async {
        let householdId = UUID()
        let batchID = UUID()
        let engine = FakeHouseholdSyncEngine(
            results: [
                HouseholdSyncPassResult(
                    fetchResult: .newData,
                    events: [
                        HouseholdSyncEvent(
                            householdId: householdId,
                            batchID: batchID,
                            source: .remote,
                            reason: .remotePush(context: .sharedDatabase),
                            timestamp: Date(timeIntervalSince1970: 100),
                            direction: .ownerToParticipant,
                            kind: .membersChanged(ids: Set([UUID()]))
                        ),
                        HouseholdSyncEvent(
                            householdId: householdId,
                            batchID: batchID,
                            source: .remote,
                            reason: .remotePush(context: .sharedDatabase),
                            timestamp: Date(timeIntervalSince1970: 100),
                            direction: .ownerToParticipant,
                            kind: .shoppingAdded(ids: Set([UUID()]), titles: ["Milk"])
                        ),
                    ],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: batchID,
                        reason: .remotePush(context: .sharedDatabase),
                        direction: .ownerToParticipant,
                        triggerReceivedAt: Date(timeIntervalSince1970: 99),
                        syncStartedAt: Date(timeIntervalSince1970: 100),
                        syncFinishedAt: Date(timeIntervalSince1970: 101),
                        changedDomains: Set([.members, .shopping]),
                        changedIDsByDomain: [:],
                        activeMemberCount: 2
                    )
                ),
            ]
        )
        let alertRecorder = SharedShoppingAlertRecorder()
        let coordinator = HouseholdSyncCoordinator(
            engine: engine,
            applicationStateProvider: { .active },
            foregroundRepairConfiguration: ForegroundRepairConfiguration(
                isEnabled: false,
                intervalNanoseconds: 0,
                maxPassCount: 0,
                maxConsecutiveNoDataPasses: 0
            ),
            sharedShoppingAlertDelivery: { titles, householdId, householdName in
                await alertRecorder.record(
                    titles: titles,
                    householdId: householdId,
                    householdName: householdName
                )
            }
        )

        _ = await coordinator.performSync(reason: .remotePush(context: .sharedDatabase))

        let deliveries = alertRecorder.deliveries
        XCTAssertTrue(deliveries.isEmpty)
    }

    func testPerformSyncSchedulesBoundedForegroundRepairForCollaborativeHousehold() async {
        let engine = FakeHouseholdSyncEngine(
            results: [
                HouseholdSyncPassResult(
                    fetchResult: .newData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .remotePush(context: .sharedDatabase),
                        direction: .ownerToParticipant,
                        triggerReceivedAt: Date(timeIntervalSince1970: 99),
                        syncStartedAt: Date(timeIntervalSince1970: 100),
                        syncFinishedAt: Date(timeIntervalSince1970: 101),
                        changedDomains: Set([.shopping]),
                        changedIDsByDomain: [.shopping: Set([UUID()])],
                        activeMemberCount: 2
                    )
                ),
                HouseholdSyncPassResult(
                    fetchResult: .noData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .foregroundRepairWindow,
                        direction: .ownerToParticipant,
                        triggerReceivedAt: Date(timeIntervalSince1970: 102),
                        syncStartedAt: Date(timeIntervalSince1970: 103),
                        syncFinishedAt: Date(timeIntervalSince1970: 104),
                        changedDomains: [],
                        changedIDsByDomain: [:],
                        activeMemberCount: 2
                    )
                ),
                HouseholdSyncPassResult(
                    fetchResult: .noData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .foregroundRepairWindow,
                        direction: .ownerToParticipant,
                        triggerReceivedAt: Date(timeIntervalSince1970: 105),
                        syncStartedAt: Date(timeIntervalSince1970: 106),
                        syncFinishedAt: Date(timeIntervalSince1970: 107),
                        changedDomains: [],
                        changedIDsByDomain: [:],
                        activeMemberCount: 2
                    )
                ),
            ]
        )
        let coordinator = HouseholdSyncCoordinator(
            engine: engine,
            applicationStateProvider: { .active },
            foregroundRepairConfiguration: ForegroundRepairConfiguration(
                isEnabled: true,
                intervalNanoseconds: 0,
                maxPassCount: 4,
                maxConsecutiveNoDataPasses: 2
            ),
            sharedShoppingAlertDelivery: { _, _, _ in }
        )

        _ = await coordinator.performSync(reason: .remotePush(context: .sharedDatabase))
        await waitUntil {
            engine.recordedReasons.count == 3
        }

        XCTAssertEqual(
            engine.recordedReasons,
            [
                .remotePush(context: .sharedDatabase),
                .foregroundRepairWindow,
                .foregroundRepairWindow,
            ]
        )
        XCTAssertEqual(coordinator.lastDiagnostics?.reason, .foregroundRepairWindow)
        XCTAssertEqual(coordinator.lastDiagnostics?.activeMemberCount, 2)
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
private final class SharedShoppingAlertRecorder {
    struct Delivery: Equatable {
        let titles: [String]
        let householdId: UUID
        let householdName: String?
    }

    private(set) var deliveries: [Delivery] = []

    func record(
        titles: [String],
        householdId: UUID,
        householdName: String?
    ) {
        deliveries.append(
            Delivery(
                titles: titles,
                householdId: householdId,
                householdName: householdName
            )
        )
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

@MainActor
private func waitUntil(
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
