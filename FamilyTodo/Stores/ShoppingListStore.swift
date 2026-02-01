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

    /// Set model context for offline caching
    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    var toBuyItems: [ShoppingItem] {
        items
            .filter { !$0.isBought }
            .sorted { $0.updatedAt > $1.updatedAt }
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

    // MARK: - Load Items

    func loadItems() async {
        guard let householdId else { return }

        isLoading = true
        error = nil

        // 1. Load from cache first (instant UI)
        loadFromCache()

        if !isCloudSyncEnabled {
            isLoading = false
            return
        }

        // 2. Sync with CloudKit in background
        do {
            // Ensure CloudKit is ready before accessing
            await cloudKit.ensureReady()
            let fetchedItems = try await cloudKit.fetchShoppingItems(householdId: householdId)
            items = fetchedItems

            // 3. Update cache
            syncToCache(fetchedItems)
        } catch {
            // Keep cached data on error
            self.error = error
        }

        isLoading = false
    }

    private func loadFromCache() {
        guard let context = modelContext, let householdId else { return }

        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        if let cachedItems = try? context.fetch(descriptor) {
            items = cachedItems.map { $0.toShoppingItem() }
        }
    }

    private func syncToCache(_ items: [ShoppingItem]) {
        guard let context = modelContext else { return }

        for item in items {
            let descriptor = FetchDescriptor<CachedShoppingItem>(
                predicate: #Predicate { $0.id == item.id }
            )

            if let existing = try? context.fetch(descriptor).first {
                existing.update(from: item)
            } else {
                let cached = CachedShoppingItem(from: item)
                context.insert(cached)
            }
        }

        try? context.save()
    }

    // MARK: - Create Item

    func createItem(title: String, quantityValue: String? = nil, quantityUnit: String? = nil) async {
        guard let householdId else { return }

        let item = ShoppingItem(
            householdId: householdId,
            title: title,
            quantityValue: quantityValue,
            quantityUnit: quantityUnit,
            isBought: false
        )

        // Optimistic UI update with animation
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            items.append(item)
        }

        // Save to cache with pending status
        if let context = modelContext {
            let cached = CachedShoppingItem(from: item)
            cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            context.insert(cached)
            try? context.save()
        }

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
                    try? context.save()
                }
            }
        } catch {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                items.removeAll { $0.id == item.id }
            }
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
        if let context = modelContext {
            let descriptor = FetchDescriptor<CachedShoppingItem>(
                predicate: #Predicate { $0.id == item.id }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.update(from: updatedItem)
                cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
                cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
                try? context.save()
            }
        }

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
                    try? context.save()
                }
            }
        } catch {
            self.error = error
            // Keep in cache with pending status
            await loadItems()
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
        }
        await updateItem(updatedItem)
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
                try await cloudKit.deleteShoppingItem(id: item.id)
            } catch {
                self.error = error
            }
        }

        try? modelContext?.save()
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
                    try? context.save()
                } else {
                    context.delete(cached)
                    try? context.save()
                }
            }
        }

        if !isCloudSyncEnabled {
            return
        }

        do {
            try await cloudKit.deleteShoppingItem(id: item.id)

            // Remove from cache
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedShoppingItem>(
                    predicate: #Predicate { $0.id == item.id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    context.delete(cached)
                    try? context.save()
                }
            }
        } catch {
            self.error = error
            // Keep in cache with pending status, reload UI
            await loadItems()
        }
    }
}
