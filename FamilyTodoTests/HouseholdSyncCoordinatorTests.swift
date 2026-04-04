import Foundation
@testable import HousePulse
import UIKit
import XCTest

@MainActor
final class HouseholdSyncCoordinatorTests: XCTestCase {
    func testHouseholdSyncContextFactoryBuildsOwnerContext() {
        let householdId = UUID()
        let household = Household(
            id: householdId,
            name: "Smith Family",
            ownerId: "owner-1"
        )

        let context = HouseholdSyncContextFactory.make(
            household: household,
            currentUserId: "owner-1"
        )

        XCTAssertEqual(
            context,
            HouseholdSyncContext(
                householdId: householdId,
                currentUserId: "owner-1",
                ownerUserId: "owner-1",
                role: .owner,
                scope: .ownerPrivate
            )
        )
    }

    func testHouseholdSyncContextFactoryBuildsParticipantContext() {
        let householdId = UUID()
        let household = Household(
            id: householdId,
            name: "Smith Family",
            ownerId: "owner-1"
        )

        let context = HouseholdSyncContextFactory.make(
            household: household,
            currentUserId: "member-2"
        )

        XCTAssertEqual(
            context,
            HouseholdSyncContext(
                householdId: householdId,
                currentUserId: "member-2",
                ownerUserId: "owner-1",
                role: .participant,
                scope: .participantShared
            )
        )
    }

    func testHouseholdSyncContextFactoryReturnsNilWithoutRequiredInputs() {
        XCTAssertNil(
            HouseholdSyncContextFactory.make(
                householdId: UUID(),
                ownerUserId: nil,
                currentUserId: "user-1"
            )
        )
        XCTAssertNil(
            HouseholdSyncContextFactory.make(
                householdId: UUID(),
                ownerUserId: "owner-1",
                currentUserId: nil
            )
        )
    }

