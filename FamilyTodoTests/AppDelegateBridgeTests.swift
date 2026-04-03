import CloudKit
@testable import HousePulse
import UserNotifications
import XCTest

@MainActor
final class AppDelegateBridgeTests: XCTestCase {
    func testRemotePushDiagnosticTracksQueuedOwnerRecordZoneInference() {
        let householdId = UUID()
        let syncContext = HouseholdSyncContext(
            householdId: householdId,
            currentUserId: "owner-1",
            ownerUserId: "owner-1",
            role: .owner,
            scope: .ownerPrivate
        )
        let resolution = RemoteCloudChangeScopeResolution(
            declaredScope: nil,
            effectiveScope: .private,
            notificationType: .recordZone,
            currentSyncContext: syncContext,
            inferredFromSyncContext: true
        )
        let bridge = AppDelegateBridge()

        let diagnostic = bridge.makeRemotePushDiagnostic(
            resolution: resolution,
            handlerInstalled: true,
            queuedBehindActiveRefresh: true
        )

        XCTAssertEqual(diagnostic.notificationType, .recordZone)
        XCTAssertNil(diagnostic.declaredScope)
        XCTAssertEqual(diagnostic.effectiveScope, .private)
        XCTAssertTrue(diagnostic.currentSyncContextAvailable)
        XCTAssertTrue(diagnostic.inferredFromSyncContext)
        XCTAssertTrue(diagnostic.handlerInstalled)
        XCTAssertTrue(diagnostic.queuedBehindActiveRefresh)
        XCTAssertTrue(diagnostic.willInvokeRemoteCloudChangeHandler)
        XCTAssertEqual(diagnostic.syncRole, .owner)
        XCTAssertEqual(diagnostic.syncHouseholdId, householdId)
    }

    func testRemotePushDiagnosticStaysUnresolvedWhenSyncContextIsMissing() {
        let bridge = AppDelegateBridge()
        let resolution = RemoteCloudChangeScopeResolution(
            declaredScope: nil,
            effectiveScope: nil,
            notificationType: .recordZone,
            currentSyncContext: nil,
            inferredFromSyncContext: false
        )

        let diagnostic = bridge.makeRemotePushDiagnostic(
            resolution: resolution,
            handlerInstalled: true,
            queuedBehindActiveRefresh: false
        )

        XCTAssertNil(diagnostic.declaredScope)
        XCTAssertNil(diagnostic.effectiveScope)
        XCTAssertFalse(diagnostic.currentSyncContextAvailable)
        XCTAssertFalse(diagnostic.inferredFromSyncContext)
        XCTAssertFalse(diagnostic.queuedBehindActiveRefresh)
        XCTAssertTrue(diagnostic.willInvokeRemoteCloudChangeHandler)
        XCTAssertNil(diagnostic.syncRole)
        XCTAssertNil(diagnostic.syncHouseholdId)
    }

    func testForegroundPresentationKeepsReminderBanner() {
        let bridge = AppDelegateBridge()

        let options = bridge.foregroundPresentationOptions(
            categoryIdentifier: "TASK_REMINDER",
            hasSound: true
        )

        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.list))
        XCTAssertTrue(options.contains(.sound))
    }

    func testForegroundPresentationSuppressesSharedShoppingAlerts() {
        let bridge = AppDelegateBridge()

        let options = bridge.foregroundPresentationOptions(
            categoryIdentifier: "SHARED_SHOPPING_UPDATE",
            hasSound: true
        )

        XCTAssertEqual(options, [])
    }

    func testForegroundPresentationSuppressesCelebrationAlerts() {
        let bridge = AppDelegateBridge()

        let options = bridge.foregroundPresentationOptions(
            categoryIdentifier: "CELEBRATION",
            hasSound: true
        )

        XCTAssertEqual(options, [])
    }
}
