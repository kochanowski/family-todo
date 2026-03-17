import Foundation
import SwiftData
import SwiftUI

// swiftlint:disable file_length

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

    enum CategoryDeletionBlockReason: Equatable {
        case ideas(count: Int)
        case tasks(count: Int)
        case ideasAndTasks(ideaCount: Int, taskCount: Int)

        var alertDetail: String {
            switch self {
            case .ideas:
                "There are ideas assigned to it."
            case .tasks:
                "There are active or completed tasks assigned to it."
            case .ideasAndTasks:
                "There are ideas, active tasks, or completed tasks assigned to it."
            }
        }
    }

    enum CategoryDeletionResult: Equatable {
        case deleted
        case blocked(CategoryDeletionBlockReason)
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
    @Published private(set) var hasHydratedLocalSnapshot = false
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingInBackground = false
    @Published private(set) var error: Error?

    private lazy var cloudKit = CloudKitManager.shared
    private let householdId: UUID?
    private var modelContext: ModelContext?
    private var syncMode: SyncMode = .cloud
    private var currentUserId: String?
    private var householdOwnerId: String?
    private var pendingMutationIDs: Set<UUID> = []
    private var isReplayingPendingMutations = false
    private var activeLoadTask: _Concurrency.Task<Void, Never>?
    private var shouldReloadAfterCurrentLoad = false
    private var hasHydratedVisibleSnapshot = false
    private var needsLocalRehydrate = false

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
    }

    func setCloudContext(currentUserId: String?, householdOwnerId: String?) {
        self.currentUserId = currentUserId
        self.householdOwnerId = householdOwnerId
    }

    private var isCloudSyncEnabled: Bool {
        syncMode == .cloud
    }

    private var cloudScope: CloudKitManager.HouseholdDatabaseScope {
        guard let currentUserId, let householdOwnerId else {
            return .participantShared
        }
        return currentUserId == householdOwnerId ? .ownerPrivate : .participantShared
    }

    init(householdId: UUID?, modelContext: ModelContext? = nil) {
        self.householdId = householdId
        self.modelContext = modelContext
        hydrateVisibleSnapshotFromCacheIfNeeded(force: true)
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
        hydrateVisibleSnapshotFromCacheIfNeeded(force: true)
    }

    /// Get items for a specific category
    func items(for categoryId: UUID) -> [BacklogItem] {
        items
            .filter { $0.categoryId == categoryId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Load Data

    func loadDataForDisplay() async {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: shouldForceVisibleHydration())
        guard isCloudSyncEnabled else { return }
        scheduleBackgroundRefresh()
    }

    func loadData() async {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: shouldForceVisibleHydration())
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
                await performLoadDataPass()
            } while shouldReloadAfterCurrentLoad

            activeLoadTask = nil
        }

        activeLoadTask = loadTask
        return loadTask
    }

    private func performLoadDataPass() async {
        guard let householdId else { return }

        isLoading = true
        isRefreshingInBackground = true
        error = nil
        defer {
            isLoading = false
            isRefreshingInBackground = false
        }

        // 1. Load from cache first
        hydrateVisibleSnapshotFromCacheIfNeeded(force: shouldForceVisibleHydration())

        if !isCloudSyncEnabled {
            return
        }

        // 2. Sync with CloudKit
        do {
            // Ensure CloudKit is ready before accessing
            await cloudKit.ensureReady()
            async let fetchedCategories = cloudKit.fetchBacklogCategories(
                householdId: householdId,
                scope: cloudScope
            )
            async let fetchedItems = cloudKit.fetchBacklogItems(
                householdId: householdId,
                scope: cloudScope
            )

            let (categoriesResult, itemsResult) = try await (fetchedCategories, fetchedItems)
            let latestCacheSnapshot = fetchCacheSnapshot(updateVisibleState: false)
            let latestPendingSnapshot = pendingSyncSnapshot(
                from: latestCacheSnapshot.items,
                cachedCategories: latestCacheSnapshot.categories
            )

            categories = mergeCloudCategories(categoriesResult, with: latestPendingSnapshot)
            items = mergeCloudSnapshot(itemsResult, with: latestPendingSnapshot)

            // 3. Update cache
            syncToCache(
                categories: categoriesResult,
                items: itemsResult,
                cloudCategoryIDs: Set(categoriesResult.map(\.id)),
                cloudItemIDs: Set(itemsResult.map(\.id))
            )
            replayPendingMutationsInBackground()
        } catch {
            self.error = error
        }
    }

    private func hydrateVisibleSnapshotFromCacheIfNeeded(force: Bool = false) {
        _ = fetchCacheSnapshot(updateVisibleState: force || shouldForceVisibleHydration())
    }

    private func fetchCacheSnapshot(updateVisibleState: Bool) -> CacheSnapshot {
        guard let context = modelContext, let householdId else {
            if updateVisibleState {
                categories = []
                items = []
                hasHydratedVisibleSnapshot = true
                hasHydratedLocalSnapshot = true
                needsLocalRehydrate = false
            }
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
            if updateVisibleState {
                categories = fetchedCategories.map { $0.toBacklogCategory() }
            }
        } else if updateVisibleState {
            categories = []
        }

        // Load Items
        var cachedItems: [CachedBacklogItem] = []
        let itemDescriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        if let fetchedItems = try? context.fetch(itemDescriptor) {
            cachedItems = fetchedItems
            if updateVisibleState {
                items = fetchedItems
                    .filter { $0.syncStatusRaw != BacklogSyncStatus.pendingDelete }
                    .map { $0.toBacklogItem() }
            }
        } else if updateVisibleState {
            items = []
        }

        if updateVisibleState {
            hasHydratedVisibleSnapshot = true
            hasHydratedLocalSnapshot = true
            needsLocalRehydrate = false
        }
        return CacheSnapshot(categories: cachedCategories, items: cachedItems)
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

    func syncToCache(
        categories: [BacklogCategory],
        items: [BacklogItem],
        cloudCategoryIDs: Set<UUID>,
        cloudItemIDs _: Set<UUID>
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
        let tombstonedItemIDs = Set(
            cachedItems.compactMap { cachedItem in
                cachedItem.syncStatusRaw == BacklogSyncStatus.pendingDelete ? cachedItem.id : nil
            }
        )

        // Sync Categories
        for category in categories {
            if let existing = cachedCategoryByID[category.id] {
                if existing.syncStatusRaw == BacklogSyncStatus.pendingUpload {
                    continue
                }
                if existing.syncStatusRaw == BacklogSyncStatus.awaitingCloudEcho,
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
            if tombstonedItemIDs.contains(item.id) {
                continue
            }
            if let existing = cachedItemByID[item.id] {
                if existing.syncStatusRaw == BacklogSyncStatus.pendingDelete {
                    continue
                }
                if existing.syncStatusRaw == BacklogSyncStatus.pendingUpload ||
                    existing.syncStatusRaw == BacklogSyncStatus.awaitingCloudEcho
                {
                    let localItem = existing.toBacklogItem()
                    guard cloudBacklogItemMatchesLocalMutationEcho(item, localItem: localItem) else {
                        continue
                    }
                }
                existing.update(from: item)
                existing.syncStatusRaw = BacklogSyncStatus.synced
                existing.lastSyncedAt = Date()
            } else {
                let cached = CachedBacklogItem(from: item)
                cached.syncStatusRaw = BacklogSyncStatus.synced
                cached.lastSyncedAt = Date()
                context.insert(cached)
            }
        }

        saveContextOrSetError(context, operation: "persist backlog cache")
    }

    private func replayPendingMutationsInBackground() {
        guard !isReplayingPendingMutations else { return }
        isReplayingPendingMutations = true

        _ = _Concurrency.Task(priority: .utility) { [self] in
            await flushPendingSync()
            isReplayingPendingMutations = false
        }
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
                _ = try await cloudKit.saveBacklogCategory(
                    cached.toBacklogCategory(),
                    scope: cloudScope
                )
                cached.syncStatusRaw = BacklogSyncStatus.synced
                cached.lastSyncedAt = Date()
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        for cached in pendingItemUploads {
            do {
                _ = try await cloudKit.saveBacklogItem(
                    cached.toBacklogItem(),
                    scope: cloudScope
                )
                cached.syncStatusRaw = BacklogSyncStatus.awaitingCloudEcho
                cached.lastSyncedAt = Date()
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        for cached in pendingItemDeletes {
            do {
                try await cloudKit.deleteBacklogItem(
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
            _ = try await cloudKit.saveBacklogCategory(category, scope: cloudScope)

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

    @discardableResult
    func deleteCategory(_ category: BacklogCategory) async -> CategoryDeletionResult {
        if let reason = categoryDeletionBlockReason(for: category.id) {
            return .blocked(reason)
        }

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

        if !isCloudSyncEnabled { return .deleted }

        do {
            try await cloudKit.deleteBacklogCategory(
                id: category.id,
                householdId: category.householdId,
                scope: cloudScope
            )
            // CloudKit should cascade delete items optionally, or we delete them explicitly?
            // Assuming we handle items delete or specific logic elsewhere, but for now just category delete.
            // Ideally we should delete items first or rely on CloudKit references if configured.
            // For safety, let's assume we need to delete items locally and hope valid refs handle it or we iterate.
            // But deleting the category is the main action here.
        } catch {
            self.error = error
            await loadData() // Reload on error
        }

        return .deleted
    }

    func categoryDeletionBlockReason(for categoryId: UUID) -> CategoryDeletionBlockReason? {
        let ideaCount = items.filter { $0.categoryId == categoryId }.count
        let linkedTaskCount = activeOrCompletedTaskCount(for: categoryId)

        if ideaCount > 0, linkedTaskCount > 0 {
            return .ideasAndTasks(ideaCount: ideaCount, taskCount: linkedTaskCount)
        }
        if ideaCount > 0 {
            return .ideas(count: ideaCount)
        }
        if linkedTaskCount > 0 {
            return .tasks(count: linkedTaskCount)
        }

        return nil
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
                newColorHex: updatedCategory.colorHex,
                scope: cloudScope
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
            try await cloudKit.saveBacklogCategoriesBatch(categories, scope: cloudScope)
            for category in categories {
                markCachedCategoryAwaitingCloudEcho(id: category.id)
            }
        } catch {
            self.error = error
            for category in categories {
                do {
                    _ = try await cloudKit.saveBacklogCategory(category, scope: cloudScope)
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

        let resolvedCategoryId: UUID? = if let backlogCategoryId = task.backlogCategoryId,
                                           categories.contains(where: { $0.id == backlogCategoryId })
        {
            backlogCategoryId
        } else if let fallbackCategoryId,
                  categories.contains(where: { $0.id == fallbackCategoryId })
        {
            fallbackCategoryId
        } else {
            categories.first?.id
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
            _ = try await cloudKit.saveBacklogItem(item, scope: cloudScope)
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
            replayPendingMutationsInBackground()
            return item
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
            _ = try await cloudKit.saveBacklogItem(item, scope: cloudScope)

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
            // Do NOT remove item from the visible list on failure — the local cache already
            // holds it as pendingUpload and replayPendingMutationsInBackground will retry.
            // Removing it here would violate offline-first and create the visible "delay"
            // where the item disappears and reappears once CloudKit eventually accepts it.
            replayPendingMutationsInBackground()
        }
    }

    @discardableResult
    func deleteItem(_ item: BacklogItem) async -> Bool {
        await deleteItemInternal(item)
    }

    private func deleteItemInternal(_ item: BacklogItem) async -> Bool {
        let removedItemIndex = items.firstIndex(where: { $0.id == item.id })
        if let removedItemIndex {
            withAnimation {
                items.remove(at: removedItemIndex)
            }
        }

        if !isCloudSyncEnabled {
            removeCachedItem(id: item.id)
            return true
        }

        guard markCachedItemPendingDelete(item) else {
            if let removedItemIndex {
                withAnimation {
                    let safeIndex = min(removedItemIndex, items.count)
                    items.insert(item, at: safeIndex)
                }
            }
            return false
        }

        replayPendingMutationsInBackground()
        return true
    }

    @discardableResult
    private func markCachedItemPendingDelete(_ item: BacklogItem) -> Bool {
        markCachedItemPendingDelete(item, shouldSave: true)
    }

    @discardableResult
    private func markCachedItemPendingDelete(_ item: BacklogItem, shouldSave: Bool) -> Bool {
        guard let context = modelContext else { return false }

        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == item.id }
        )

        if let cached = try? context.fetch(descriptor).first {
            // Replace the visible cache row with a tombstone so SwiftData-backed reloads
            // cannot resurrect the promoted idea in the same session.
            context.delete(cached)
        }

        let tombstone = CachedBacklogItem(from: item)
        tombstone.syncStatusRaw = BacklogSyncStatus.pendingDelete
        tombstone.lastSyncedAt = nil
        context.insert(tombstone)
        if shouldSave {
            return saveContextOrSetError(context, operation: "insert backlog tombstone")
        }
        return true
    }

    private func removeCachedItem(id: UUID) {
        removeCachedItem(id: id, shouldSave: true)
    }

    private func removeCachedItem(id: UUID, shouldSave: Bool) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            context.delete(cached)
            if shouldSave {
                saveContextOrSetError(context, operation: "persist backlog cache")
            }
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
            _ = try await cloudKit.saveBacklogItem(updatedItem, scope: cloudScope)
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
        let resolvedAssigneeId = assigneeId ?? item.assigneeId

        if preferredStatus != .backlog, resolvedAssigneeId == nil {
            return .assigneeRequired
        }

        let createdTask = Task(
            id: UUID(),
            householdId: householdId,
            title: item.title,
            status: preferredStatus,
            assigneeId: resolvedAssigneeId,
            assigneeIds: resolvedAssigneeId.map { [$0] } ?? [],
            backlogCategoryId: item.categoryId,
            taskType: .oneOff,
            notes: item.notes,
            order: preferredStatus == .next ? nextTaskOrderBaselineFromCache() + 1 : 0,
            createdAt: item.createdAt,
            updatedAt: Date()
        )

        beginMutation(item.id)
        defer { endMutation(item.id) }

        withAnimation {
            items.removeAll { $0.id == item.id }
        }

        upsertCachedTask(
            createdTask,
            syncStatusRaw: isCloudSyncEnabled ? "pendingUpload" : "synced",
            lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
            shouldSave: false
        )

        if isCloudSyncEnabled {
            guard markCachedItemPendingDelete(item, shouldSave: false) else {
                withAnimation {
                    items.insert(item, at: 0)
                }
                removeCachedTask(id: createdTask.id, shouldSave: false)
                _ = saveContextOrSetError(modelContext, operation: "rollback idea promotion")
                return .failed("Couldn't remove item from Ideas.")
            }
        } else {
            removeCachedItem(id: item.id, shouldSave: false)
        }

        guard saveContextOrSetError(modelContext, operation: "promote idea to task locally") else {
            withAnimation {
                items.insert(item, at: 0)
            }
            removeCachedTask(id: createdTask.id, shouldSave: false)
            _ = saveContextOrSetError(modelContext, operation: "rollback idea promotion")
            return .failed("Couldn't save the task locally.")
        }

        NotificationCenter.default.post(name: .taskBoardDataDidChange, object: nil)

        if isCloudSyncEnabled {
            syncPromotedTaskDestinationInBackground(createdTask)
            replayPendingMutationsInBackground()
        }

        return .success(createdTaskId: createdTask.id)
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
            if let cloudItem = mergedByID[id],
               cloudBacklogItemMatchesLocalMutationEcho(cloudItem, localItem: pendingItem)
            {
                mergedByID[id] = cloudItem
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

    private func activeOrCompletedTaskCount(for categoryId: UUID) -> Int {
        guard let context = modelContext, let householdId else { return 0 }

        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate {
                $0.householdId == householdId && $0.backlogCategoryId == categoryId
            }
        )
        let cachedTasks = (try? context.fetch(descriptor)) ?? []
        return cachedTasks.filter { $0.syncStatusRaw != SyncStatus.pendingDelete.rawValue }.count
    }

    func resolveDestinationCategoryIdForTaskMove(
        _ task: Task,
        fallbackCategoryId: UUID? = nil
    ) -> UUID? {
        if let backlogCategoryId = task.backlogCategoryId,
           categories.contains(where: { $0.id == backlogCategoryId })
        {
            return backlogCategoryId
        }

        if let fallbackCategoryId,
           categories.contains(where: { $0.id == fallbackCategoryId })
        {
            return fallbackCategoryId
        }

        if let visibleCategory = categories.first {
            return visibleCategory.id
        }

        guard let context = modelContext, let householdId else { return nil }
        let descriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor))?.first?.id
    }

    private func upsertCachedTask(
        _ task: Task,
        syncStatusRaw: String,
        lastSyncedAt: Date?,
        shouldSave: Bool
    ) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == task.id }
        )
        if let cached = try? context.fetch(descriptor).first {
            cached.update(from: task)
            cached.syncStatusRaw = syncStatusRaw
            cached.lastSyncedAt = lastSyncedAt
        } else {
            let cached = CachedTask(from: task)
            cached.syncStatusRaw = syncStatusRaw
            cached.lastSyncedAt = lastSyncedAt
            context.insert(cached)
        }

        if shouldSave {
            saveContextOrSetError(context, operation: "persist promoted task cache")
        }
    }

    private func removeCachedTask(id: UUID, shouldSave: Bool) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            context.delete(cached)
        }

        if shouldSave {
            saveContextOrSetError(context, operation: "remove promoted task cache")
        }
    }

    private func markCachedTaskAwaitingCloudEcho(id: UUID) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == id }
        )
        if let cached = try? context.fetch(descriptor).first {
            cached.syncStatusRaw = "awaitingCloudEcho"
            cached.lastSyncedAt = Date()
            saveContextOrSetError(context, operation: "mark promoted task awaiting cloud echo")
        }
    }

    private func syncPromotedTaskDestinationInBackground(_ task: Task) {
        _ = _Concurrency.Task { [self] in
            do {
                _ = try await cloudKit.saveTask(task, scope: cloudScope)
                markCachedTaskAwaitingCloudEcho(id: task.id)
            } catch {
                self.error = error
            }
        }
    }

    private func nextTaskOrderBaselineFromCache() -> Int {
        guard let context = modelContext, let householdId else { return -1 }
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedTasks = (try? context.fetch(descriptor)) ?? []
        return cachedTasks
            .filter {
                $0.statusRaw == Task.TaskStatus.next.rawValue &&
                    $0.syncStatusRaw != SyncStatus.pendingDelete.rawValue
            }
            .map(\.order)
            .max() ?? -1
    }

    private func cloudBacklogItemMatchesLocalMutationEcho(
        _ cloudItem: BacklogItem,
        localItem: BacklogItem
    ) -> Bool {
        guard cloudItem.updatedAt >= localItem.updatedAt else { return false }

        return cloudItem.categoryId == localItem.categoryId &&
            cloudItem.title == localItem.title &&
            cloudItem.assigneeId == localItem.assigneeId &&
            cloudItem.notes == localItem.notes
    }

    private func shouldForceVisibleHydration() -> Bool {
        needsLocalRehydrate || !hasHydratedVisibleSnapshot || (categories.isEmpty && items.isEmpty)
    }
}

// swiftlint:enable file_length
