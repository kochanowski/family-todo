import Foundation
@testable import HousePulse
import XCTest

final class HouseholdSyncBatchTests: XCTestCase {
    func testChangedIDAccessorsUnionAddedChangedAndRemovedIDsAcrossEvents() {
        let householdId = UUID()
        let batchId = UUID()
        let addedTaskID = UUID()
        let changedTaskID = UUID()
        let removedTaskID = UUID()
        let addedIdeaID = UUID()
        let changedIdeaID = UUID()
        let removedIdeaID = UUID()
        let addedCategoryID = UUID()
        let changedCategoryID = UUID()
        let removedCategoryID = UUID()
        let addedShoppingID = UUID()
        let changedShoppingID = UUID()
        let changedBundleID = UUID()
        let removedShoppingID = UUID()
        let removedBundleID = UUID()
        let memberID = UUID()

        let batch = HouseholdSyncBatch(
            events: [
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchId,
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(timeIntervalSince1970: 1),
                    direction: .participantToOwner,
                    kind: .tasksChanged(
                        addedIDs: [addedTaskID],
                        changedIDs: [changedTaskID],
                        removedIDs: [removedTaskID]
                    )
                ),
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchId,
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(timeIntervalSince1970: 1),
                    direction: .participantToOwner,
                    kind: .ideasChanged(
                        addedIDs: [addedIdeaID],
                        changedIDs: [changedIdeaID],
                        removedIDs: [removedIdeaID]
                    )
                ),
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchId,
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(timeIntervalSince1970: 1),
                    direction: .participantToOwner,
                    kind: .backlogCategoriesChanged(
                        addedIDs: [addedCategoryID],
                        changedIDs: [changedCategoryID],
                        removedIDs: [removedCategoryID]
                    )
                ),
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchId,
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(timeIntervalSince1970: 1),
                    direction: .participantToOwner,
                    kind: .shoppingAdded(ids: [addedShoppingID], titles: ["Milk"])
                ),
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchId,
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(timeIntervalSince1970: 1),
                    direction: .participantToOwner,
                    kind: .shoppingUpdated(
                        itemIDs: [changedShoppingID],
                        bundleIDs: [changedBundleID]
                    )
                ),
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchId,
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(timeIntervalSince1970: 1),
                    direction: .participantToOwner,
                    kind: .shoppingRemoved(
                        itemIDs: [removedShoppingID],
                        bundleIDs: [removedBundleID]
                    )
                ),
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchId,
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(timeIntervalSince1970: 1),
                    direction: .participantToOwner,
                    kind: .membersChanged(ids: [memberID])
                ),
            ],
            diagnostics: makeDiagnostics(batchId: batchId, reason: .remotePush(context: .sharedDatabase))
        )

        XCTAssertEqual(batch.taskChangedIDs, [addedTaskID, changedTaskID, removedTaskID])
        XCTAssertEqual(batch.ideaChangedIDs, [addedIdeaID, changedIdeaID, removedIdeaID])
        XCTAssertEqual(
            batch.backlogChangedCategoryIDs,
            [addedCategoryID, changedCategoryID, removedCategoryID]
        )
        XCTAssertEqual(
            batch.shoppingChangedItemIDs,
            [addedShoppingID, changedShoppingID, removedShoppingID]
        )
        XCTAssertEqual(batch.memberChangedIDs, [memberID])
    }

    func testClassificationIsBootstrapWhenBatchContainsMembershipChange() {
        let householdId = UUID()
        let batchId = UUID()
        let memberID = UUID()

        let batch = HouseholdSyncBatch(
            events: [
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchId,
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(timeIntervalSince1970: 1),
                    direction: .participantToOwner,
                    kind: .membersChanged(ids: [memberID])
                ),
            ],
            diagnostics: makeDiagnostics(batchId: batchId, reason: .remotePush(context: .sharedDatabase))
        )

        XCTAssertEqual(batch.classification, .bootstrap)
    }

    func testClassificationStaysSteadyStateRemoteForNonMembershipRemotePush() {
        let householdId = UUID()
        let batchId = UUID()

        let batch = HouseholdSyncBatch(
            events: [
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchId,
                    source: .remote,
                    reason: .remotePush(context: .sharedDatabase),
                    timestamp: Date(timeIntervalSince1970: 1),
                    direction: .participantToOwner,
                    kind: .tasksChanged(
                        addedIDs: [UUID()],
                        changedIDs: [],
                        removedIDs: []
                    )
                ),
            ],
            diagnostics: makeDiagnostics(batchId: batchId, reason: .remotePush(context: .sharedDatabase))
        )

        XCTAssertEqual(batch.classification, .steadyStateRemote)
    }

    private func makeDiagnostics(
        batchId: UUID,
        reason: HouseholdSyncReason
    ) -> HouseholdSyncDiagnostics {
        HouseholdSyncDiagnostics(
            batchID: batchId,
            reason: reason,
            direction: .participantToOwner,
            triggerReceivedAt: Date(timeIntervalSince1970: 1),
            syncStartedAt: Date(timeIntervalSince1970: 2),
            syncFinishedAt: Date(timeIntervalSince1970: 3),
            changedDomains: [],
            changedIDsByDomain: [:],
            activeMemberCount: 2
        )
    }
}
