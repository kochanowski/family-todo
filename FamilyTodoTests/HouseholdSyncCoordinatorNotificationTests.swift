import Foundation
@testable import HousePulse
import UIKit
import XCTest

@MainActor
final class HouseholdSyncCoordinatorNotificationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CloudKitDiagnosticsState.shared.clear()
    }

    func testPerformSyncDeliversPassiveTaskAlertForSteadyStateRemoteBatch() async {
        let householdId = UUID()
        let batchID = UUID()
        let engine = PassiveAlertFakeHouseholdSyncEngine(
            result: HouseholdSyncPassResult(
                fetchResult: .newData,
                events: [
                    HouseholdSyncEvent(
                        householdId: householdId,
                        batchID: batchID,
                        source: .remote,
                        reason: .remotePush(context: .sharedDatabase),
                        timestamp: Date(timeIntervalSince1970: 100),
                        direction: .ownerToParticipant,
                        kind: .tasksChanged(
                            addedIDs: Set([UUID(), UUID()]),
                            changedIDs: [],
                            removedIDs: []
                        )
                    ),
                ],
                diagnostics: HouseholdSyncDiagnostics(
                    batchID: batchID,
                    reason: .remotePush(context: .sharedDatabase),
                    direction: .ownerToParticipant,
                    triggerReceivedAt: Date(timeIntervalSince1970: 99),
                    syncStartedAt: Date(timeIntervalSince1970: 100),
                    syncFinishedAt: Date(timeIntervalSince1970: 101),
                    changedDomains: Set([.tasks]),
                    changedIDsByDomain: [:],
                    activeMemberCount: 2
                )
            )
        )
        let alertRecorder = PassiveSharedActivityAlertRecorder()
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
            sharedShoppingAlertDelivery: { _, _, _ in },
            passiveSharedActivityAlertDelivery: { descriptor in
                await alertRecorder.record(descriptor)
            }
        )

        _ = await coordinator.performSync(reason: .remotePush(context: .sharedDatabase))

        XCTAssertEqual(
            alertRecorder.deliveries,
            [
                PassiveSharedActivityAlertDescriptor(
                    householdId: householdId,
                    householdName: nil,
                    domain: .tasks,
                    changeCount: 2
                ),
            ]
        )
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains(
                    "notification.sharedActivity.descriptorPrepared householdId=\(householdId.uuidString) domain=tasks changeCount=2"
                )
            }
        )
    }

    func testLifecycleBatchSkipsPassiveSharedActivityDeliveryAndLogsWhy() async {
        let householdId = UUID()
        let batchID = UUID()
        let engine = PassiveAlertFakeHouseholdSyncEngine(
            result: HouseholdSyncPassResult(
                fetchResult: .newData,
                events: [
                    HouseholdSyncEvent(
                        householdId: householdId,
                        batchID: batchID,
                        source: .foregroundRepair,
                        reason: .foregroundRepairWindow,
                        timestamp: Date(timeIntervalSince1970: 100),
                        direction: .unknown,
                        kind: .shoppingAdded(
                            ids: Set([UUID()]),
                            titles: ["Milk"]
                        )
                    ),
                ],
                diagnostics: HouseholdSyncDiagnostics(
                    batchID: batchID,
                    reason: .foregroundRepairWindow,
                    direction: .unknown,
                    triggerReceivedAt: Date(timeIntervalSince1970: 99),
                    syncStartedAt: Date(timeIntervalSince1970: 100),
                    syncFinishedAt: Date(timeIntervalSince1970: 101),
                    changedDomains: Set([.shopping]),
                    changedIDsByDomain: [:],
                    activeMemberCount: 2
                )
            )
        )
        let alertRecorder = PassiveSharedActivityAlertRecorder()
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
            sharedShoppingAlertDelivery: { _, _, _ in },
            passiveSharedActivityAlertDelivery: { descriptor in
                await alertRecorder.record(descriptor)
            }
        )

        _ = await coordinator.performSync(reason: .foregroundRepairWindow)

        XCTAssertTrue(alertRecorder.deliveries.isEmpty)
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.entries.contains {
                $0.operation.contains(
                    "notification.sharedActivity.batchSkipped classification=steadyStateLifecycle"
                )
            }
        )
    }
}

@MainActor
private final class PassiveAlertFakeHouseholdSyncEngine: HouseholdSyncEngine {
    private let result: HouseholdSyncPassResult

    init(result: HouseholdSyncPassResult) {
        self.result = result
    }

    func runSync(for _: HouseholdSyncReason) async -> HouseholdSyncPassResult {
        result
    }
}

@MainActor
private final class PassiveSharedActivityAlertRecorder {
    private(set) var deliveries: [PassiveSharedActivityAlertDescriptor] = []

    func record(_ descriptor: PassiveSharedActivityAlertDescriptor) {
        deliveries.append(descriptor)
    }
}