    func testPerformSyncPublishesEngineEventsAndReturnsFetchResult() async {
        CloudKitDiagnosticsState.shared.clear()
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
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.pass.started reason=remotePushShared")
            }
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.batch.published reason=remotePushShared")
            }
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.pass.completed reason=remotePushShared fetchResult=newData")
            }
        )
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

    func testPerformHouseholdLifecycleSyncUsesJoinedForFirstSelectionAndDedupesSameHousehold() async {
        let householdId = UUID()
        let engine = FakeHouseholdSyncEngine(
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
        let engine = FakeHouseholdSyncEngine(
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
                burstIntervalNanoseconds: 0,
                burstMaxPassCount: 0,
                maxConsecutiveNoDataBurstPasses: 0,
                steadyIntervalNanoseconds: 0,
                steadyMaxPassCount: 0,
                ownerFallbackIntervalNanoseconds: 0,
                ownerFallbackMaxPassCount: 0
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

    func testPerformSyncDoesNotDeliverSharedShoppingAlertForLifecycleRefresh() async {
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
                            source: .foregroundRepair,
                            reason: .appBecameActive,
                            timestamp: Date(timeIntervalSince1970: 100),
                            direction: .ownerToParticipant,
                            kind: .shoppingAdded(ids: Set([UUID()]), titles: ["Milk"])
                        ),
                    ],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: batchID,
                        reason: .appBecameActive,
                        direction: .ownerToParticipant,
                        triggerReceivedAt: Date(timeIntervalSince1970: 99),
                        syncStartedAt: Date(timeIntervalSince1970: 100),
                        syncFinishedAt: Date(timeIntervalSince1970: 101),
                        changedDomains: Set([.shopping]),
                        changedIDsByDomain: [:],
                        activeMemberCount: 2
                    )
                ),
            ]
        )
        let alertRecorder = SharedShoppingAlertRecorder()
        let coordinator = HouseholdSyncCoordinator(
            engine: engine,
            applicationStateProvider: { .background },
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
            sharedShoppingAlertDelivery: { titles, householdId, householdName in
                await alertRecorder.record(
                    titles: titles,
                    householdId: householdId,
                    householdName: householdName
                )
            }
        )

        _ = await coordinator.performSync(reason: .appBecameActive)

        XCTAssertTrue(alertRecorder.deliveries.isEmpty)
    }

    func testPerformSyncDoesNotScheduleForegroundRepairWindowForRemotePush() async {
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
            ]
        )
        let coordinator = HouseholdSyncCoordinator(
            engine: engine,
            applicationStateProvider: { .active },
            foregroundRepairConfiguration: ForegroundRepairConfiguration(
                isEnabled: true,
                burstIntervalNanoseconds: 0,
                burstMaxPassCount: 4,
                maxConsecutiveNoDataBurstPasses: 2,
                steadyIntervalNanoseconds: 0,
                steadyMaxPassCount: 0,
                ownerFallbackIntervalNanoseconds: 0,
                ownerFallbackMaxPassCount: 0
            ),
            sharedShoppingAlertDelivery: { _, _, _ in }
        )

        _ = await coordinator.performSync(reason: .remotePush(context: .sharedDatabase))
        await waitUntil {
            engine.recordedReasons.count == 1
        }

        XCTAssertEqual(engine.recordedReasons, [.remotePush(context: .sharedDatabase)])
        XCTAssertEqual(coordinator.lastDiagnostics?.reason, .remotePush(context: .sharedDatabase))
    }

    func testRemotePushSharedCancelsPendingForegroundRepairWindow() async {
        CloudKitDiagnosticsState.shared.clear()
        let engine = FakeHouseholdSyncEngine(
            results: [
                HouseholdSyncPassResult(
                    fetchResult: .newData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .appBecameActive,
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
                    fetchResult: .newData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .remotePush(context: .sharedDatabase),
                        direction: .ownerToParticipant,
                        triggerReceivedAt: Date(timeIntervalSince1970: 102),
                        syncStartedAt: Date(timeIntervalSince1970: 103),
                        syncFinishedAt: Date(timeIntervalSince1970: 104),
                        changedDomains: Set([.shopping]),
                        changedIDsByDomain: [.shopping: Set([UUID()])],
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
                burstIntervalNanoseconds: 200_000_000,
                burstMaxPassCount: 4,
                maxConsecutiveNoDataBurstPasses: 2,
                steadyIntervalNanoseconds: 200_000_000,
                steadyMaxPassCount: 0,
                ownerFallbackIntervalNanoseconds: 0,
                ownerFallbackMaxPassCount: 0
            ),
            sharedShoppingAlertDelivery: { _, _, _ in }
        )

        _ = await coordinator.performSync(reason: .appBecameActive)
        _ = await coordinator.performSync(reason: .remotePush(context: .sharedDatabase))
        try? await _Concurrency.Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(
            engine.recordedReasons,
            [
                .appBecameActive,
                .remotePush(context: .sharedDatabase),
            ]
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.scheduler.cancelled kind=foregroundRepair reason=remotePushPriority")
            }
        )
    }

    func testForegroundRepairWindowWithNewDataDoesNotRestartBurstWindow() async {
        let engine = FakeHouseholdSyncEngine(
            results: [
                HouseholdSyncPassResult(
                    fetchResult: .newData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .appBecameActive,
                        direction: .participantToOwner,
                        triggerReceivedAt: Date(timeIntervalSince1970: 99),
                        syncStartedAt: Date(timeIntervalSince1970: 100),
                        syncFinishedAt: Date(timeIntervalSince1970: 101),
                        changedDomains: Set([.shopping]),
                        changedIDsByDomain: [.shopping: Set([UUID()])],
                        activeMemberCount: 2
                    )
                ),
                HouseholdSyncPassResult(
                    fetchResult: .newData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .foregroundRepairWindow,
                        direction: .participantToOwner,
                        triggerReceivedAt: Date(timeIntervalSince1970: 102),
                        syncStartedAt: Date(timeIntervalSince1970: 103),
                        syncFinishedAt: Date(timeIntervalSince1970: 104),
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
                        direction: .participantToOwner,
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
                burstIntervalNanoseconds: 0,
                burstMaxPassCount: 2,
                maxConsecutiveNoDataBurstPasses: 2,
                steadyIntervalNanoseconds: 0,
                steadyMaxPassCount: 0,
                ownerFallbackIntervalNanoseconds: 0,
                ownerFallbackMaxPassCount: 0
            ),
            sharedShoppingAlertDelivery: { _, _, _ in }
        )

        _ = await coordinator.performSync(reason: .appBecameActive)
        await waitUntil {
            engine.recordedReasons.count == 3
        }

        XCTAssertEqual(
            engine.recordedReasons,
            [
                .appBecameActive,
                .foregroundRepairWindow,
                .foregroundRepairWindow,
            ]
        )
    }

    func testOwnerParticipantToOwnerSyncSchedulesOwnerFallbackPolls() async {
        CloudKitDiagnosticsState.shared.clear()
        let engine = FakeHouseholdSyncEngine(
            results: [
                makeLifecycleNoDataPassResult(
                    reason: .appBecameActive,
                    direction: .unknown,
                    syncRole: .owner,
                    syncScope: .ownerPrivate,
                    timelineStart: 99
                ),
                makeLifecycleNoDataPassResult(
                    reason: .foregroundRepairWindow,
                    direction: .unknown,
                    syncRole: .owner,
                    syncScope: .ownerPrivate,
                    timelineStart: 102
                ),
                makeLifecycleNoDataPassResult(
                    reason: .foregroundRepairWindow,
                    direction: .unknown,
                    syncRole: .owner,
                    syncScope: .ownerPrivate,
                    timelineStart: 105
                ),
            ]
        )
        let coordinator = HouseholdSyncCoordinator(
            engine: engine,
            applicationStateProvider: { .active },
            foregroundRepairConfiguration: ForegroundRepairConfiguration(
                isEnabled: false,
                burstIntervalNanoseconds: 0,
                burstMaxPassCount: 0,
                maxConsecutiveNoDataBurstPasses: 0,
                steadyIntervalNanoseconds: 0,
                steadyMaxPassCount: 0,
                ownerFallbackIntervalNanoseconds: 0,
                ownerFallbackMaxPassCount: 2
            ),
            sharedShoppingAlertDelivery: { _, _, _ in }
        )

        _ = await coordinator.performSync(reason: .appBecameActive)
        await waitUntil {
            engine.recordedReasons.count == 3
        }

        XCTAssertEqual(
            engine.recordedReasons,
            [
                .appBecameActive,
                .foregroundRepairWindow,
                .foregroundRepairWindow,
            ]
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.scheduler.ownerFallbackDecision eligible=true role=owner scope=ownerPrivate direction=unknown reason=appBecameActive")
            }
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.scheduler.started reason=appBecameActive ownerFallback=true")
            }
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.scheduler.scheduled kind=ownerFallback")
            }
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.scheduler.fired kind=ownerFallback")
            }
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.pass.started reason=foregroundRepairWindow")
            }
        )
    }

    func testParticipantLifecycleSyncDoesNotScheduleOwnerFallback() async {
        CloudKitDiagnosticsState.shared.clear()
        let engine = FakeHouseholdSyncEngine(
            results: [
                makeLifecycleNoDataPassResult(
                    reason: .appBecameActive,
                    direction: .unknown,
                    syncRole: .participant,
                    syncScope: .participantShared,
                    timelineStart: 99
                ),
            ]
        )
        let coordinator = HouseholdSyncCoordinator(
            engine: engine,
            applicationStateProvider: { .active },
            foregroundRepairConfiguration: ForegroundRepairConfiguration(
                isEnabled: false,
                burstIntervalNanoseconds: 0,
                burstMaxPassCount: 0,
                maxConsecutiveNoDataBurstPasses: 0,
                steadyIntervalNanoseconds: 0,
                steadyMaxPassCount: 0,
                ownerFallbackIntervalNanoseconds: 0,
                ownerFallbackMaxPassCount: 2
            ),
            sharedShoppingAlertDelivery: { _, _, _ in }
        )

        _ = await coordinator.performSync(reason: .appBecameActive)
        await waitUntil {
            engine.recordedReasons.count == 1
        }

        XCTAssertEqual(engine.recordedReasons, [.appBecameActive])
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("sync.scheduler.ownerFallbackDecision eligible=false role=participant scope=participantShared direction=unknown reason=appBecameActive")
            }
        )
        XCTAssertFalse(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains("ownerFallback=true")
            }
        )
    }

    func testPerformSyncSchedulesBoundedForegroundRepairForAppBecameActive() async {
        let engine = FakeHouseholdSyncEngine(
            results: [
                HouseholdSyncPassResult(
                    fetchResult: .newData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .appBecameActive,
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
                burstIntervalNanoseconds: 0,
                burstMaxPassCount: 4,
                maxConsecutiveNoDataBurstPasses: 2,
                steadyIntervalNanoseconds: 0,
                steadyMaxPassCount: 0,
                ownerFallbackIntervalNanoseconds: 0,
                ownerFallbackMaxPassCount: 0
            ),
            sharedShoppingAlertDelivery: { _, _, _ in }
        )

        _ = await coordinator.performSync(reason: .appBecameActive)
        await waitUntil {
            engine.recordedReasons.count == 3
        }

        XCTAssertEqual(
            engine.recordedReasons,
            [
                .appBecameActive,
                .foregroundRepairWindow,
                .foregroundRepairWindow,
            ]
        )
        XCTAssertEqual(coordinator.lastDiagnostics?.reason, .foregroundRepairWindow)
        XCTAssertEqual(coordinator.lastDiagnostics?.activeMemberCount, 2)
    }

    func testManualRefreshDoesNotScheduleForegroundRepairWindow() async {
        let engine = FakeHouseholdSyncEngine(
            results: [
                HouseholdSyncPassResult(
                    fetchResult: .newData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .manualRefresh,
                        direction: .ownerToParticipant,
                        triggerReceivedAt: Date(timeIntervalSince1970: 99),
                        syncStartedAt: Date(timeIntervalSince1970: 100),
                        syncFinishedAt: Date(timeIntervalSince1970: 101),
                        changedDomains: Set([.shopping]),
                        changedIDsByDomain: [.shopping: Set([UUID()])],
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
                burstIntervalNanoseconds: 0,
                burstMaxPassCount: 4,
                maxConsecutiveNoDataBurstPasses: 2,
                steadyIntervalNanoseconds: 0,
                steadyMaxPassCount: 0,
                ownerFallbackIntervalNanoseconds: 0,
                ownerFallbackMaxPassCount: 0
            ),
            sharedShoppingAlertDelivery: { _, _, _ in }
        )

        _ = await coordinator.performSync(reason: .manualRefresh)
        await waitUntil {
            engine.recordedReasons.count > 1
        }

        XCTAssertEqual(engine.recordedReasons, [.manualRefresh])
        XCTAssertEqual(coordinator.lastDiagnostics?.reason, .manualRefresh)
    }

    func testPerformSyncFallsBackToSteadyForegroundRepairWhenBurstWindowExhausts() async {
        let engine = FakeHouseholdSyncEngine(
            results: [
                HouseholdSyncPassResult(
                    fetchResult: .newData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .appBecameActive,
                        direction: .participantToOwner,
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
                        direction: .participantToOwner,
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
                        direction: .participantToOwner,
                        triggerReceivedAt: Date(timeIntervalSince1970: 105),
                        syncStartedAt: Date(timeIntervalSince1970: 106),
                        syncFinishedAt: Date(timeIntervalSince1970: 107),
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
                        direction: .participantToOwner,
                        triggerReceivedAt: Date(timeIntervalSince1970: 108),
                        syncStartedAt: Date(timeIntervalSince1970: 109),
                        syncFinishedAt: Date(timeIntervalSince1970: 110),
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
                burstIntervalNanoseconds: 0,
                burstMaxPassCount: 2,
                maxConsecutiveNoDataBurstPasses: 1,
                steadyIntervalNanoseconds: 0,
                steadyMaxPassCount: 2,
                ownerFallbackIntervalNanoseconds: 0,
                ownerFallbackMaxPassCount: 0
            ),
            sharedShoppingAlertDelivery: { _, _, _ in }
        )

        _ = await coordinator.performSync(reason: .appBecameActive)
        await waitUntil {
            engine.recordedReasons.count == 4
        }

        XCTAssertEqual(
            engine.recordedReasons,
            [
                .appBecameActive,
                .foregroundRepairWindow,
                .foregroundRepairWindow,
                .foregroundRepairWindow,
            ]
        )
        XCTAssertEqual(coordinator.lastDiagnostics?.reason, .foregroundRepairWindow)
        XCTAssertEqual(coordinator.lastDiagnostics?.direction, .participantToOwner)
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
