import Foundation
import SwiftData
import SwiftUI

/// Store for shared shopping list management
@MainActor
final class ShoppingListStore: ObservableObject {
    @Published private(set) var items: [ShoppingItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private lazy var cloudKit = CloudKitManager.shared
    private let householdId: UUID?
    private var modelContext: ModelContext?
    private var syncMode: SyncMode = .cloud

    struct PendingSyncSnapshot {
        var pendingUploadByID: [UUID: ShoppingItem]
        var pendingDeleteIDs: Set<UUID>
    }

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
    }

    private var isCloudSyncEnabled: Bool {
        syncMode == .cloud
    }

    init(householdId: UUID?, modelContext: ModelContext? = nil) {
        self.householdId = householdId
        self.modelContext = modelContext
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

    func loadItems() async {
        guard let householdId else { return }

        isLoading = true
        error = nil

        // 1. Load from cache first (instant UI)
        let cachedItems = loadFromCache()
        let pendingSnapshot = pendingSyncSnapshot(from: cachedItems)

        if !isCloudSyncEnabled {
            isLoading = false
            return
        }

        // 2. Sync with CloudKit in background
        do {
            // Ensure CloudKit is ready before accessing
            await cloudKit.ensureReady()
            let fetchedItems = try await cloudKit.fetchShoppingItems(householdId: householdId)
            items = mergeCloudSnapshot(fetchedItems, with: pendingSnapshot)

            // 3. Update cache
            syncToCache(fetchedItems)
            await flushPendingSync()
        } catch {
            // Keep cached data on error
            self.error = error
        }

        isLoading = false
    }

    private func loadFromCache() -> [CachedShoppingItem] {
        guard let context = modelContext, let householdId else { return [] }

        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        if let cachedItems = try? context.fetch(descriptor) {
            items = cachedItems.map { $0.toShoppingItem() }
            return cachedItems
        }
        return []
    }

    private func syncToCache(_ items: [ShoppingItem]) {
        guard let context = modelContext else { return }

        for item in items {
            let descriptor = FetchDescriptor<CachedShoppingItem>(
                predicate: #Predicate { $0.id == item.id }
            )

            if let existing = try? context.fetch(descriptor).first {
                if existing.syncStatusRaw == "pendingUpload" || existing.syncStatusRaw == "pendingDelete" {
                    continue
                }
                existing.update(from: item)
            } else {
                let cached = CachedShoppingItem(from: item)
                context.insert(cached)
            }
        }

        saveContextOrSetError(context, operation: "sync shopping cache from cloud")
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

        for cached in pendingUploads {
            do {
                _ = try await cloudKit.saveShoppingItem(cached.toShoppingItem())
                cached.syncStatusRaw = "synced"
                cached.lastSyncedAt = Date()
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        for cached in pendingDeletes {
            do {
                try await cloudKit.deleteShoppingItem(id: cached.id, householdId: cached.householdId)
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

    func createItem(title: String, quantityValue: String? = nil, quantityUnit: String? = nil) async {
        guard let householdId else { return }

        let item = ShoppingItem(
            householdId: householdId,
            title: title,
            quantityValue: quantityValue,
            quantityUnit: quantityUnit,
            isBought: false,
            sortOrder: nextToBuySortOrder()
        )

        // Optimistic UI update (view handles animation)
        items.append(item)

        // Save to cache with pending status
        upsertCachedItem(
            item,
            syncStatusRaw: isCloudSyncEnabled ? "pendingUpload" : "synced",
            lastSyncedAt: isCloudSyncEnabled ? nil : Date()
        )

        if !isCloudSyncEnabled {
            return
        }

        do {
            _ = try await cloudKit.saveShoppingItem(item)

            // Mark as synced
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedShoppingItem>(
                    predicate: #Predicate { $0.id == item.id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    cached.syncStatusRaw = "synced"
                    cached.lastSyncedAt = Date()
                    saveContextOrSetError(context, operation: "mark created shopping item as synced")
                }
            }
        } catch {
            items.removeAll { $0.id == item.id }
            // Keep in cache with pending status
            self.error = error
        }
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

        // Save to cache with pending status
        upsertCachedItem(
            updatedItem,
            syncStatusRaw: isCloudSyncEnabled ? "pendingUpload" : "synced",
            lastSyncedAt: isCloudSyncEnabled ? nil : Date()
        )

        if !isCloudSyncEnabled {
            return
        }

        do {
            _ = try await cloudKit.saveShoppingItem(updatedItem)

            // Mark as synced
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedShoppingItem>(
                    predicate: #Predicate { $0.id == item.id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    cached.syncStatusRaw = "synced"
                    cached.lastSyncedAt = Date()
                    saveContextOrSetError(context, operation: "mark updated shopping item as synced")
                }
            }
        } catch {
            self.error = error
            // Keep optimistic + pending cache state; avoid immediate stale-cloud rollback.
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
        applyToBuyOrder(orderedItems)

        guard persist else { return }
        _ = _Concurrency.Task {
            await persistCurrentToBuyOrder()
        }
    }

    func persistCurrentToBuyOrder() async {
        let orderedItems = toBuyItems
        updateCachedOrder(for: orderedItems)

        guard isCloudSyncEnabled else { return }

        for item in orderedItems {
            do {
                _ = try await cloudKit.saveShoppingItem(item)
                markCachedItemSynced(itemId: item.id)
            } catch {
                self.error = error
            }
        }
    }

    private func applyToBuyOrder(_ orderedItems: [ShoppingItem]) {
        var sortOrderByID: [UUID: Int] = [:]
        for (index, item) in orderedItems.enumerated() {
            sortOrderByID[item.id] = index
        }

        for index in items.indices {
            guard let sortOrder = sortOrderByID[items[index].id] else { continue }
            items[index].sortOrder = sortOrder
            items[index].updatedAt = Date()
        }
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
            cached.syncStatusRaw = "synced"
            cached.lastSyncedAt = Date()
            saveContextOrSetError(context, operation: "mark reordered shopping item as synced")
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

        // Delete from cache/cloud
        for item in boughtItems {
            if let context = modelContext {
                let itemId = item.id
                let descriptor = FetchDescriptor<CachedShoppingItem>(
                    predicate: #Predicate { $0.id == itemId }
                )
                if let cached = try? context.fetch(descriptor).first {
                    context.delete(cached)
                }
            }

            if isCloudSyncEnabled {
                do {
                    try await cloudKit.deleteShoppingItem(id: item.id, householdId: item.householdId)
                } catch {
                    self.error = error
                }
            }
        }

        saveContextOrSetError(operation: "clear recent shopping items cache")
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

        // Delete from CloudKit and cache
        for item in itemsToClear {
            // Mark as pending delete in cache
            if let context = modelContext {
                let itemId = item.id
                let descriptor = FetchDescriptor<CachedShoppingItem>(
                    predicate: #Predicate { $0.id == itemId }
                )
                if let cached = try? context.fetch(descriptor).first {
                    context.delete(cached)
                }
            }

            if !isCloudSyncEnabled {
                continue
            }

            do {
                try await cloudKit.deleteShoppingItem(id: item.id, householdId: item.householdId)
            } catch {
                self.error = error
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
            try await cloudKit.deleteShoppingItem(id: item.id, householdId: item.householdId)

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

        for cached in cachedItems {
            switch cached.syncStatusRaw {
            case "pendingUpload":
                pendingUploadByID[cached.id] = cached.toShoppingItem()
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
            mergedByID[id] = pendingItem
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
}
