import Foundation
@testable import HousePulse
import UIKit
import XCTest

final class CloudKitSubscriptionManagerTests: XCTestCase {
    @MainActor
    private func makeManager() -> CloudKitSubscriptionManager {
        let manager = CloudKitSubscriptionManager()
        manager.resetTransientPresentationState()
        return manager
    }

    @MainActor
    func testParticipantSharedSkipsZoneSubscriptions() {
        XCTAssertFalse(
            CloudKitSubscriptionManager.shouldCreateZoneSubscription(for: .participantShared)
        )
        XCTAssertTrue(
            CloudKitSubscriptionManager.shouldCreateZoneSubscription(for: .ownerPrivate)
        )
    }

    func testCloudKitSchemaKeepsHouseholdMemberRecordIndexesAndInviteTokenRoles() throws {
        let schemaURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cloudkit")
            .appendingPathComponent("schema")
            .appendingPathComponent("housepulse-schema.json")
        let data = try Data(contentsOf: schemaURL)
        let object = try JSONSerialization.jsonObject(with: data)
        let schema = try XCTUnwrap(object as? [String: Any])
        let recordTypes = try XCTUnwrap(schema["recordTypes"] as? [[String: Any]])

        let household = try XCTUnwrap(recordTypes.first { $0["name"] as? String == "Household" })
        let householdIndexes = try XCTUnwrap(household["indexes"] as? [String: Any])
        XCTAssertTrue(((householdIndexes["query"] as? [String]) ?? []).contains("___recordID"))

        let member = try XCTUnwrap(recordTypes.first { $0["name"] as? String == "Member" })
        let memberIndexes = try XCTUnwrap(member["indexes"] as? [String: Any])
        XCTAssertTrue(((memberIndexes["query"] as? [String]) ?? []).contains("___recordID"))

        let securityRoles = try XCTUnwrap(schema["securityRoles"] as? [[String: Any]])
        let inviteRolePermissions = securityRoles.flatMap { role -> [String] in
            let roleName = role["name"] as? String ?? ""
            let recordPermissions = (role["recordTypePermissions"] as? [[String: Any]]) ?? []
            return recordPermissions.compactMap { permission -> [String]? in
                guard permission["recordType"] as? String == "InviteToken" else { return nil }
                let actions = [
                    (permission["create"] as? Bool == true) ? "create" : nil,
                    (permission["read"] as? Bool == true) ? "read" : nil,
                    (permission["write"] as? Bool == true) ? "write" : nil,
                ].compactMap { $0 }
                return actions.map { "\(roleName):\($0)" }
            }.flatMap { $0 }
        }

        XCTAssertTrue(inviteRolePermissions.contains("_world:read"))
        XCTAssertTrue(inviteRolePermissions.contains("_icloud:create"))
        XCTAssertTrue(inviteRolePermissions.contains("_icloud:read"))
        XCTAssertTrue(inviteRolePermissions.contains("_creator:read"))
        XCTAssertTrue(inviteRolePermissions.contains("_creator:write"))
    }

