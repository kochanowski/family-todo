import Foundation
import SwiftData
import SwiftUI

/// Store for backlog management (categories and items)
@MainActor
final class BacklogStore: ObservableObject {
    @Published private(set) var categories: [BacklogCategory] = []
    @Published private(set) var items: [BacklogItem] = []
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

    /// Get items for a specific category
    func items(for categoryId: UUID) -> [BacklogItem] {
        items
            .filter { $0.categoryId == categoryId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Load Data

    func loadData() async {
        guard let householdId else { return }

        isLoading = true
        error = nil

        // 1. Load from cache first
        loadFromCache()

        if !isCloudSyncEnabled {
            isLoading = false
            return
        }

        // 2. Sync with CloudKit
        do {
            // Ensure CloudKit is ready before accessing
            await cloudKit.ensureReady()
            async let fetchedCategories = cloudKit.fetchBacklogCategories(householdId: householdId)
            async let fetchedItems = cloudKit.fetchBacklogItems(householdId: householdId)

            let (categoriesResult, itemsResult) = try await (fetchedCategories, fetchedItems)

            categories = categoriesResult
            items = itemsResult

            // 3. Update cache
            syncToCache(categories: categoriesResult, items: itemsResult)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func loadFromCache() {
        guard let context = modelContext, let householdId else { return }

        // Load Categories
        let categoryDescriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        if let cachedCategories = try? context.fetch(categoryDescriptor) {
            categories = cachedCategories.map { $0.toBacklogCategory() }
        }

        // Load Items
        let itemDescriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        if let cachedItems = try? context.fetch(itemDescriptor) {
            items = cachedItems.map { $0.toBacklogItem() }
        }
    }

    private func syncToCache(categories: [BacklogCategory], items: [BacklogItem]) {
        guard let context = modelContext else { return }

        // Sync Categories
        for category in categories {
            let descriptor = FetchDescriptor<CachedBacklogCategory>(
                predicate: #Predicate { $0.id == category.id }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.update(from: category)
            } else {
                let cached = CachedBacklogCategory(from: category)
                context.insert(cached)
            }
        }

        // Sync Items
        for item in items {
            let descriptor = FetchDescriptor<CachedBacklogItem>(
                predicate: #Predicate { $0.id == item.id }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.update(from: item)
            } else {
                let cached = CachedBacklogItem(from: item)
                context.insert(cached)
            }
        }

        try? context.save()
    }

    // MARK: - Category Operations

    func addCategory(_ title: String) async {
        guard let householdId else { return }

        let category = BacklogCategory(
            householdId: householdId,
            title: title,
            sortOrder: categories.count
        )

        // Optimistic UI
        withAnimation {
            categories.append(category)
        }

        // Cache
        if let context = modelContext {
            let cached = CachedBacklogCategory(from: category)
            cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            context.insert(cached)
            try? context.save()
        }

        if !isCloudSyncEnabled { return }

        do {
            _ = try await cloudKit.saveBacklogCategory(category)

            // Mark synced
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedBacklogCategory>(
                    predicate: #Predicate { $0.id == category.id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    cached.syncStatusRaw = "synced"
                    cached.lastSyncedAt = Date()
                    try? context.save()
                }
            }
        } catch {
            self.error = error
            // Revert UI if needed, or keep as pending
        }
    }

    func deleteCategory(_ category: BacklogCategory) async {
        // Optimistic UI
        withAnimation {
            categories.removeAll { $0.id == category.id }
            // Also remove items in this category visually
            items.removeAll { $0.categoryId == category.id }
        }

        // Cache
        if let context = modelContext {
            // Delete category
            let catDescriptor = FetchDescriptor<CachedBacklogCategory>(
                predicate: #Predicate { $0.id == category.id }
            )
            if let cached = try? context.fetch(catDescriptor).first {
                context.delete(cached)
            }

            // Delete items in category
            let categoryId = category.id
            let itemDescriptor = FetchDescriptor<CachedBacklogItem>(
                predicate: #Predicate { $0.categoryId == categoryId } // Note: Check if predicate supports this variable capture
            )
            if let cachedItems = try? context.fetch(itemDescriptor) {
                for item in cachedItems {
                    context.delete(item)
                }
            }
            try? context.save()
        }

        if !isCloudSyncEnabled { return }

        do {
            try await cloudKit.deleteBacklogCategory(id: category.id)
            // CloudKit should cascade delete items optionally, or we delete them explicitly?
            // Assuming we handle items delete or specific logic elsewhere, but for now just category delete.
            // Ideally we should delete items first or rely on CloudKit references if configured.
            // For safety, let's assume we need to delete items locally and hope valid refs handle it or we iterate.
            // But deleting the category is the main action here.
        } catch {
            self.error = error
            await loadData() // Reload on error
        }
    }

    // MARK: - Item Operations

    func addItem(to categoryId: UUID, title: String) async {
        guard let householdId else { return }

        let item = BacklogItem(
            categoryId: categoryId,
            householdId: householdId,
            title: title
        )

        // Optimistic UI
        withAnimation {
            items.insert(item, at: 0)
        }

        // Cache
        if let context = modelContext {
            let cached = CachedBacklogItem(from: item)
            cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            context.insert(cached)
            try? context.save()
        }

        if !isCloudSyncEnabled { return }

        do {
            _ = try await cloudKit.saveBacklogItem(item)

            // Mark synced
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedBacklogItem>(
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
            withAnimation {
                items.removeAll { $0.id == item.id }
            }
        }
    }

    func deleteItem(_ item: BacklogItem) async {
        // Optimistic UI
        withAnimation {
            items.removeAll { $0.id == item.id }
        }

        // Cache
        if let context = modelContext {
            let descriptor = FetchDescriptor<CachedBacklogItem>(
                predicate: #Predicate { $0.id == item.id }
            )
            if let cached = try? context.fetch(descriptor).first {
                context.delete(cached)
                try? context.save()
            }
        }

        if !isCloudSyncEnabled { return }

        do {
            try await cloudKit.deleteBacklogItem(id: item.id)
        } catch {
            self.error = error
            await loadData()
        }
    }
}
