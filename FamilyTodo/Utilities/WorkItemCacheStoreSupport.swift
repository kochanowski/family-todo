import Foundation
import SwiftData

@MainActor
enum WorkItemCacheStoreSupport {
    static let synced = "synced"
    static let pendingUpload = "pendingUpload"
    static let pendingDelete = "pendingDelete"
    static let awaitingCloudEcho = "awaitingCloudEcho"

    struct PendingSnapshot {
        var pendingUploadByID: [UUID: WorkItem]
        var pendingDeleteIDs: Set<UUID>
        var pendingDeleteLogicalItemIDs: Set<UUID>
    }

    static func fetchCachedWorkItems(
        householdId: UUID?,
        context: ModelContext,
        migrateLegacyCache: Bool = true
    ) -> [CachedWorkItem] {
        if migrateLegacyCache {
            WorkItemCacheMigrator.migrateIfNeeded(context: context)
        }

        if let householdId {
            let descriptor = FetchDescriptor<CachedWorkItem>(
                predicate: #Predicate { $0.householdId == householdId }
            )
            return (try? context.fetch(descriptor)) ?? []
        }

        return (try? context.fetch(FetchDescriptor<CachedWorkItem>())) ?? []
    }

    static func isPendingCloudMutation(status: String) -> Bool {
        status == pendingUpload || status == awaitingCloudEcho
    }

    static func isTombstoned(
        cachedStatus: String,
        id: UUID,
        logicalItemID: UUID,
        pendingDeleteIDs: Set<UUID>,
        pendingDeleteLogicalItemIDs: Set<UUID>
    ) -> Bool {
        cachedStatus == pendingDelete ||
            pendingDeleteIDs.contains(id) ||
            pendingDeleteLogicalItemIDs.contains(logicalItemID)
    }

    static func shouldIgnoreCloudSnapshot(
        _ cloudItem: WorkItem,
        for localCachedItem: CachedWorkItem,
        pendingSnapshot: PendingSnapshot,
        mutationEchoMatches: (WorkItem, WorkItem) -> Bool
    ) -> Bool {
        let localLogicalItemID = resolvedLogicalItemID(for: localCachedItem)

        if isTombstoned(
            cachedStatus: localCachedItem.syncStatusRaw,
            id: localCachedItem.id,
            logicalItemID: localLogicalItemID,
            pendingDeleteIDs: pendingSnapshot.pendingDeleteIDs,
            pendingDeleteLogicalItemIDs: pendingSnapshot.pendingDeleteLogicalItemIDs
        ) {
            return true
        }

        let localItem = localCachedItem.toWorkItem()
        if isPendingCloudMutation(status: localCachedItem.syncStatusRaw),
           let localMutation = pendingSnapshot.pendingUploadByID[localCachedItem.id]
        {
            if !mutationEchoMatches(cloudItem, localMutation) {
                return true
            }
            return cloudItem.updatedAt < localMutation.updatedAt
        }

        return cloudItem.updatedAt < localItem.updatedAt ||
            cloudItem.logicalItemID != localLogicalItemID
    }