    @MainActor
    func testShoppingAdditionOnShoppingTabPublishesNoTextInlineFeedbackAndNoBanner() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.shopping)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 3,
                titles: ["Milk", "Bread", "Eggs"]
            ),
            applicationState: .active
        )

        XCTAssertNil(manager.shoppingInlineFeedback)
        XCTAssertFalse(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 0)
    }

    @MainActor
    func testShoppingAdditionOffShoppingTabShowsBannerWithoutInlineFeedback() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.tasks)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 2,
                titles: ["Milk", "Bread"]
            ),
            applicationState: .active
        )

        XCTAssertTrue(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 2)
        XCTAssertNil(manager.shoppingInlineFeedback)
        XCTAssertNil(manager.tasksInlineFeedback)
    }

    @MainActor
    func testTaskUpdateOnTasksTabPublishesInlineFeedbackWithoutBanner() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.tasks)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .tasks,
                kind: .updates,
                changeCount: 1,
                titles: []
            ),
            applicationState: .active
        )

        XCTAssertEqual(manager.tasksInlineFeedback?.text, "Tasks updated")
        XCTAssertFalse(manager.showNewItemsBanner)
        XCTAssertNil(manager.shoppingInlineFeedback)
    }

    @MainActor
    func testTaskAdditionOffTasksTabDoesNotShowGlobalBannerOrInlineFeedback() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.shopping)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .tasks,
                kind: .additions,
                changeCount: 1,
                titles: ["Take out trash"]
            ),
            applicationState: .active
        )

        XCTAssertFalse(manager.showNewItemsBanner)
        XCTAssertNil(manager.tasksInlineFeedback)
        XCTAssertNil(manager.shoppingInlineFeedback)
    }

    @MainActor
    func testSharedShoppingAlertsAreSuppressedOnlyWhenShoppingTabIsVisible() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }

        manager.updateActiveTab(.shopping)
        XCTAssertTrue(manager.shouldSuppressSharedShoppingAlert(applicationState: .active))

        manager.updateActiveTab(.tasks)
        XCTAssertFalse(manager.shouldSuppressSharedShoppingAlert(applicationState: .active))
        XCTAssertFalse(manager.shouldSuppressSharedShoppingAlert(applicationState: .background))
    }

    @MainActor
    func testCelebrationAlertsAreSuppressedOnlyWhenTasksTabIsVisible() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }

        manager.updateActiveTab(.tasks)
        XCTAssertTrue(manager.shouldSuppressHouseholdCelebrationAlert(applicationState: .active))

        manager.updateActiveTab(.shopping)
        XCTAssertFalse(manager.shouldSuppressHouseholdCelebrationAlert(applicationState: .active))
        XCTAssertFalse(manager.shouldSuppressHouseholdCelebrationAlert(applicationState: .background))
    }

    @MainActor
    func testShoppingAdditionOffShoppingTabAccumulatesExistingBannerCount() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.tasks)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 2,
                titles: ["Milk", "Bread"]
            ),
            applicationState: .active
        )
        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 3,
                titles: ["Eggs", "Butter", "Cheese"]
            ),
            applicationState: .active
        )

        XCTAssertTrue(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 5)
    }

    @MainActor
    func testTaskPresentationDoesNotClearExistingShoppingBanner() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.more)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 2,
                titles: ["Milk", "Bread"]
            ),
            applicationState: .active
        )
        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .tasks,
                kind: .updates,
                changeCount: 1,
                titles: []
            ),
            applicationState: .active
        )

        XCTAssertTrue(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 2)
    }

    @MainActor
    func testShoppingUpdatesOffShoppingTabDoNotClearExistingBanner() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.tasks)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 2,
                titles: ["Milk", "Bread"]
            ),
            applicationState: .active
        )
        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .updates,
                changeCount: 1,
                titles: []
            ),
            applicationState: .active
        )

        XCTAssertTrue(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 2)
    }

    @MainActor
    func testBootstrapMemberJoinBatchDoesNotShowShoppingBannerOrInlineFeedback() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.tasks)

        let householdId = UUID()
        let batchID = UUID()
        let batch = HouseholdSyncBatch(
            events: [
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchID,
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(timeIntervalSince1970: 10),
                    direction: .ownerToParticipant,
                    kind: .membersChanged(ids: Set([UUID()]))
                ),
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchID,
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(timeIntervalSince1970: 10),
                    direction: .ownerToParticipant,
                    kind: .shoppingAdded(ids: Set([UUID(), UUID()]), titles: ["Milk", "Bread"])
                ),
            ],
            diagnostics: HouseholdSyncDiagnostics(
                batchID: batchID,
                reason: .remotePush(context: .sharedDatabase),
                direction: .ownerToParticipant,
                triggerReceivedAt: Date(timeIntervalSince1970: 9),
                syncStartedAt: Date(timeIntervalSince1970: 10),
                syncFinishedAt: Date(timeIntervalSince1970: 11),
                changedDomains: Set([.members, .shopping]),
                changedIDsByDomain: [:]
            )
        )

        manager.consumeSyncBatch(batch, applicationState: .active)

        XCTAssertFalse(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 0)
        XCTAssertNil(manager.shoppingInlineFeedback)
        XCTAssertNil(manager.tasksInlineFeedback)
    }

    @MainActor
    func testConsumeSyncBatchSuppressesLikelySelfNoiseShoppingAdditionPresentation() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.tasks)

        let itemID = UUID()
        manager.registerLocalMutation(recordName: itemID.uuidString)

        let batch = HouseholdSyncBatch(
            events: [
                HouseholdSyncEvent(
                    householdId: UUID(),
                    batchID: UUID(),
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(),
                    direction: .ownerToParticipant,
                    kind: .shoppingAdded(ids: Set([itemID]), titles: ["Milk"])
                ),
            ],
            diagnostics: HouseholdSyncDiagnostics(
                batchID: UUID(),
                reason: .remotePush(context: .sharedDatabase),
                direction: .ownerToParticipant,
                triggerReceivedAt: Date(),
                syncStartedAt: Date(),
                syncFinishedAt: Date(),
                changedDomains: Set([.shopping]),
                changedIDsByDomain: [.shopping: Set([itemID])],
                activeMemberCount: 2
            )
        )

        manager.consumeSyncBatch(batch, applicationState: .active)

        XCTAssertFalse(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 0)
        XCTAssertNil(manager.shoppingInlineFeedback)
    }
}
