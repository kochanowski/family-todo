import Foundation

struct HouseholdSyncVisibleChanges: Equatable {
    let contentDiff: RemoteVisibleContentDiff?
    let taskDiff: RemoteTaskVisibleContentDiff?
    let ideaDiff: RemoteIdeaVisibleContentDiff?

    static let empty = HouseholdSyncVisibleChanges(
        contentDiff: nil,
        taskDiff: nil,
        ideaDiff: nil
    )

    var shoppingChangedItemIDs: Set<UUID> {
        guard let contentDiff else { return [] }
        return contentDiff.addedShoppingItemIDs
            .union(contentDiff.changedShoppingItemIDs)
            .union(contentDiff.removedShoppingItemIDs)
    }

    var backlogChangedCategoryIDs: Set<UUID> {
        guard let contentDiff else { return [] }
        return contentDiff.addedBacklogCategoryIDs
            .union(contentDiff.changedBacklogCategoryIDs)
            .union(contentDiff.removedBacklogCategoryIDs)
    }

    var taskChangedIDs: Set<UUID> {
        if let taskDiff {
            return taskDiff.addedTaskIDs
                .union(taskDiff.changedTaskIDs)
                .union(taskDiff.removedTaskIDs)
        }
        guard let contentDiff else { return [] }
        return contentDiff.addedTaskIDs
            .union(contentDiff.changedTaskIDs)
            .union(contentDiff.removedTaskIDs)
    }

    var ideaChangedIDs: Set<UUID> {
        if let ideaDiff {
            return ideaDiff.addedIdeaIDs
                .union(ideaDiff.changedIdeaIDs)
                .union(ideaDiff.removedIdeaIDs)
        }
        guard let contentDiff else { return [] }
        return contentDiff.addedIdeaIDs
            .union(contentDiff.changedIdeaIDs)
            .union(contentDiff.removedIdeaIDs)
    }

    var memberChangedIDs: Set<UUID> {
        guard let contentDiff else { return [] }
        return contentDiff.addedMemberIDs
            .union(contentDiff.changedMemberIDs)
            .union(contentDiff.removedMemberIDs)
    }

    var legacyTaskPresentationDiff: RemoteTaskVisibleContentDiff? {
        if let taskDiff {
            return taskDiff
        }
        guard let contentDiff else { return nil }
        return RemoteTaskVisibleContentDiff(
            addedTaskIDs: contentDiff.addedTaskIDs,
            removedTaskIDs: contentDiff.removedTaskIDs,
            changedTaskIDs: contentDiff.changedTaskIDs
        )
    }
}

extension HouseholdSyncBatch {
    var remoteSyncAnimationPayload: RemoteSyncAnimationPayload {
        RemoteSyncAnimationPayload(
            batchToken: id,
            shoppingChangedItemIDs: shoppingChangedItemIDs,
            workItemChangedIDs: taskChangedIDs.union(ideaChangedIDs),
            backlogChangedCategoryIDs: backlogChangedCategoryIDs,
            direction: diagnostics.direction.rawValue,
            pushReceivedAt: diagnostics.triggerReceivedAt,
            cacheUpdatedAt: diagnostics.syncFinishedAt
        )
    }

    var tasksScreenRefresh: HouseholdTasksScreenRefresh? {
        guard !domains.isDisjoint(with: [.tasks, .members, .backlog, .ideas]) else {
            return nil
        }

        return HouseholdTasksScreenRefresh(
            classification: classification,
            changedTaskIDs: taskChangedIDs,
            animationPayload: remoteSyncAnimationPayload
        )
    }

    var backlogScreenRefresh: HouseholdBacklogScreenRefresh? {
        guard !domains.isDisjoint(with: [.ideas, .backlog, .members, .tasks]) else {
            return nil
        }

        return HouseholdBacklogScreenRefresh(
            classification: classification,
            changedCategoryIDs: backlogChangedCategoryIDs,
            changedIdeaIDs: ideaChangedIDs,
            animationPayload: remoteSyncAnimationPayload
        )
    }
}

struct HouseholdTasksScreenRefresh: Equatable {
    let classification: HouseholdSyncBatchClassification
    let changedTaskIDs: Set<UUID>
    let animationPayload: RemoteSyncAnimationPayload

    var isBootstrap: Bool {
        classification == .bootstrap
    }
}

struct HouseholdBacklogScreenRefresh: Equatable {
    let classification: HouseholdSyncBatchClassification
    let changedCategoryIDs: Set<UUID>
    let changedIdeaIDs: Set<UUID>
    let animationPayload: RemoteSyncAnimationPayload

    var isBootstrap: Bool {
        classification == .bootstrap
    }
}
