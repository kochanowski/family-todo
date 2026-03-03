import Foundation
import SwiftData
import SwiftUI

/// Store for backlog management (categories and items)
@MainActor
final class BacklogStore: ObservableObject {
    private enum BacklogSyncStatus {
        static let synced = "synced"
        static let pendingUpload = "pendingUpload"
        static let pendingDelete = "pendingDelete"
        static let awaitingCloudEcho = "awaitingCloudEcho"
    }

    enum PromotionResult: Equatable {
        case success(createdTaskId: UUID)
        case assigneeRequired
        case wipLimitReached(current: Int, limit: Int)
        case failed(String)
    }

    private struct PendingSyncSnapshot {
        var pendingUploadItemsByID: [UUID: BacklogItem]
        var pendingDeleteItemIDs: Set<UUID>
        var pendingCategoriesByID: [UUID: BacklogCategory]
    }

    private struct CacheSnapshot {
        var categories: [CachedBacklogCategory]
        var items: [CachedBacklogItem]
    }

    @Published private(set) var categories: [BacklogCategory] = []
    @Published private(set) var items: [BacklogItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private lazy var cloudKit = CloudKitManager.shared
    private let householdId: UUID?
    private var modelContext: ModelContext?
    private var syncMode: SyncMode = .cloud
    private var pendingMutationIDs: Set<UUID> = []

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
        operation: String = "persist backlog cache",
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        StoreContextSaver.saveContextOrSetError(
            context ?? modelContext,
            store: "BacklogStore",
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
        let cacheSnapshot = loadFromCache()
        let pendingSnapshot = pendingSyncSnapshot(
            from: cacheSnapshot.items,
            cachedCategories: cacheSnapshot.categories
        )

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

            categories = mergeCloudCategories(categoriesResult, with: pendingSnapshot)
            items = mergeCloudSnapshot(itemsResult, with: pendingSnapshot)

            // 3. Update cache
            syncToCache(
                categories: categories,
                items: items,
                cloudCategoryIDs: Set(categoriesResult.map(\.id)),
                cloudItemIDs: Set(itemsResult.map(\.id))
            )
            await flushPendingSync()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func loadFromCache() -> CacheSnapshot {
        guard let context = modelContext, let householdId else {
            return CacheSnapshot(categories: [], items: [])
        }

        // Load Categories
        var cachedCategories: [CachedBacklogCategory] = []
        let categoryDescriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        if let fetchedCategories = try? context.fetch(categoryDescriptor) {
            cachedCategories = fetchedCategories
            categories = fetchedCategories.map { $0.toBacklogCategory() }
        }

        // Load Items
        var cachedItems: [CachedBacklogItem] = []
        let itemDescriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        if let fetchedItems = try? context.fetch(itemDescriptor) {
            cachedItems = fetchedItems
            items = fetchedItems
                .filter { $0.syncStatusRaw != BacklogSyncStatus.pendingDelete }
                .map { $0.toBacklogItem() }
        }
        return CacheSnapshot(categories: cachedCategories, items: cachedItems)
    }

    private func syncToCache(
        categories: [BacklogCategory],
        items: [BacklogItem],
        cloudCategoryIDs: Set<UUID>,
        cloudItemIDs: Set<UUID>
    ) {
        guard let context = modelContext, let householdId else { return }

        let categoryCacheDescriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let itemCacheDescriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        let cachedCategories = (try? context.fetch(categoryCacheDescriptor)) ?? []
        let cachedItems = (try? context.fetch(itemCacheDescriptor)) ?? []
        let cachedCategoryByID = Dictionary(uniqueKeysWithValues: cachedCategories.map { ($0.id, $0) })
        let cachedItemByID = Dictionary(uniqueKeysWithValues: cachedItems.map { ($0.id, $0) })

        // Sync Categories
        for category in categories {
            if let existing = cachedCategoryByID[category.id] {
                if existing.syncStatusRaw == BacklogSyncStatus.pendingUpload {
                    continue
                }
                if existing.syncStatusRaw == BacklogSyncStatus.awaitingCloudEcho &&
                    !cloudCategoryIDs.contains(category.id)
                {
                    continue
                }
                existing.update(from: category)
            } else {
                let cached = CachedBacklogCategory(from: category)
                context.insert(cached)
            }
        }

        // Sync Items
        for item in items {
            if let existing = cachedItemByID[item.id] {
                if existing.syncStatusRaw == BacklogSyncStatus.pendingUpload ||
                    existing.syncStatusRaw == BacklogSyncStatus.pendingDelete
                {
                    continue
                }
                if existing.syncStatusRaw == BacklogSyncStatus.awaitingCloudEcho &&
                    !cloudItemIDs.contains(item.id)
                {
                    continue
                }
                existing.update(from: item)
            } else {
                let cached = CachedBacklogItem(from: item)
                context.insert(cached)
            }
        }

        saveContextOrSetError(context, operation: "persist backlog cache")
    }

    private func flushPendingSync() async {
        guard isCloudSyncEnabled, let context = modelContext, let householdId else { return }

        let categoryDescriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let itemDescriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        let cachedCategories = (try? context.fetch(categoryDescriptor)) ?? []
        let cachedItems = (try? context.fetch(itemDescriptor)) ?? []

        let pendingCategoryUploads = cachedCategories.filter {
            $0.syncStatusRaw == BacklogSyncStatus.pendingUpload
        }
        let pendingItemUploads = cachedItems.filter {
            $0.syncStatusRaw == BacklogSyncStatus.pendingUpload
        }
        let pendingItemDeletes = cachedItems.filter {
            $0.syncStatusRaw == BacklogSyncStatus.pendingDelete
        }

        guard
            !pendingCategoryUploads.isEmpty ||
            !pendingItemUploads.isEmpty ||
            !pendingItemDeletes.isEmpty
        else {
            return
        }

        var didMutateCache = false

        for cached in pendingCategoryUploads {
            do {
                _ = try await cloudKit.saveBacklogCategory(cached.toBacklogCategory())
                cached.syncStatusRaw = BacklogSyncStatus.synced
                cached.lastSyncedAt = Date()
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        for cached in pendingItemUploads {
            do {
                _ = try await cloudKit.saveBacklogItem(cached.toBacklogItem())
                cached.syncStatusRaw = BacklogSyncStatus.synced
                cached.lastSyncedAt = Date()
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        for cached in pendingItemDeletes {
            do {
                try await cloudKit.deleteBacklogItem(id: cached.id, householdId: cached.householdId)
                context.delete(cached)
                items.removeAll { $0.id == cached.id }
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        if didMutateCache {
            saveContextOrSetError(context, operation: "flush pending backlog sync mutations")
        }
    }

    // MARK: - Category Operations

    func addCategory(_ title: String, colorHex: String? = nil) async {
        guard let householdId else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let categoryId = UUID()
        let resolvedColorHex = resolveCategoryColorHex(
            requested: colorHex,
            stableId: categoryId
        )

        let category = BacklogCategory(
            id: categoryId,
            householdId: householdId,
            title: trimmedTitle,
            colorHex: resolvedColorHex,
            sortOrder: categories.count
        )

        // Optimistic UI
        withAnimation {
            categories.append(category)
        }

        // Cache
        if let context = modelContext {
            let cached = CachedBacklogCategory(from: category)
            cached.syncStatusRaw = isCloudSyncEnabled
                ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            context.insert(cached)
            saveContextOrSetError(context, operation: "persist backlog cache")
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
                    cached.syncStatusRaw = BacklogSyncStatus.awaitingCloudEcho
                    cached.lastSyncedAt = Date()
                    saveContextOrSetError(context, operation: "persist backlog cache")
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
            saveContextOrSetError(context, operation: "persist backlog cache")
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
        await updateCategory(
            category,
            newTitle: newTitle,
            newColorHex: category.colorHex
        )
    }

    func updateCategory(
        _ category: BacklogCategory,
        newTitle: String,
        newColorHex: String
    ) async {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        let resolvedColorHex = resolveCategoryColorHex(
            requested: newColorHex,
            stableId: category.id
        )

        let previousCategory = categories[index]
        var updatedCategory = categories[index]
        updatedCategory.title = trimmedTitle
        updatedCategory.colorHex = resolvedColorHex
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
                cached.syncStatusRaw = isCloudSyncEnabled
                    ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced
                cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
                saveContextOrSetError(context, operation: "persist backlog cache")
            }
        }

        guard isCloudSyncEnabled else { return }
        do {
            _ = try await cloudKit.updateBacklogCategoryMetadata(
                categoryId: updatedCategory.id,
                householdId: updatedCategory.householdId,
                newTitle: updatedCategory.title,
                newColorHex: updatedCategory.colorHex
            )

            if let context = modelContext {
                let categoryId = updatedCategory.id
                let descriptor = FetchDescriptor<CachedBacklogCategory>(
                    predicate: #Predicate { $0.id == categoryId }
                )
                if let cached = try? context.fetch(descriptor).first {
                    cached.syncStatusRaw = BacklogSyncStatus.awaitingCloudEcho
                    cached.lastSyncedAt = Date()
                    saveContextOrSetError(context, operation: "persist backlog cache")
                }
            }
        } catch {
            self.error = error
            withAnimation {
                categories[index] = previousCategory
            }
            if let context = modelContext {
                let categoryId = previousCategory.id
                let descriptor = FetchDescriptor<CachedBacklogCategory>(
                    predicate: #Predicate { $0.id == categoryId }
                )
                if let cached = try? context.fetch(descriptor).first {
                    cached.update(from: previousCategory)
                    cached.syncStatusRaw = BacklogSyncStatus.synced
                    cached.lastSyncedAt = Date()
                    saveContextOrSetError(context, operation: "persist backlog cache")
                }
            }
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
                    cached.syncStatusRaw = isCloudSyncEnabled
                        ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced
                    cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
                }
            }
            saveContextOrSetError(context, operation: "persist backlog cache")
        }

        guard isCloudSyncEnabled else { return }
        do {
            try await cloudKit.saveBacklogCategoriesBatch(categories)
            for category in categories {
                markCachedCategoryAwaitingCloudEcho(id: category.id)
            }
        } catch {
            self.error = error
            for category in categories {
                do {
                    _ = try await cloudKit.saveBacklogCategory(category)
                    markCachedCategoryAwaitingCloudEcho(id: category.id)
                } catch {
                    self.error = error
                }
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
            cached.syncStatusRaw = isCloudSyncEnabled
                ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            context.insert(cached)
            saveContextOrSetError(context, operation: "persist backlog cache")
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
                    cached.syncStatusRaw = BacklogSyncStatus.awaitingCloudEcho
                    cached.lastSyncedAt = Date()
                    saveContextOrSetError(context, operation: "persist backlog cache")
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
            cached.syncStatusRaw = isCloudSyncEnabled
                ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            context.insert(cached)
            saveContextOrSetError(context, operation: "persist backlog cache")
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
                    cached.syncStatusRaw = BacklogSyncStatus.awaitingCloudEcho
                    cached.lastSyncedAt = Date()
                    saveContextOrSetError(context, operation: "persist backlog cache")
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
            saveContextOrSetError(context, operation: "persist backlog cache")
        }
    }

    func updateItem(_ item: BacklogItem, title: String, notes: String?) async {
        await updateItem(item, title: title, notes: notes, assigneeId: item.assigneeId)
    }

    func updateItem(_ item: BacklogItem, title: String, notes: String?, assigneeId: UUID?) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        beginMutation(item.id)
        defer { endMutation(item.id) }

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
                cached.syncStatusRaw = isCloudSyncEnabled
                    ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced
                cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
                saveContextOrSetError(context, operation: "persist backlog cache")
            } else {
                let cached = CachedBacklogItem(from: updatedItem)
                cached.syncStatusRaw = isCloudSyncEnabled
                    ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced
                cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
                context.insert(cached)
                saveContextOrSetError(context, operation: "persist backlog cache")
            }
        }

        guard isCloudSyncEnabled else { return }
        do {
            _ = try await cloudKit.saveBacklogItem(updatedItem)
            markCachedItemAwaitingCloudEcho(id: updatedItem.id)
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
            NotificationCenter.default.post(name: .taskBoardDataDidChange, object: nil)
            return .success(createdTaskId: createdTaskId)
        case .assigneeRequired:
            return .assigneeRequired
        case let .wipLimitReached(current, limit):
            return .wipLimitReached(current: current, limit: limit)
        }
    }

    private func beginMutation(_ id: UUID) {
        pendingMutationIDs.insert(id)
    }

    private func endMutation(_ id: UUID) {
        pendingMutationIDs.remove(id)
    }

    private func markCachedItemAwaitingCloudEcho(id: UUID) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            cached.syncStatusRaw = BacklogSyncStatus.awaitingCloudEcho
            cached.lastSyncedAt = Date()
            saveContextOrSetError(context, operation: "persist backlog cache")
        }
    }

    private func markCachedCategoryAwaitingCloudEcho(id: UUID) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            cached.syncStatusRaw = BacklogSyncStatus.awaitingCloudEcho
            cached.lastSyncedAt = Date()
            saveContextOrSetError(context, operation: "persist backlog cache")
        }
    }

    private func resolveCategoryColorHex(requested: String?, stableId: UUID) -> String {
        guard let normalized = MemberColorToken.normalize(hex: requested),
              MemberColorToken.isAllowed(hex: normalized)
        else {
            return MemberColorToken.migratedHex(for: stableId)
        }
        return normalized
    }

    private func pendingSyncSnapshot(
        from cachedItems: [CachedBacklogItem],
        cachedCategories: [CachedBacklogCategory]
    ) -> PendingSyncSnapshot {
        var pendingUploadItemsByID: [UUID: BacklogItem] = [:]
        var pendingDeleteItemIDs = Set<UUID>()
        var pendingCategoriesByID: [UUID: BacklogCategory] = [:]
        for cached in cachedItems {
            switch cached.syncStatusRaw {
            case BacklogSyncStatus.pendingUpload, BacklogSyncStatus.awaitingCloudEcho:
                pendingUploadItemsByID[cached.id] = cached.toBacklogItem()
            case BacklogSyncStatus.pendingDelete:
                pendingDeleteItemIDs.insert(cached.id)
            default:
                continue
            }
        }
        for cachedCategory in cachedCategories {
            if cachedCategory.syncStatusRaw == BacklogSyncStatus.pendingUpload ||
                cachedCategory.syncStatusRaw == BacklogSyncStatus.awaitingCloudEcho
            {
                pendingCategoriesByID[cachedCategory.id] = cachedCategory.toBacklogCategory()
            }
        }
        return PendingSyncSnapshot(
            pendingUploadItemsByID: pendingUploadItemsByID,
            pendingDeleteItemIDs: pendingDeleteItemIDs,
            pendingCategoriesByID: pendingCategoriesByID
        )
    }

    private func mergeCloudCategories(
        _ cloudCategories: [BacklogCategory],
        with pendingSnapshot: PendingSyncSnapshot
    ) -> [BacklogCategory] {
        var mergedByID = Dictionary(uniqueKeysWithValues: cloudCategories.map { ($0.id, $0) })
        for (id, pendingCategory) in pendingSnapshot.pendingCategoriesByID {
            if let cloudCategory = mergedByID[id], cloudCategory.updatedAt > pendingCategory.updatedAt {
                continue
            }
            mergedByID[id] = pendingCategory
        }
        return mergedByID.values.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func mergeCloudSnapshot(
        _ cloudItems: [BacklogItem],
        with pendingSnapshot: PendingSyncSnapshot
    ) -> [BacklogItem] {
        var mergedByID = Dictionary(uniqueKeysWithValues: cloudItems.map { ($0.id, $0) })
        let localByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        for (id, pendingItem) in pendingSnapshot.pendingUploadItemsByID {
            if let cloudItem = mergedByID[id], cloudItem.updatedAt > pendingItem.updatedAt {
                continue
            }
            mergedByID[id] = pendingItem
        }

        for id in pendingSnapshot.pendingDeleteItemIDs {
            mergedByID.removeValue(forKey: id)
        }

        for id in pendingMutationIDs {
            if let local = localByID[id] {
                mergedByID[id] = local
            }
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
