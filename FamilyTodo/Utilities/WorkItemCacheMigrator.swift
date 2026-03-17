import Foundation
import SwiftData

@MainActor
enum WorkItemCacheMigrator {
    private static let defaultsKey = "work_item_cache_migration_v1_complete"

    static func migrateIfNeeded(
        context: ModelContext,
        userDefaults: UserDefaults = .standard
    ) {
        guard !userDefaults.bool(forKey: defaultsKey) else { return }

        let taskDescriptor = FetchDescriptor<CachedTask>()
        let backlogDescriptor = FetchDescriptor<CachedBacklogItem>()
        let workItemDescriptor = FetchDescriptor<CachedWorkItem>()

        do {
            let existingWorkItems = try context.fetch(workItemDescriptor)
            let cachedTasks = try context.fetch(taskDescriptor)
            let cachedIdeas = try context.fetch(backlogDescriptor)

            var mergedByLogicalID = Dictionary(
                uniqueKeysWithValues: existingWorkItems.map { ($0.logicalItemID, $0) }
            )

            for cachedTask in cachedTasks {
                let item = cachedTask.toTask()
                let workItem = WorkItem(task: item)
                let logicalID = workItem.logicalItemID

                if let existing = mergedByLogicalID[logicalID] {
                    if shouldReplace(existing: existing.toWorkItem(), with: workItem) {
                        existing.update(from: workItem)
                    }
                } else {
                    let cached = CachedWorkItem(from: workItem)
                    context.insert(cached)
                    mergedByLogicalID[logicalID] = cached
                }
            }

            for cachedIdea in cachedIdeas {
                let item = cachedIdea.toBacklogItem()
                let workItem = WorkItem(idea: item)
                let logicalID = workItem.logicalItemID

                if let existing = mergedByLogicalID[logicalID] {
                    if shouldReplace(existing: existing.toWorkItem(), with: workItem) {
                        existing.update(from: workItem)
                    }
                } else {
                    let cached = CachedWorkItem(from: workItem)
                    context.insert(cached)
                    mergedByLogicalID[logicalID] = cached
                }
            }

            if context.hasChanges {
                try context.save()
            }
            userDefaults.set(true, forKey: defaultsKey)
        } catch {
            print("Failed to migrate legacy task/backlog cache to work items: \(error)")
        }
    }

    private static func shouldReplace(existing: WorkItem, with candidate: WorkItem) -> Bool {
        let existingPriority = statusPriority(existing.status)
        let candidatePriority = statusPriority(candidate.status)

        if candidatePriority != existingPriority {
            return candidatePriority > existingPriority
        }

        if candidate.updatedAt != existing.updatedAt {
            return candidate.updatedAt > existing.updatedAt
        }

        return candidate.createdAt > existing.createdAt
    }

    private static func statusPriority(_ status: WorkItem.Status) -> Int {
        switch status {
        case .done:
            4
        case .next:
            3
        case .backlog:
            2
        case .idea:
            1
        }
    }
}
