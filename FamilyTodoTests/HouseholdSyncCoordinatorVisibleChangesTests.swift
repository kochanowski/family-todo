import Foundation
@testable import HousePulse
import UIKit
import XCTest

@MainActor
final class HouseholdSyncCoordinatorVisibleChangesTests: XCTestCase {
    func testPerformSyncPublishesPrecomputedVisibleChangesOnLatestBatch() async {
        let memberID = UUID()
        let taskID = UUID()
        let ideaID = UUID()
        let backlogCategoryID = UUID()
        let visibleChanges = HouseholdSyncVisibleChanges(
            contentDiff: RemoteVisibleContentDiff(
                addedMemberIDs: [memberID],
                removedMemberIDs: [],
                changedMemberIDs: [],
                addedShoppingItemIDs: [],
                addedShoppingTitles: [],
                addedShoppingBundleIDs: [],
                addedTaskIDs: [taskID],
                addedIdeaIDs: [ideaID],
                addedBacklogCategoryIDs: [backlogCategoryID],
                removedShoppingItemIDs: [],
                removedShoppingBundleIDs: [],
                removedTaskIDs: [],
                removedIdeaIDs: [],
                removedBacklogCategoryIDs: [],
                changedShoppingItemIDs: [],
                changedShoppingBundleIDs: [],
                changedWorkItemIDs: [],
                changedTaskIDs: [],
                changedIdeaIDs: [],
                changedBacklogCategoryIDs: []
            ),
            taskDiff: RemoteTaskVisibleContentDiff(
                addedTaskIDs: [taskID],
                removedTaskIDs: [],
                changedTaskIDs: []
            ),
            ideaDiff: RemoteIdeaVisibleContentDiff(
                addedIdeaIDs: [ideaID],
                removedIdeaIDs: [],
                changedIdeaIDs: []
            )
        )
        let engine = VisibleChangesFakeHouseholdSyncEngine(
            results: [
                HouseholdSyncPassResult(
                    fetchResult: .newData,
                    events: [],
                    diagnostics: HouseholdSyncDiagnostics(
                        batchID: UUID(),
                        reason: .remotePush(context: .sharedDatabase),
                        direction: .ownerToParticipant,
                        triggerReceivedAt: Date(timeIntervalSince1970: 50),
                        syncStartedAt: Date(timeIntervalSince1970: 51),
                        syncFinishedAt: Date(timeIntervalSince1970: 52),
                        changedDomains: Set([.members, .tasks, .ideas, .backlog]),
                        changedIDsByDomain: [:],
                        activeMemberCount: 2
                    ),
                    visibleChanges: visibleChanges
                ),
            ]
        )
        let coordinator = HouseholdSyncCoordinator(engine: engine)

        let result = await coordinator.performSync(reason: .remotePush(context: .sharedDatabase))

        XCTAssertEqual(result, .newData)
        XCTAssertEqual(coordinator.latestBatch?.memberChangedIDs, Set([memberID]))
        XCTAssertEqual(coordinator.latestBatch?.taskChangedIDs, Set([taskID]))
        XCTAssertEqual(coordinator.latestBatch?.ideaChangedIDs, Set([ideaID]))
        XCTAssertEqual(coordinator.latestBatch?.backlogChangedCategoryIDs, Set([backlogCategoryID]))
    }
}

@MainActor
private final class VisibleChangesFakeHouseholdSyncEngine: HouseholdSyncEngine {
    private var results: [HouseholdSyncPassResult]

    init(results: [HouseholdSyncPassResult]) {
        self.results = results
    }

    func runSync(for _: HouseholdSyncReason) async -> HouseholdSyncPassResult {
        results.removeFirst()
    }
}
