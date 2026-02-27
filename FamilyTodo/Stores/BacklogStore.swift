import Foundation
import SwiftData
import SwiftUI

/// Store for backlog management (categories and items)
@MainActor
final class BacklogStore: ObservableObject {
    enum PromotionResult: Equatable {
        case success(createdTaskId: UUID)
        case assigneeRequired
        case wipLimitReached(current: Int, limit: Int)
        case failed(String)
    }

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
            try await cloudKit.deleteBacklogCategory(id: category.id, householdId: category.householdId)
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

    func renameCategory(_ category: BacklogCategory, newTitle: String) async {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }

        var updatedCategory = categories[index]
        updatedCategory.title = trimmedTitle
        updatedCategory.updatedAt = Date()

        withAnimation {
            categories[index] = updatedCategory
        }

        if let context = modelContext {
            let categoryId = category.id
            let descriptor = FetchDescriptor<CachedBacklogCategory>(
                predicate: #Predicate { $0.id == categoryId }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.update(from: updatedCategory)
                cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
                cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
                try? context.save()
            }
        }

        guard isCloudSyncEnabled else { return }
        do {
            _ = try await cloudKit.saveBacklogCategory(updatedCategory)
        } catch {
            self.error = error
            await loadData()
        }
    }

    func reorderCategories(orderedIds: [UUID]) async {
        guard !orderedIds.isEmpty else { return }

        var indexMap: [UUID: Int] = [:]
        for (index, id) in orderedIds.enumerated() {
            indexMap[id] = index
        }

        for idx in categories.indices {
            guard let newOrder = indexMap[categories[idx].id] else { continue }
            categories[idx].sortOrder = newOrder
            categories[idx].updatedAt = Date()
        }
        categories.sort { $0.sortOrder < $1.sortOrder }

        if let context = modelContext {
            for category in categories {
                let categoryId = category.id
                let descriptor = FetchDescriptor<CachedBacklogCategory>(
                    predicate: #Predicate { $0.id == categoryId }
                )
                if let cached = try? context.fetch(descriptor).first {
                    cached.update(from: category)
                    cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
                    cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
                }
            }
            try? context.save()
        }

        guard isCloudSyncEnabled else { return }
        for category in categories {
            do {
                _ = try await cloudKit.saveBacklogCategory(category)
            } catch {
                self.error = error
            }
        }
    }

    // MARK: - Item Operations

    @discardableResult
    func createFromTask(_ task: Task, fallbackCategoryId: UUID? = nil) async throws -> BacklogItem {
        guard let householdId else {
            throw HouseholdError.householdNotFound
        }

        let resolvedCategoryId: UUID?
        if let backlogCategoryId = task.backlogCategoryId,
           categories.contains(where: { $0.id == backlogCategoryId })
        {
            resolvedCategoryId = backlogCategoryId
        } else if let fallbackCategoryId,
                  categories.contains(where: { $0.id == fallbackCategoryId })
        {
            resolvedCategoryId = fallbackCategoryId
        } else {
            resolvedCategoryId = categories.first?.id
        }

        guard let categoryId = resolvedCategoryId else {
            throw HouseholdError.invalidInviteCode
        }

        let item = BacklogItem(
            categoryId: categoryId,
            householdId: householdId,
            title: task.title,
            assigneeId: task.assigneeId,
            notes: task.notes
        )

        withAnimation {
            items.insert(item, at: 0)
        }

        if let context = modelContext {
            let cached = CachedBacklogItem(from: item)
            cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            context.insert(cached)
            try? context.save()
        }

        guard isCloudSyncEnabled else {
            return item
        }

        do {
            _ = try await cloudKit.saveBacklogItem(item)
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
            return item
        } catch {
            self.error = error
            withAnimation {
                items.removeAll { $0.id == item.id }
            }
            removeCachedItem(id: item.id)
            throw error
        }
    }

    func addItem(to categoryId: UUID, title: String, assigneeId: UUID? = nil, notes: String? = nil) async {
        guard let householdId else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)

        let item = BacklogItem(
            categoryId: categoryId,
            householdId: householdId,
            title: trimmedTitle,
            assigneeId: assigneeId,
            notes: trimmedNotes
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

    @discardableResult
    func deleteItem(_ item: BacklogItem) async -> Bool {
        await deleteItemInternal(item, reloadOnFailure: true)
    }

    private func deleteItemInternal(_ item: BacklogItem, reloadOnFailure: Bool) async -> Bool {
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }) else {
            removeCachedItem(id: item.id)
            return true
        }

        let removedItem = items[currentIndex]

        withAnimation {
            items.remove(at: currentIndex)
        }

        if !isCloudSyncEnabled {
            removeCachedItem(id: item.id)
            return true
        }

        do {
            try await cloudKit.deleteBacklogItem(id: item.id, householdId: item.householdId)
            removeCachedItem(id: item.id)
            return true
        } catch {
            self.error = error
            withAnimation {
                let safeIndex = min(currentIndex, items.count)
                items.insert(removedItem, at: safeIndex)
            }
            if reloadOnFailure {
                await loadData()
            }
            return false
        }
    }

    private func removeCachedItem(id: UUID) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            context.delete(cached)
            try? context.save()
        }
    }

    func updateItem(_ item: BacklogItem, title: String, notes: String?) async {
        await updateItem(item, title: title, notes: notes, assigneeId: item.assigneeId)
    }

    func updateItem(_ item: BacklogItem, title: String, notes: String?, assigneeId: UUID?) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        var updatedItem = items[index]
        updatedItem.title = trimmedTitle
        updatedItem.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedItem.assigneeId = assigneeId
        updatedItem.updatedAt = Date()

        withAnimation {
            items[index] = updatedItem
        }

        if let context = modelContext {
            let itemId = updatedItem.id
            let descriptor = FetchDescriptor<CachedBacklogItem>(
                predicate: #Predicate { $0.id == itemId }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.update(from: updatedItem)
                cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
                cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
                try? context.save()
            }
        }

        guard isCloudSyncEnabled else { return }
        do {
            _ = try await cloudKit.saveBacklogItem(updatedItem)
        } catch {
            self.error = error
            // Keep optimistic + pending cache state; avoid immediate stale-cloud rollback.
        }
    }

    @discardableResult
    func promoteItemToTask(
        _ item: BacklogItem,
        assigneeId: UUID?,
        preferredStatus: Task.TaskStatus = .next
    ) async -> PromotionResult {
        guard let modelContext, let householdId else {
            return .failed("Missing local context.")
        }

        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setSyncMode(syncMode)
        taskStore.setHousehold(householdId)

        let createdTaskId = UUID()
        let resolvedAssigneeId = assigneeId ?? item.assigneeId
        let validation = await taskStore.createTaskFromBacklogItem(
            title: item.title,
            notes: item.notes,
            preferredStatus: preferredStatus,
            assigneeId: resolvedAssigneeId,
            taskId: createdTaskId,
            backlogCategoryId: item.categoryId
        )

        switch validation {
        case .ok:
            let didDeleteBacklogItem = await deleteItemInternal(item, reloadOnFailure: false)
            guard didDeleteBacklogItem else {
                if let createdTask = taskStore.tasks.first(where: { $0.id == createdTaskId }) {
                    await taskStore.deleteTask(createdTask)
                }
                return .failed(
                    "Couldn't remove item from Ideas. Promotion was rolled back."
                )
            }
            return .success(createdTaskId: createdTaskId)
        case .assigneeRequired:
            return .assigneeRequired
        case let .wipLimitReached(current, limit):
            return .wipLimitReached(current: current, limit: limit)
        }
    }
}
