import Foundation
@testable import HousePulse
import XCTest

final class HouseholdSyncBatchTests: XCTestCase {
    func testChangedIDAccessorsUnionAddedChangedAndRemovedIDsAcrossEvents() {
        let ids = makeChangedIDFixture()
        let batch = makeBatch(
            events: [
                makeEvent(
                    kind: .tasksChanged(
                        addedIDs: [ids.addedTaskID],
                        changedIDs: [ids.changedTaskID],
                        removedIDs: [ids.removedTaskID]
                    )
                ),
                makeEvent(
                    kind: .ideasChanged(
                        addedIDs: [ids.addedIdeaID],
                        changedIDs: [ids.changedIdeaID],
                        removedIDs: [ids.removedIdeaID]
                    )
                ),
                makeEvent(
                    kind: .backlogCategoriesChanged(
                        addedIDs: [ids.addedCategoryID],
                        changedIDs: [ids.changedCategoryID],
                        removedIDs: [ids.removedCategoryID]
                    )
                ),
                makeEvent(kind: .shoppingAdded(ids: [ids.addedShoppingID], titles: ["Milk"])),
                makeEvent(
                    kind: .shoppingUpdated(
                        itemIDs: [ids.changedShoppingID],
                        bundleIDs: [ids.changedBundleID]
                    )
                ),
                makeEvent(
                    kind: .shoppingRemoved(
                        itemIDs: [ids.removedShoppingID],
                        bundleIDs: [ids.removedBundleID]
                    )
                ),
                makeEvent(kind: .membersChanged(ids: [ids.memberID]))
            ]
        )

        XCTAssertEqual(batch.taskChangedIDs, [ids.addedTaskID, ids.changedTaskID, ids.removedTaskID])
        XCTAssertEqual(batch.ideaChangedIDs, [ids.addedIdeaID, ids.changedIdeaID, ids.removedIdeaID])
        XCTAssertEqual(batch.backlogChangedCategoryIDs, [ids.addedCategoryID, ids.changedCategoryID, ids.removedCategoryID])
        XCTAssertEqual(batch.shoppingChangedItemIDs, [ids.addedShoppingID, ids.changedShoppingID, ids.removedShoppingID])
        XCTAssertEqual(batch.memberChangedIDs, [ids.memberID])
    }

    func testClassificationIsBootstrapWhenBatchContainsMembershipChange() {
        let batch = makeBatch(events: [makeEvent(kind: .membersChanged(ids: [UUID()]))])

        XCTAssertEqual(batch.classification, .bootstrap)
    }

    func testClassificationStaysSteadyStateRemoteForNonMembershipRemotePush() {
        let batch = makeBatch(
            events: [
                makeEvent(
                    kind: .tasksChanged(
                        addedIDs: [UUID()],
                        changedIDs: [],
                        removedIDs: []
                    )
                )
            ]
        )

        XCTAssertEqual(batch.classification, .steadyStateRemote)
    }

    private func makeBatch(events: [HouseholdSyncEvent]) -> HouseholdSyncBatch {
        let batchId = UUID()
        return HouseholdSyncBatch(
            events: events.map { event in
                HouseholdSyncEvent(
                    householdId: event.householdId,
                    batchID: batchId,
                    source: event.source,
                    reason: event.reason,
                    timestamp: event.timestamp,
                    direction: event.direction,
                    kind: event.kind
                )
            },
            diagnostics: makeDiagnostics(batchId: batchId, reason: .remotePush(context: .sharedDatabase))
        )
    }

    private func makeEvent(kind: HouseholdSyncEventKind) -> HouseholdSyncEvent {
        HouseholdSyncEvent(
            householdId: UUID(),
            batchID: UUID(),
            source: .remote,
            reason: .remotePush(context: .sharedDatabase),
            timestamp: Date(timeIntervalSince1970: 1),
            direction: .participantToOwner,
            kind: kind
        )
    }

    private func makeChangedIDFixture() -> ChangedIDFixture {
        ChangedIDFixture(
            addedTaskID: UUID(),
            changedTaskID: UUID(),
            removedTaskID: UUID(),
            addedIdeaID: UUID(),
            changedIdeaID: UUID(),
            removedIdeaID: UUID(),
            addedCategoryID: UUID(),
            changedCategoryID: UUID(),
            removedCategoryID: UUID(),
            addedShoppingID: UUID(),
            changedShoppingID: UUID(),
            changedBundleID: UUID(),
            removedShoppingID: UUID(),
            removedBundleID: UUID(),
            memberID: UUID()
        )
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

private struct ChangedIDFixture {
    let addedTaskID: UUID
    let changedTaskID: UUID
    let removedTaskID: UUID
    let addedIdeaID: UUID
    let changedIdeaID: UUID
    let removedIdeaID: UUID
    let addedCategoryID: UUID
    let changedCategoryID: UUID
    let removedCategoryID: UUID
    let addedShoppingID: UUID
    let changedShoppingID: UUID
    let changedBundleID: UUID
    let removedShoppingID: UUID
    let removedBundleID: UUID
    let memberID: UUID
}
