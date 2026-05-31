import Foundation
import SwiftData
import SwiftUI

/// Store for shared shopping list management
@MainActor
final class ShoppingListStore: ObservableObject {
    @Published private(set) var items: [ShoppingItem] = []
    @Published private(set) var hasHydratedLocalSnapshot = false
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingInBackground = false
    @Published private(set) var error: Error?

    private lazy var cloudKit = CloudKitManager.shared
    private let householdId: UUID?
    private var modelContext: ModelContext?
    private var syncMode: SyncMode = .cloud
    private var syncContext: HouseholdSyncContext?
    private var isReplayingPendingMutations = false
    private var shouldReplayPendingMutationsAfterCurrentPass = false
    private var activeLoadTask: _Concurrency.Task<Void, Never>?
    private var shouldReloadAfterCurrentLoad = false
    private var hasHydratedVisibleSnapshot = false
    private var needsLocalRehydrate = false

    struct PendingSyncSnapshot {
        var pendingUploadByID: [UUID: ShoppingItem]
        var pendingDeleteIDs: Set<UUID>
    }

    private enum ShoppingSyncPolicy {
        static let awaitingCloudEchoGraceDuration: TimeInterval = 45
    }

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
    }

    func setCloudContext(_ syncContext: HouseholdSyncContext?) {
        self.syncContext = syncContext
    }

    func setCloudContext(currentUserId: String?, householdOwnerId: String?) {
        syncContext = HouseholdSyncContextFactory.make(
            householdId: householdId,
            ownerUserId: householdOwnerId,
            currentUserId: currentUserId
        )
    }

    private var isCloudSyncEnabled: Bool {
        syncMode == .cloud
    }

    private var cloudScope: CloudKitManager.HouseholdDatabaseScope {
        syncContext?.scope ?? .participantShared
    }

    init(householdId: UUID?, modelContext: ModelContext? = nil) {
        self.householdId = householdId
        self.modelContext = modelContext
        hydrateVisibleSnapshotFromCacheIfNeeded(force: true)
    }

    @discardableResult
    private func saveContextOrSetError(
        _ context: ModelContext? = nil,
        operation: String = "persist shopping cache",
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        StoreContextSaver.saveContextOrSetError(
            context ?? modelContext,
            store: "ShoppingListStore",
            operation: operation,
            file: file,
            line: line
        ) { [self] saveError in
            error = saveError
        }
    }

    /// Set model context for offline caching
    func setModelContext(_ context: ModelContext) {
        modelContext = context
        hydrateVisibleSnapshotFromCacheIfNeeded(force: true)
    }

    var toBuyItems: [ShoppingItem] {
        items
            .filter { !$0.isBought }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var boughtItems: [ShoppingItem] {
        items
            .filter(\.isBought)
            .sorted {
                if $0.restockCount != $1.restockCount {
                    return $0.restockCount > $1.restockCount
                }
                return $0.updatedAt > $1.updatedAt
            }
    }

    /// Recently purchased list deduplicated by normalized title.
    /// Keeps the most recently purchased record for each product name.
    var recentItems: [ShoppingItem] {
        let purchased = items.filter(\.isBought)
        let grouped = Dictionary(grouping: purchased) { normalizedRecentKey($0.title) }

        return grouped.compactMap { _, records in
            records.max { recentTimestamp(for: $0) < recentTimestamp(for: $1) }
        }
        .sorted { recentTimestamp(for: $0) > recentTimestamp(for: $1) }
    }

    // MARK: - Load Items

    func loadItemsForDisplay() async {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: !hasHydratedVisibleSnapshot || items.isEmpty)
        guard isCloudSyncEnabled else { return }
        scheduleBackgroundRefresh()
    }

    func loadItems() async {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: !hasHydratedVisibleSnapshot || items.isEmpty)
        guard isCloudSyncEnabled else { return }
        let loadTask = ensureBackgroundRefreshTask()
        await loadTask.value
    }

    private func scheduleBackgroundRefresh() {
        _ = ensureBackgroundRefreshTask()
    }

    private func ensureBackgroundRefreshTask() -> _Concurrency.Task<Void, Never> {
        if let activeLoadTask {
            shouldReloadAfterCurrentLoad = true
            return activeLoadTask
        }

        let loadTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }

            repeat {
                shouldReloadAfterCurrentLoad = false
                await performLoadItemsPass()
            } while shouldReloadAfterCurrentLoad

            activeLoadTask = nil
        }

        activeLoadTask = loadTask
        return loadTask
    }

    private func performLoadItemsPass() async {
        guard let householdId else { return }

        isLoading = true
        isRefreshingInBackground = true
        error = nil
        defer {
            isLoading = false
            isRefreshingInBackground = false
        }

        // 1. Load from cache first (instant UI)
        hydrateVisibleSnapshotFromCacheIfNeeded(force: !hasHydratedVisibleSnapshot || items.isEmpty)

        if !isCloudSyncEnabled {
            return
        }

        // 2. Sync with CloudKit in background
        do {
            // Ensure CloudKit is ready before accessing
            await cloudKit.ensureReady()
            let fetchedItems = try await cloudKit.fetchShoppingItems(
                householdId: householdId,
                scope: cloudScope
            )
            let latestCachedItems = fetchCachedItems(updateVisibleState: false)
            let latestPendingSnapshot = pendingSyncSnapshot(from: latestCachedItems)
            items = mergeCloudSnapshot(fetchedItems, with: latestPendingSnapshot)

            // 3. Update cache
            syncToCache(fetchedItems)
            replayPendingMutationsInBackground()
        } catch {
            // Keep cached data on error
            self.error = error
        }
    }

    private func hydrateVisibleSnapshotFromCacheIfNeeded(force: Bool = false) {
        _ = fetchCachedItems(
            updateVisibleState: force || needsLocalRehydrate || !hasHydratedVisibleSnapshot || items.isEmpty
        )
    }

    private func fetchCachedItems(updateVisibleState: Bool) -> [CachedShoppingItem] {
        guard let context = modelContext, let householdId else {
            if updateVisibleState {
                items = []
                hasHydratedVisibleSnapshot = true
                hasHydratedLocalSnapshot = true
            }
            return []
        }

        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        let cachedItems = (try? context.fetch(descriptor)) ?? []
        if updateVisibleState {
            items = cachedItems
                .filter { $0.syncStatusRaw != "pendingDelete" }
                .map { $0.toShoppingItem() }
            hasHydratedVisibleSnapshot = true
            hasHydratedLocalSnapshot = true
            needsLocalRehydrate = false
        }
        return cachedItems
    }

    func markLocalSnapshotStale() {
        needsLocalRehydrate = true
    }

    func rehydrateVisibleSnapshotFromCache() {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: true)
    }

    func replayPendingMutationsIfNeeded() {
        guard isCloudSyncEnabled else { return }
        replayPendingMutationsInBackground()
    }

    func syncToCache(_ items: [ShoppingItem]) {
        guard let context = modelContext, let householdId else { return }
        let syncTimestamp = Date()
        let cloudItemIDs = Set(items.map(\.id))

        let cacheDescriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedItems = (try? context.fetch(cacheDescriptor)) ?? []
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedItems.map { ($0.id, $0) })

        // Build the set of locally-tombstoned IDs so we never resurrect
        // items that the local device has already marked for deletion.
        let pendingDeleteIDs = Set(
            cachedItems
                .filter { $0.syncStatusRaw == "pendingDelete" }
                .map(\.id)
        )

        for item in items {
            // Fix #1 — tombstone guard: skip cloud item whose local copy is pending delete.
            // Without this, a cloud echo from another member can resurrect an item the local
            // user already deleted before the delete reaches CloudKit.
            if pendingDeleteIDs.contains(item.id) {
                continue
            }

            if let existing = cachedByID[item.id] {
                if existing.syncStatusRaw == "pendingDelete" {
                    continue
                }
                if existing.syncStatusRaw == "pendingUpload" || existing.syncStatusRaw == "awaitingCloudEcho",
                   !isExpiredAwaitingCloudEcho(existing, relativeTo: syncTimestamp),
                   !cloudShoppingItemMatchesLocalMutationEcho(item, localItem: existing.toShoppingItem())
                {
                    continue
                }
                existing.update(from: item)
                existing.syncStatusRaw = "synced"
                existing.lastSyncedAt = syncTimestamp
            } else {
                let cached = CachedShoppingItem(from: item)
                cached.syncStatusRaw = "synced"
                cached.lastSyncedAt = syncTimestamp
                context.insert(cached)
            }
        }

        // Fix #2 — orphan cleanup: remove cache entries no longer present in the cloud
        // snapshot, scoped to each status bucket:
        // • synced → deleted remotely by another member; remove from local cache.
        // • awaitingCloudEcho (expired) → grace period elapsed, still not in cloud; remove.
        // • pendingUpload / non-expired awaitingCloudEcho → in-flight mutation; keep.
        // • pendingDelete → flushPendingSync will handle the remote delete; keep.
        for cached in cachedItems where !cloudItemIDs.contains(cached.id) {
            switch cached.syncStatusRaw {
            case "synced":
                context.delete(cached)
            case "awaitingCloudEcho":
                if isExpiredAwaitingCloudEcho(cached, relativeTo: syncTimestamp) {
                    context.delete(cached)
                }
            default:
                break
            }
        }

        saveContextOrSetError(context, operation: "sync shopping cache from cloud")
    }

    private func replayPendingMutationsInBackground() {
        if isReplayingPendingMutations {
            shouldReplayPendingMutationsAfterCurrentPass = true
            return
        }
        isReplayingPendingMutations = true

        _ = _Concurrency.Task(priority: .utility) { [self] in
            while true {
                shouldReplayPendingMutationsAfterCurrentPass = false
                await flushPendingSync()
                if !shouldReplayPendingMutationsAfterCurrentPass {
                    break
                }
            }
            isReplayingPendingMutations = false
        }
    }

    private func flushPendingSync() async {
        guard isCloudSyncEnabled, let context = modelContext, let householdId else { return }

        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedItems = (try? context.fetch(descriptor)) ?? []

        let pendingUploads = cachedItems.filter { $0.syncStatusRaw == "pendingUpload" }
        let pendingDeletes = cachedItems.filter { $0.syncStatusRaw == "pendingDelete" }

        guard !pendingUploads.isEmpty || !pendingDeletes.isEmpty else { return }

        var didMutateCache = false

        if !pendingUploads.isEmpty {
            let pendingItems = pendingUploads.map { $0.toShoppingItem() }
            let syncedAt = Date()

            do {
                if pendingItems.count == 1, let item = pendingItems.first {
                    _ = try await cloudKit.saveShoppingItem(item, scope: cloudScope)
                } else {
                    try await cloudKit.saveShoppingItemsBatch(
                        pendingItems,
                        scope: cloudScope
                    )
                }

                for cached in pendingUploads {
                    cached.syncStatusRaw = "awaitingCloudEcho"
                    cached.lastSyncedAt = syncedAt
                }
                didMutateCache = true
            } catch {
                self.error = error

                for cached in pendingUploads {
                    do {
                        _ = try await cloudKit.saveShoppingItem(
                            cached.toShoppingItem(),
                            scope: cloudScope
                        )
                        cached.syncStatusRaw = "awaitingCloudEcho"
                        cached.lastSyncedAt = syncedAt
                        didMutateCache = true
                    } catch {
                        self.error = error
                    }
                }
            }
        }

        for cached in pendingDeletes {
            do {
                try await cloudKit.deleteShoppingItem(
                    id: cached.id,
                    householdId: cached.householdId,
                    scope: cloudScope
                )
                context.delete(cached)
                items.removeAll { $0.id == cached.id }
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        if didMutateCache {
            saveContextOrSetError(context, operation: "flush pending shopping sync mutations")
        }
    }

    // MARK: - Create Item

    @discardableResult
    func createItem(
        title: String,
        quantityValue: String? = nil,
        quantityUnit: String? = nil,
        afterItemId: UUID? = nil
    ) async -> ShoppingItem? {
        guard let householdId else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        var item = ShoppingItem(
            householdId: householdId,
            title: trimmedTitle,
            quantityValue: quantityValue,
            quantityUnit: quantityUnit,
            isBought: false,
            sortOrder: nextToBuySortOrder()
        )

        let syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
        let lastSyncedAt = isCloudSyncEnabled ? nil : Date()

        items.append(item)

        if let afterItemId {
            let reorderedItems = reorderedToBuyItems(inserting: item.id, after: afterItemId)
            let persistedOrder = applyToBuyOrder(reorderedItems)
            if let updatedItem = persistedOrder.first(where: { $0.id == item.id }) {
                item = updatedItem
            }
            upsertCachedItems(
                persistedOrder,
                syncStatusRaw: syncStatusRaw,
                lastSyncedAt: lastSyncedAt
            )
        } else {
            upsertCachedItem(
                item,
                syncStatusRaw: syncStatusRaw,
                lastSyncedAt: lastSyncedAt
            )
        }

        AppAnalytics.capture(
            "shopping_item_added",
            properties: [
                "has_quantity": quantityValue != nil,
                "is_inline_insert": afterItemId != nil,
            ],
            syncMode: syncMode,
            householdId: householdId
        )
        AppAnalytics.activationMilestone(
            .shoppingItemAdded,
            syncMode: syncMode,
            householdId: householdId
        )
        AppAnalytics.firstValueCompleted(
            source: .shoppingItem,
            syncMode: syncMode,
            householdId: householdId
        )

        if !isCloudSyncEnabled {
            return item
        }
        replayPendingMutationsInBackground()
        return item
    }

    func createItems(fromTitles titles: [String]) async -> Int {
        guard let householdId else { return 0 }

        let cleanedTitles = titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedTitles.isEmpty else { return 0 }

        let initialSortOrder = nextToBuySortOrder()
        let newItems = cleanedTitles.enumerated().map { offset, title in
            ShoppingItem(
                householdId: householdId,
                title: title,
                isBought: false,
                sortOrder: initialSortOrder + offset
            )
        }

        withAnimation(WowAnimation.spring) {
            items.append(contentsOf: newItems)
        }

        upsertCachedItems(
            newItems,
            syncStatusRaw: isCloudSyncEnabled ? "pendingUpload" : "synced",
            lastSyncedAt: isCloudSyncEnabled ? nil : Date()
        )

        if isCloudSyncEnabled {
            replayPendingMutationsInBackground()
        }

        return newItems.count
    }

    private func reorderedToBuyItems(inserting insertedItemId: UUID, after afterItemId: UUID) -> [ShoppingItem] {
        var orderedItems = toBuyItems
        guard let insertedIndex = orderedItems.firstIndex(where: { $0.id == insertedItemId }) else {
            return orderedItems
        }

        let insertedItem = orderedItems.remove(at: insertedIndex)

        if let anchorIndex = orderedItems.firstIndex(where: { $0.id == afterItemId }) {
            orderedItems.insert(insertedItem, at: anchorIndex + 1)
        } else {
            orderedItems.append(insertedItem)
        }

        return orderedItems
    }

    // MARK: - Update Item

    func updateItem(_ item: ShoppingItem) async {
        var updatedItem = item
        updatedItem.updatedAt = Date()

        // Optimistic UI update with animation
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                items[index] = updatedItem
            }
        }

        // Save to cache with pending status, then let replayPendingMutationsInBackground
        // handle the CloudKit write. This matches the createItem pattern and avoids a
        // dual-write race where both updateItem and flushPendingSync could attempt to
        // save the same record to CloudKit concurrently.
        upsertCachedItem(
            updatedItem,
            syncStatusRaw: isCloudSyncEnabled ? "pendingUpload" : "synced",
            lastSyncedAt: isCloudSyncEnabled ? nil : Date()
        )

        if isCloudSyncEnabled {
            replayPendingMutationsInBackground()
        }
    }

    // MARK: - Toggle Bought

    func toggleBought(_ item: ShoppingItem) async {
        var updatedItem = item
        updatedItem.isBought.toggle()
        if updatedItem.isBought {
            updatedItem.boughtAt = Date()
        } else {
            updatedItem.boughtAt = nil
            updatedItem.restockCount += 1
            updatedItem.sortOrder = nextToBuySortOrder()
        }
        await updateItem(updatedItem)
    }

    /// Restores a recent item to the active shopping list.
    /// After restore, the product name disappears from Recent.
    func restoreRecentItem(_ item: ShoppingItem) async {
        let key = normalizedRecentKey(item.title)
        let matchingBought = items.filter { $0.isBought && normalizedRecentKey($0.title) == key }
        guard
            let latest = matchingBought.max(by: {
                recentTimestamp(for: $0) < recentTimestamp(for: $1)
            })
        else {
            return
        }

        var restored = latest
        restored.isBought = false
        restored.boughtAt = nil
        restored.restockCount += 1
        restored.sortOrder = nextToBuySortOrder()
        restored.updatedAt = Date()
        await updateItem(restored)

        for duplicate in matchingBought where duplicate.id != restored.id {
            await deleteItem(duplicate)
        }
    }

    // MARK: - Reordering

    func moveToBuyItems(from source: IndexSet, to destination: Int, persist: Bool = true) {
        var orderedItems = toBuyItems
        orderedItems.move(fromOffsets: source, toOffset: destination)
        _ = applyToBuyOrder(orderedItems)

        guard persist else { return }
        _ = _Concurrency.Task {
            await persistCurrentToBuyOrder()
        }
    }

    func persistCurrentToBuyOrder() async {
        let orderedItems = toBuyItems
        updateCachedOrder(for: orderedItems)

        guard isCloudSyncEnabled else { return }

        do {
            try await cloudKit.saveShoppingItemsBatch(orderedItems, scope: cloudScope)
            for item in orderedItems {
                markCachedItemSynced(itemId: item.id)
            }
        } catch {
            self.error = error
            for item in orderedItems {
                do {
                    _ = try await cloudKit.saveShoppingItem(item, scope: cloudScope)
                    markCachedItemSynced(itemId: item.id)
                } catch {
                    self.error = error
                }
            }
        }
    }

    private func applyToBuyOrder(_ orderedItems: [ShoppingItem]) -> [ShoppingItem] {
        var persistedOrder: [ShoppingItem] = []
        persistedOrder.reserveCapacity(orderedItems.count)

        for (index, item) in orderedItems.enumerated() {
            var updatedItem = item
            updatedItem.sortOrder = index
            updatedItem.updatedAt = Date()
            persistedOrder.append(updatedItem)

            guard let localIndex = items.firstIndex(where: { $0.id == updatedItem.id }) else { continue }
            items[localIndex] = updatedItem
        }

        return persistedOrder
    }

    private func updateCachedOrder(for orderedItems: [ShoppingItem]) {
        for item in orderedItems {
            upsertCachedItem(
                item,
                syncStatusRaw: isCloudSyncEnabled ? "pendingUpload" : "synced",
                lastSyncedAt: isCloudSyncEnabled ? nil : Date()
            )
        }
    }

    private func markCachedItemSynced(itemId: UUID) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.id == itemId }
        )
        if let cached = try? context.fetch(descriptor).first {
            cached.syncStatusRaw = "awaitingCloudEcho"
            cached.lastSyncedAt = Date()
            saveContextOrSetError(context, operation: "mark reordered shopping item awaiting cloud echo")
        }
    }

    private func nextToBuySortOrder() -> Int {
        let currentMax = items
            .filter { !$0.isBought }
            .map(\.sortOrder)
            .max() ?? -1
        return currentMax + 1
    }

    /// Deletes a single recent item (all bought duplicates matching the same title).
    func deleteRecentItem(_ item: ShoppingItem) async {
        let key = normalizedRecentKey(item.title)
        let matchingBought = items.filter { $0.isBought && normalizedRecentKey($0.title) == key }
        for match in matchingBought {
            await deleteItem(match)
        }
    }

    /// Clears all recently purchased items.
    func clearRecentItems() async {
        let boughtItems = items.filter(\.isBought)
        guard !boughtItems.isEmpty else { return }

        // Optimistic UI update
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            items.removeAll(where: \.isBought)
        }

        // Keep tombstones locally so a delayed cloud snapshot cannot resurrect bought items.
        for item in boughtItems {
            if let context = modelContext {
                let itemId = item.id
                let descriptor = FetchDescriptor<CachedShoppingItem>(
                    predicate: #Predicate { $0.id == itemId }
                )
                if let cached = try? context.fetch(descriptor).first {
                    if isCloudSyncEnabled {
                        cached.syncStatusRaw = "pendingDelete"
                        cached.lastSyncedAt = nil
                    } else {
                        context.delete(cached)
                    }
                }
            }
        }

        if isCloudSyncEnabled {
            if let householdId {
                let boughtIDs = Set(boughtItems.map(\.id))
                do {
                    try await cloudKit.deleteShoppingItemsBatch(
                        ids: boughtIDs,
                        householdId: householdId,
                        scope: cloudScope
                    )
                    removeCachedItems(ids: boughtIDs)
                } catch {
                    self.error = error
                    for item in boughtItems {
                        do {
                            try await cloudKit.deleteShoppingItem(
                                id: item.id,
                                householdId: item.householdId,
                                scope: cloudScope
                            )
                            removeCachedItems(ids: Set([item.id]))
                        } catch {
                            self.error = error
                        }
                    }
                }
            } else {
                for item in boughtItems {
                    do {
                        try await cloudKit.deleteShoppingItem(
                            id: item.id,
                            householdId: item.householdId,
                            scope: cloudScope
                        )
                        removeCachedItems(ids: Set([item.id]))
                    } catch {
                        self.error = error
                    }
                }
            }
        }

        saveContextOrSetError(operation: "clear recent shopping items cache")

        AppAnalytics.capture(
            "shopping_list_cleared",
            properties: ["cleared_count": boughtItems.count],
            syncMode: syncMode,
            householdId: householdId
        )
    }

    // MARK: - Bulk Operations

    func markAllAsBought() async {
        let activeItems = items.filter { !$0.isBought }
        guard !activeItems.isEmpty else { return }

        // Optimistic UI
        for item in activeItems {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                withAnimation {
                    items[index].isBought = true
                    items[index].boughtAt = Date()
                }
            }
        }

        // Update cache/cloud
        // Note: Ideally allow batch update, but for now we iterate
        for item in activeItems {
            var updated = item
            updated.isBought = true
            updated.boughtAt = Date()
            await updateItem(updated)
        }
    }

    // MARK: - Clear To Buy

    func clearToBuy() async {
        let itemsToClear = items.filter { !$0.isBought }
        guard !itemsToClear.isEmpty else { return }

        // Optimistic UI update
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            items.removeAll { !$0.isBought }
        }

        // Keep tombstones locally so background refresh cannot re-add removed rows.
        for item in itemsToClear {
            if let context = modelContext {
                let itemId = item.id
                let descriptor = FetchDescriptor<CachedShoppingItem>(
                    predicate: #Predicate { $0.id == itemId }
                )
                if let cached = try? context.fetch(descriptor).first {
                    if isCloudSyncEnabled {
                        cached.syncStatusRaw = "pendingDelete"
                        cached.lastSyncedAt = nil
                    } else {
                        context.delete(cached)
                    }
                }
            }

            if !isCloudSyncEnabled {
                continue
            }
        }

        if isCloudSyncEnabled {
            if let householdId {
                let idsToDelete = Set(itemsToClear.map(\.id))
                do {
                    try await cloudKit.deleteShoppingItemsBatch(
                        ids: idsToDelete,
                        householdId: householdId,
                        scope: cloudScope
                    )
                    removeCachedItems(ids: idsToDelete)
                } catch {
                    self.error = error
                    for item in itemsToClear {
                        do {
                            try await cloudKit.deleteShoppingItem(
                                id: item.id,
                                householdId: item.householdId,
                                scope: cloudScope
                            )
                            removeCachedItems(ids: Set([item.id]))
                        } catch {
                            self.error = error
                        }
                    }
                }
            } else {
                for item in itemsToClear {
                    do {
                        try await cloudKit.deleteShoppingItem(
                            id: item.id,
                            householdId: item.householdId,
                            scope: cloudScope
                        )
                        removeCachedItems(ids: Set([item.id]))
                    } catch {
                        self.error = error
                    }
                }
            }
        }

        saveContextOrSetError(operation: "clear to-buy shopping cache")
    }

    // MARK: - Delete Item

    func deleteItem(_ item: ShoppingItem) async {
        // Optimistic UI update
        items.removeAll { $0.id == item.id }

        // Mark as pending delete in cache
        if let context = modelContext {
            let descriptor = FetchDescriptor<CachedShoppingItem>(
                predicate: #Predicate { $0.id == item.id }
            )
            if let cached = try? context.fetch(descriptor).first {
                if isCloudSyncEnabled {
                    cached.syncStatusRaw = "pendingDelete"
                    saveContextOrSetError(context, operation: "mark shopping item pending delete")
                } else {
                    context.delete(cached)
                    saveContextOrSetError(context, operation: "delete shopping item from cache")
                }
            }
        }

        if !isCloudSyncEnabled {
            return
        }

        do {
            try await cloudKit.deleteShoppingItem(
                id: item.id,
                householdId: item.householdId,
                scope: cloudScope
            )

            // Remove from cache
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedShoppingItem>(
                    predicate: #Predicate { $0.id == item.id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    context.delete(cached)
                    saveContextOrSetError(context, operation: "remove synced shopping item from cache")
                }
            }
        } catch {
            self.error = error
            // Keep in cache with pending status, reload UI
            await loadItems()
        }
    }

    private func normalizedRecentKey(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func recentTimestamp(for item: ShoppingItem) -> Date {
        item.boughtAt ?? item.updatedAt
    }

    func pendingSyncSnapshot(from cachedItems: [CachedShoppingItem]) -> PendingSyncSnapshot {
        var pendingUploadByID: [UUID: ShoppingItem] = [:]
        var pendingDeleteIDs = Set<UUID>()
        let now = Date()

        for cached in cachedItems {
            switch cached.syncStatusRaw {
            case "pendingUpload":
                pendingUploadByID[cached.id] = cached.toShoppingItem()
            case "awaitingCloudEcho":
                if !isExpiredAwaitingCloudEcho(cached, relativeTo: now) {
                    pendingUploadByID[cached.id] = cached.toShoppingItem()
                }
            case "pendingDelete":
                pendingDeleteIDs.insert(cached.id)
            default:
                continue
            }
        }

        return PendingSyncSnapshot(
            pendingUploadByID: pendingUploadByID,
            pendingDeleteIDs: pendingDeleteIDs
        )
    }

    func mergeCloudSnapshot(
        _ cloudItems: [ShoppingItem],
        with pendingSnapshot: PendingSyncSnapshot
    ) -> [ShoppingItem] {
        var mergedByID: [UUID: ShoppingItem] = Dictionary(
            uniqueKeysWithValues: cloudItems.map { ($0.id, $0) }
        )

        for (id, pendingItem) in pendingSnapshot.pendingUploadByID {
            if let cloudItem = mergedByID[id],
               cloudShoppingItemMatchesLocalMutationEcho(cloudItem, localItem: pendingItem)
            {
                mergedByID[id] = cloudItem
            } else {
                mergedByID[id] = pendingItem
            }
        }
        for id in pendingSnapshot.pendingDeleteIDs {
            mergedByID.removeValue(forKey: id)
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func cloudShoppingItemMatchesLocalMutationEcho(
        _ cloudItem: ShoppingItem,
        localItem: ShoppingItem
    ) -> Bool {
        guard cloudItem.id == localItem.id else { return false }
        guard cloudItem.updatedAt >= localItem.updatedAt else { return false }

        return cloudItem.title == localItem.title &&
            cloudItem.quantityValue == localItem.quantityValue &&
            cloudItem.quantityUnit == localItem.quantityUnit &&
            cloudItem.isBought == localItem.isBought &&
            cloudItem.boughtAt == localItem.boughtAt &&
            cloudItem.restockCount == localItem.restockCount &&
            cloudItem.sortOrder == localItem.sortOrder
    }

    private func isExpiredAwaitingCloudEcho(
        _ cached: CachedShoppingItem,
        relativeTo now: Date
    ) -> Bool {
        guard cached.syncStatusRaw == "awaitingCloudEcho",
              let lastSyncedAt = cached.lastSyncedAt
        else {
            return false
        }

        return now.timeIntervalSince(lastSyncedAt) >= ShoppingSyncPolicy.awaitingCloudEchoGraceDuration
    }

    private func upsertCachedItem(
        _ item: ShoppingItem,
        syncStatusRaw: String,
        lastSyncedAt: Date?
    ) {
        guard let context = modelContext else { return }

        let itemId = item.id
        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.id == itemId }
        )

        if let cached = try? context.fetch(descriptor).first {
            cached.update(from: item)
            cached.syncStatusRaw = syncStatusRaw
            cached.lastSyncedAt = lastSyncedAt
        } else {
            let cached = CachedShoppingItem(from: item)
            cached.syncStatusRaw = syncStatusRaw
            cached.lastSyncedAt = lastSyncedAt
            context.insert(cached)
        }

        saveContextOrSetError(context, operation: "upsert shopping cache item")
    }

    private func upsertCachedItems(
        _ items: [ShoppingItem],
        syncStatusRaw: String,
        lastSyncedAt: Date?
    ) {
        guard let context = modelContext, !items.isEmpty else { return }

        let itemIDs = Set(items.map(\.id))
        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { itemIDs.contains($0.id) }
        )
        let cachedItems = (try? context.fetch(descriptor)) ?? []
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedItems.map { ($0.id, $0) })

        for item in items {
            if let cached = cachedByID[item.id] {
                cached.update(from: item)
                cached.syncStatusRaw = syncStatusRaw
                cached.lastSyncedAt = lastSyncedAt
            } else {
                let cached = CachedShoppingItem(from: item)
                cached.syncStatusRaw = syncStatusRaw
                cached.lastSyncedAt = lastSyncedAt
                context.insert(cached)
            }
        }

        saveContextOrSetError(context, operation: "upsert shopping cache items")
    }

    private func removeCachedItems(ids: Set<UUID>) {
        guard let context = modelContext, !ids.isEmpty else { return }

        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        let cachedItems = (try? context.fetch(descriptor)) ?? []
        for cached in cachedItems {
            context.delete(cached)
        }
        saveContextOrSetError(context, operation: "remove deleted shopping cache items")
    }
}