    static func upsert(
        _ item: WorkItem,
        syncStatusRaw: String,
        lastSyncedAt: Date?,
        context: ModelContext,
        shouldSave: Bool,
        save: (String) -> Bool
    ) {
        let descriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.id == item.id }
        )

        if let cached = try? context.fetch(descriptor).first {
            cached.update(from: item)
            cached.syncStatusRaw = syncStatusRaw
            cached.lastSyncedAt = lastSyncedAt
        } else {
            let cached = CachedWorkItem(from: item)
            cached.syncStatusRaw = syncStatusRaw
            cached.lastSyncedAt = lastSyncedAt
            context.insert(cached)
        }

        if shouldSave {
            _ = save("persist work item cache")
        }
    }

    static func markPendingDelete(
        _ item: WorkItem,
        context: ModelContext,
        shouldSave: Bool,
        save: (String) -> Bool
    ) {
        let descriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.id == item.id }
        )

        if let cached = try? context.fetch(descriptor).first {
            cached.update(from: item)
            cached.syncStatusRaw = pendingDelete
            cached.lastSyncedAt = nil
        } else {
            let cached = CachedWorkItem(from: item)
            cached.syncStatusRaw = pendingDelete
            cached.lastSyncedAt = nil
            context.insert(cached)
        }

        if shouldSave {
            _ = save("mark work item pending delete")
        }
    }

    static func markAwaitingCloudEcho(
        id: UUID,
        context: ModelContext,
        shouldSave: Bool,
        save: (String) -> Bool
    ) {
        let descriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            cached.syncStatusRaw = awaitingCloudEcho
            cached.lastSyncedAt = Date()
            if shouldSave {
                _ = save("mark work item awaiting cloud echo")
            }
        }
    }

    static func remove(
        id: UUID,
        context: ModelContext,
        shouldSave: Bool,
        save: (String) -> Bool
    ) {
        let descriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            context.delete(cached)
            if shouldSave {
                _ = save("remove work item cache")
            }
        }
    }

    static func resolvedLogicalItemID(for cached: CachedWorkItem) -> UUID {
        cached.logicalItemID
    }

    static func canonicalCachedWorkItemsByLogicalItemID(
        _ cachedItems: [CachedWorkItem]
    ) -> [UUID: CachedWorkItem] {
        var deduplicated: [UUID: CachedWorkItem] = [:]

        for cached in cachedItems {
            let logicalItemID = resolvedLogicalItemID(for: cached)
            if let existing = deduplicated[logicalItemID] {
                if shouldPreferCachedWorkItem(cached, over: existing) {
                    deduplicated[logicalItemID] = cached
                }
            } else {
                deduplicated[logicalItemID] = cached
            }
        }

        return deduplicated
    }

    static func visibleTasks(from cachedItems: [CachedWorkItem]) -> [Task] {
        // Only tasks going pendingDelete tombstone the tasks list.
        // An idea going pendingDelete (during promotion) must not suppress the promoted Task.
        let tombstonedLogicalItemIDs = Set(
            cachedItems.compactMap { cached -> UUID? in
                guard cached.syncStatusRaw == pendingDelete else { return nil }
                guard cached.toWorkItem().asTask() != nil else { return nil }
                return resolvedLogicalItemID(for: cached)
            }
        )

        return canonicalCachedWorkItemsByLogicalItemID(cachedItems)
            .filter { !tombstonedLogicalItemIDs.contains($0.key) }
            .values
            .filter { $0.syncStatusRaw != pendingDelete }
            .compactMap { $0.toWorkItem().asTask() }
            .sorted(by: taskSort)
    }

    static func visibleIdeas(from cachedItems: [CachedWorkItem]) -> [BacklogItem] {
        // Only ideas going pendingDelete tombstone the ideas list.
        // A task going pendingDelete (during demotion) must not suppress the new BacklogItem.
        let tombstonedLogicalItemIDs = Set(
            cachedItems.compactMap { cached -> UUID? in
                guard cached.syncStatusRaw == pendingDelete else { return nil }
                guard cached.toWorkItem().asBacklogItem() != nil else { return nil }
                return resolvedLogicalItemID(for: cached)
            }
        )

        return canonicalCachedWorkItemsByLogicalItemID(cachedItems)
            .filter { !tombstonedLogicalItemIDs.contains($0.key) }
            .values
            .filter { $0.syncStatusRaw != pendingDelete }
            .compactMap { $0.toWorkItem().asBacklogItem() }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    static func pendingSnapshot(from cachedItems: [CachedWorkItem]) -> PendingSnapshot {
        var pendingUploadByID: [UUID: WorkItem] = [:]
        var pendingDeleteIDs = Set<UUID>()
        var pendingDeleteLogicalItemIDs = Set<UUID>()

        for cached in cachedItems {
            switch cached.syncStatusRaw {
            case pendingUpload, awaitingCloudEcho:
                pendingUploadByID[cached.id] = cached.toWorkItem()
            case pendingDelete:
                pendingDeleteIDs.insert(cached.id)
                pendingDeleteLogicalItemIDs.insert(resolvedLogicalItemID(for: cached))
            default:
                continue
            }
        }

        return PendingSnapshot(
            pendingUploadByID: pendingUploadByID,
            pendingDeleteIDs: pendingDeleteIDs,
            pendingDeleteLogicalItemIDs: pendingDeleteLogicalItemIDs
        )
    }

    static func deduplicatedCloudWorkItems(_ items: [WorkItem]) -> [WorkItem] {
        var deduplicated: [UUID: WorkItem] = [:]

        for item in items {
            if let existing = deduplicated[item.logicalItemID] {
                if shouldPreferCloudWorkItem(item, over: existing) {
                    deduplicated[item.logicalItemID] = item
                }
            } else {
                deduplicated[item.logicalItemID] = item
            }
        }

        return Array(deduplicated.values)
    }

    private static func shouldPreferCachedWorkItem(
        _ candidate: CachedWorkItem,
        over current: CachedWorkItem
    ) -> Bool {
        let candidatePriority = syncPriority(candidate.syncStatusRaw)
        let currentPriority = syncPriority(current.syncStatusRaw)
        if candidatePriority != currentPriority {
            return candidatePriority > currentPriority
        }
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }
        if candidate.createdAt != current.createdAt {
            return candidate.createdAt > current.createdAt
        }
        return candidate.id.uuidString < current.id.uuidString
    }

    private static func shouldPreferCloudWorkItem(_ candidate: WorkItem, over current: WorkItem) -> Bool {
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }
        if candidate.createdAt != current.createdAt {
            return candidate.createdAt > current.createdAt
        }
        return candidate.id.uuidString < current.id.uuidString
    }

    private static func syncPriority(_ syncStatusRaw: String) -> Int {
        switch syncStatusRaw {
        case pendingUpload, awaitingCloudEcho:
            3
        case synced:
            2
        case pendingDelete:
            0
        default:
            1
        }
    }

    private static func taskSort(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
