import Foundation
import SwiftData
import SwiftUI

// swiftlint:disable file_length type_body_length

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
        var pendingDeleteItemLogicalIDs: Set<UUID>
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

    private func persistIdeaWorkItem(
        _ item: BacklogItem,
        syncStatusRaw: String,
        lastSyncedAt: Date?,
        shouldSave: Bool,
        operation: String
    ) {
        guard let context = modelContext else { return }
        WorkItemCacheStoreSupport.upsert(
            WorkItem(idea: item),
            syncStatusRaw: syncStatusRaw,
            lastSyncedAt: lastSyncedAt,
            context: context,
            shouldSave: shouldSave
        ) { [self] defaultOperation in
            saveContextOrSetError(
                context,
                operation: operation.isEmpty ? defaultOperation : operation
            )
        }
    }

    private func markIdeaWorkItemPendingDelete(
        _ item: BacklogItem,
        shouldSave: Bool,
        operation: String
    ) {
        guard let context = modelContext else { return }
        WorkItemCacheStoreSupport.markPendingDelete(
            WorkItem(idea: item),
            context: context,
            shouldSave: shouldSave
        ) { [self] defaultOperation in
            saveContextOrSetError(
                context,
                operation: operation.isEmpty ? defaultOperation : operation
            )
        }
    }

    private func markIdeaWorkItemAwaitingCloudEcho(id: UUID, operation: String) {
        guard let context = modelContext else { return }
        WorkItemCacheStoreSupport.markAwaitingCloudEcho(
            id: id,
            context: context,
            shouldSave: true
        ) { [self] defaultOperation in
            saveContextOrSetError(
                context,
                operation: operation.isEmpty ? defaultOperation : operation
            )
        }
    }

    private func removeIdeaWorkItem(id: UUID, shouldSave: Bool, operation: String) {
        guard let context = modelContext else { return }
        WorkItemCacheStoreSupport.remove(
            id: id,
            context: context,
            shouldSave: shouldSave
        ) { [self] defaultOperation in
            saveContextOrSetError(
                context,
                operation: operation.isEmpty ? defaultOperation : operation
            )
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

            let categoriesResult = try await fetchedCategories
            let cloudWorkItems = try await cloudKit.fetchUnifiedWorkItems(
                householdId: householdId,
                scope: cloudScope
            )

            syncCategoriesToCache(categoriesResult)
            syncCloudIdeaWorkItemsToCache(cloudWorkItems)
            _ = fetchIdeaWorkItems(updateVisibleState: true)
            replayPendingMutationsInBackground()
        } catch {
            self.error = error
        }
    }

    private func hydrateVisibleSnapshotFromCacheIfNeeded(force: Bool = false) {
        _ = fetchIdeaWorkItems(updateVisibleState: force || shouldForceVisibleHydration())
    }

    private func fetchIdeaWorkItems(updateVisibleState: Bool) -> [CachedWorkItem] {
        guard let context = modelContext, let householdId else {
            if updateVisibleState {
                categories = []
                items = []
                hasHydratedVisibleSnapshot = true
                hasHydratedLocalSnapshot = true
                needsLocalRehydrate = false
            }
            return []
        }

        let categoryDescriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let cachedCategories = (try? context.fetch(categoryDescriptor)) ?? []
        let cachedWorkItems = WorkItemCacheStoreSupport.fetchCachedWorkItems(
            householdId: householdId,
            context: context
        )

        if updateVisibleState {
            categories = cachedCategories.map { $0.toBacklogCategory() }
            items = visibleBacklogItems(from: cachedWorkItems)
            hasHydratedVisibleSnapshot = true
            hasHydratedLocalSnapshot = true
            needsLocalRehydrate = false
        }

        return cachedWorkItems
    }

    private func syncCategoriesToCache(_ cloudCategories: [BacklogCategory]) {
        guard let context = modelContext, let householdId else { return }
        let descriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedCategories = (try? context.fetch(descriptor)) ?? []
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedCategories.map { ($0.id, $0) })

        for category in cloudCategories {
            if let cached = cachedByID[category.id] {
                cached.update(from: category)
            } else {
                context.insert(CachedBacklogCategory(from: category))
            }
        }

        saveContextOrSetError(context, operation: "sync backlog categories to cache")
    }

    private func syncCloudIdeaWorkItemsToCache(_ cloudItems: [WorkItem]) {
        guard let context = modelContext, let householdId else { return }
        let descriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedWorkItems = (try? context.fetch(descriptor)) ?? []
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedWorkItems.map { ($0.id, $0) })
        let pendingSnapshot = WorkItemCacheStoreSupport.pendingSnapshot(from: cachedWorkItems)
        let deduplicatedByLogicalID = WorkItemCacheStoreSupport.canonicalCachedWorkItemsByLogicalItemID(cachedWorkItems)

        for item in cloudItems {
            if pendingSnapshot.pendingDeleteLogicalItemIDs.contains(item.logicalItemID) {
                continue
            }

            if let cached = cachedByID[item.id] {
                if WorkItemCacheStoreSupport.shouldIgnoreCloudSnapshot(
                    item,
                    for: cached,
                    pendingSnapshot: pendingSnapshot,
                    mutationEchoMatches: cloudWorkItemMatchesLocalMutationEcho
                ) {
                    continue
                }
                cached.update(from: item)
                cached.syncStatusRaw = BacklogSyncStatus.synced
                cached.lastSyncedAt = Date()
                continue
            }

            if let cached = deduplicatedByLogicalID[item.logicalItemID] {
                if WorkItemCacheStoreSupport.shouldIgnoreCloudSnapshot(
                    item,
                    for: cached,
                    pendingSnapshot: pendingSnapshot,
                    mutationEchoMatches: cloudWorkItemMatchesLocalMutationEcho
                ) {
                    continue
                }
                cached.update(from: item)
                cached.syncStatusRaw = BacklogSyncStatus.synced
                cached.lastSyncedAt = Date()
                continue
            }

            if cachedByID[item.id] == nil {
                let cached = CachedWorkItem(from: item)
                cached.syncStatusRaw = BacklogSyncStatus.synced
                cached.lastSyncedAt = Date()
                context.insert(cached)
            }
        }

        saveContextOrSetError(context, operation: "sync backlog work items to cache")
    }

    private func visibleBacklogItems(from cachedWorkItems: [CachedWorkItem]) -> [BacklogItem] {
        WorkItemCacheStoreSupport.visibleIdeas(from: cachedWorkItems)
    }

    private func cloudWorkItemMatchesLocalMutationEcho(_ cloudItem: WorkItem, localItem: WorkItem) -> Bool {
        cloudItem.id == localItem.id &&
            cloudItem.logicalItemID == localItem.logicalItemID &&
            cloudItem.status == localItem.status &&
            cloudItem.categoryId == localItem.categoryId &&
            cloudItem.assigneeId == localItem.assigneeId &&
            cloudItem.title == localItem.title &&
            cloudItem.notes == localItem.notes &&
            cloudItem.updatedAt >= localItem.updatedAt
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
                items = deduplicatedVisibleBacklogItems(from: fetchedItems)
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
        _ = cloudCategoryIDs
        syncCategoriesToCache(categories)
        syncCloudIdeaWorkItemsToCache(items.map(WorkItem.init(idea:)))
    }

    private func replayPendingMutationsInBackground() {
        guard !isReplayingPendingMutations else { return }
        isReplayingPendingMutations = true

        _ = _Concurrency.Task(priority: .utility) { [self] in
            await flushPendingSync()
            isReplayingPendingMutations = false
        }
    }

    private func postLocalBacklogRefresh(includeTaskBoard: Bool = false) {
        NotificationCenter.default.post(name: .backlogDataDidChange, object: "local")
        if includeTaskBoard {
            NotificationCenter.default.post(name: .taskBoardDataDidChange, object: "local")
        }
    }

    private func flushPendingSync() async {
        guard isCloudSyncEnabled, let context = modelContext, let householdId else { return }

        let categoryDescriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        let cachedCategories = (try? context.fetch(categoryDescriptor)) ?? []
        let cachedItems = WorkItemCacheStoreSupport.fetchCachedWorkItems(
            householdId: householdId,
            context: context
        )

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
                _ = try await cloudKit.saveWorkItem(cached.toWorkItem(), scope: cloudScope)
                cached.syncStatusRaw = BacklogSyncStatus.awaitingCloudEcho
                cached.lastSyncedAt = Date()
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        for cached in pendingItemDeletes {
            do {
                try await cloudKit.deleteWorkItem(
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

        let didPersistLocally: Bool
        if let context = modelContext {
            let cached = CachedBacklogCategory(from: category)
            cached.syncStatusRaw = isCloudSyncEnabled
                ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            context.insert(cached)
            didPersistLocally = saveContextOrSetError(context, operation: "persist backlog cache")
        } else {
            didPersistLocally = true
        }

        guard didPersistLocally else { return }
        postLocalBacklogRefresh(includeTaskBoard: true)

        guard isCloudSyncEnabled else { return }
        replayPendingMutationsInBackground()
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

        let didPersistLocally: Bool
        if let context = modelContext {
            // Delete category
            let catDescriptor = FetchDescriptor<CachedBacklogCategory>(
                predicate: #Predicate { $0.id == category.id }
            )
            if let cached = try? context.fetch(catDescriptor).first {
                context.delete(cached)
            }

            let cachedWorkItems = WorkItemCacheStoreSupport.fetchCachedWorkItems(
                householdId: category.householdId,
                context: context
            )
            for cached in cachedWorkItems where cached.categoryId == category.id {
                context.delete(cached)
            }
            didPersistLocally = saveContextOrSetError(context, operation: "persist backlog cache")
        } else {
            didPersistLocally = true
        }

        guard didPersistLocally else { return .deleted }
        postLocalBacklogRefresh(includeTaskBoard: true)

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

        let didPersistLocally: Bool
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
                didPersistLocally = saveContextOrSetError(context, operation: "persist backlog cache")
            } else {
                didPersistLocally = true
            }
        } else {
            didPersistLocally = true
        }

        guard didPersistLocally else {
            withAnimation {
                categories[index] = previousCategory
            }
            return
        }
        postLocalBacklogRefresh(includeTaskBoard: true)

        guard isCloudSyncEnabled else { return }
        replayPendingMutationsInBackground()
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

        let didPersistLocally: Bool
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
            didPersistLocally = saveContextOrSetError(context, operation: "persist backlog cache")
        } else {
            didPersistLocally = true
        }

        guard didPersistLocally else { return }
        postLocalBacklogRefresh(includeTaskBoard: true)

        guard isCloudSyncEnabled else { return }
        replayPendingMutationsInBackground()
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
            logicalItemID: task.logicalItemID,
            categoryId: categoryId,
            householdId: householdId,
            title: task.title,
            assigneeId: task.assigneeId,
            notes: task.notes,
            createdAt: task.createdAt
        )

        withAnimation {
            items.insert(item, at: 0)
        }

        persistIdeaWorkItem(
            item,
            syncStatusRaw: isCloudSyncEnabled ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced,
            lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
            shouldSave: true,
            operation: "persist backlog cache"
        )

        guard isCloudSyncEnabled else {
            return item
        }

        do {
            _ = try await cloudKit.saveWorkItem(WorkItem(idea: item), scope: cloudScope)
            markIdeaWorkItemAwaitingCloudEcho(id: item.id, operation: "persist backlog cache")
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
        persistIdeaWorkItem(
            item,
            syncStatusRaw: isCloudSyncEnabled ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced,
            lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
            shouldSave: false,
            operation: "persist backlog cache"
        )

        guard let context = modelContext else {
            postLocalBacklogRefresh()
            guard isCloudSyncEnabled else { return }
            replayPendingMutationsInBackground()
            return
        }

        guard saveContextOrSetError(context, operation: "persist backlog cache") else {
            withAnimation {
                items.removeAll { $0.id == item.id }
            }
            removeIdeaWorkItem(
                id: item.id,
                shouldSave: false,
                operation: "rollback backlog cache after add item failure"
            )
            _ = saveContextOrSetError(context, operation: "rollback backlog cache after add item failure")
            return
        }

        postLocalBacklogRefresh()

        guard isCloudSyncEnabled else { return }
        replayPendingMutationsInBackground()
    }

    @discardableResult
    func deleteItem(_ item: BacklogItem) async -> Bool {
        await deleteItemInternal(item)
    }

    private func deleteItemInternal(_ item: BacklogItem) async -> Bool {
        let removedItemIndex = items.firstIndex(where: { $0.id == item.id })
        if let removedItemIndex {
            _ = withAnimation {
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
        markIdeaWorkItemPendingDelete(
            item,
            shouldSave: false,
            operation: ""
        )
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
        removeIdeaWorkItem(id: id, shouldSave: false, operation: "")
        if shouldSave {
            saveContextOrSetError(context, operation: "persist backlog cache")
        }
    }

    func updateItem(_ item: BacklogItem, title: String, notes: String?) {
        updateItem(item, title: title, notes: notes, assigneeId: item.assigneeId)
    }

    func updateItem(_ item: BacklogItem, title: String, notes: String?, assigneeId: UUID?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard !pendingMutationIDs.contains(item.id) else { return }

        beginMutation(item.id)

        var updatedItem = items[index]
        updatedItem.title = trimmedTitle
        updatedItem.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedItem.assigneeId = assigneeId
        updatedItem.updatedAt = Date()

        withAnimation {
            items[index] = updatedItem
        }

        persistIdeaWorkItem(
            updatedItem,
            syncStatusRaw: isCloudSyncEnabled ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced,
            lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
            shouldSave: false,
            operation: "persist backlog cache"
        )

        guard let context = modelContext else {
            endMutation(item.id)
            return
        }

        guard saveContextOrSetError(context, operation: "persist backlog cache") else {
            withAnimation {
                items[index] = item
            }
            persistIdeaWorkItem(
                item,
                syncStatusRaw: isCloudSyncEnabled ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced,
                lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
                shouldSave: false,
                operation: "rollback backlog cache"
            )
            _ = saveContextOrSetError(context, operation: "rollback backlog cache")
            endMutation(item.id)
            return
        }

        endMutation(item.id)
        postLocalBacklogRefresh()

        guard isCloudSyncEnabled else { return }
        replayPendingMutationsInBackground()
    }

    @discardableResult
    func promoteItemToTask(
        _ item: BacklogItem,
        assigneeId: UUID?,
        preferredStatus: Task.TaskStatus = .next
    ) -> PromotionResult {
        guard let modelContext else {
            return .failed("Missing local context.")
        }
        let resolvedAssigneeId = assigneeId ?? item.assigneeId

        if preferredStatus != .backlog, resolvedAssigneeId == nil {
            return .assigneeRequired
        }

        let existingTask = existingDestinationTask(for: item.logicalItemID)
        let promotedItem: WorkItem
        if let existingTask, existingTask.id != item.id {
            let promotedTask = promotedTaskDestination(
                from: item,
                assigneeId: resolvedAssigneeId,
                preferredStatus: preferredStatus,
                existing: existingTask
            )
            promotedItem = WorkItem(task: promotedTask)
        } else {
            var localPromotedItem = WorkItem(idea: item)
            localPromotedItem.status = WorkItem.Status(taskStatus: preferredStatus)
            localPromotedItem.assigneeId = resolvedAssigneeId
            localPromotedItem.assigneeIds = resolvedAssigneeId.map { [$0] } ?? []
            localPromotedItem.order = preferredStatus == .next ? nextTaskOrderBaselineFromCache() + 1 : 0
            localPromotedItem.updatedAt = Date()
            if preferredStatus == .done {
                localPromotedItem.completedAt = Date()
            } else {
                localPromotedItem.completedAt = nil
                localPromotedItem.completedById = nil
            }
            promotedItem = localPromotedItem
        }

        withAnimation {
            items.removeAll { $0.id == item.id }
        }

        if promotedItem.id != item.id {
            removeIdeaWorkItem(
                id: item.id,
                shouldSave: false,
                operation: "remove source idea after promotion"
            )
        }

        WorkItemCacheStoreSupport.upsert(
            promotedItem,
            syncStatusRaw: isCloudSyncEnabled ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced,
            lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
            context: modelContext,
            shouldSave: false
        ) { [self] _ in
            saveContextOrSetError(modelContext, operation: "persist promoted idea work item")
        }

        guard saveContextOrSetError(modelContext, operation: "promote idea to task locally") else {
            withAnimation {
                items.insert(item, at: 0)
            }
            persistIdeaWorkItem(
                item,
                syncStatusRaw: isCloudSyncEnabled ? BacklogSyncStatus.pendingUpload : BacklogSyncStatus.synced,
                lastSyncedAt: isCloudSyncEnabled ? nil : Date(),
                shouldSave: false,
                operation: "rollback promoted idea work item"
            )
            _ = saveContextOrSetError(modelContext, operation: "rollback idea promotion")
            return .failed("Couldn't save the task locally.")
        }

        postLocalBacklogRefresh(includeTaskBoard: true)

        if isCloudSyncEnabled {
            replayPendingMutationsInBackground()
        }

        return .success(createdTaskId: promotedItem.id)
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
        var pendingDeleteItemLogicalIDs = Set<UUID>()
        var pendingCategoriesByID: [UUID: BacklogCategory] = [:]
        for cached in cachedItems {
            switch cached.syncStatusRaw {
            case BacklogSyncStatus.pendingUpload, BacklogSyncStatus.awaitingCloudEcho:
                pendingUploadItemsByID[cached.id] = cached.toBacklogItem()
            case BacklogSyncStatus.pendingDelete:
                pendingDeleteItemIDs.insert(cached.id)
                pendingDeleteItemLogicalIDs.insert(resolvedLogicalItemID(for: cached))
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
            pendingDeleteItemLogicalIDs: pendingDeleteItemLogicalIDs,
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
        var mergedByLogicalID = Dictionary(
            uniqueKeysWithValues: deduplicatedCloudBacklogItems(cloudItems).map { ($0.logicalItemID, $0) }
        )
        let localByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        for pendingItem in pendingSnapshot.pendingUploadItemsByID.values {
            if let cloudItem = mergedByLogicalID[pendingItem.logicalItemID],
               cloudBacklogItemMatchesLocalMutationEcho(cloudItem, localItem: pendingItem)
            {
                mergedByLogicalID[pendingItem.logicalItemID] = cloudItem
                continue
            }
            mergedByLogicalID[pendingItem.logicalItemID] = pendingItem
        }

        for logicalID in pendingSnapshot.pendingDeleteItemLogicalIDs {
            mergedByLogicalID.removeValue(forKey: logicalID)
        }

        for id in pendingMutationIDs {
            if let local = localByID[id] {
                mergedByLogicalID[local.logicalItemID] = local
            }
        }

        return mergedByLogicalID.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func activeOrCompletedTaskCount(for categoryId: UUID) -> Int {
        guard let context = modelContext, let householdId else { return 0 }
        let cachedWorkItems = WorkItemCacheStoreSupport.fetchCachedWorkItems(
            householdId: householdId,
            context: context
        )

        return cachedWorkItems.filter { cached in
            let workItem = cached.toWorkItem()
            guard workItem.status != .idea else { return false }
            guard workItem.categoryId == categoryId else { return false }
            return cached.syncStatusRaw != BacklogSyncStatus.pendingDelete
        }.count
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

    private func nextTaskOrderBaselineFromCache() -> Int {
        guard let context = modelContext, let householdId else { return -1 }
        let cachedWorkItems = WorkItemCacheStoreSupport.fetchCachedWorkItems(
            householdId: householdId,
            context: context
        )
        return cachedWorkItems
            .filter {
                $0.statusRaw == WorkItem.Status.next.rawValue &&
                    $0.syncStatusRaw != BacklogSyncStatus.pendingDelete
            }
            .map(\.order)
            .max() ?? -1
    }

    private func cloudBacklogItemMatchesLocalMutationEcho(
        _ cloudItem: BacklogItem,
        localItem: BacklogItem
    ) -> Bool {
        guard cloudItem.updatedAt >= localItem.updatedAt else { return false }

        return cloudItem.logicalItemID == localItem.logicalItemID &&
            cloudItem.categoryId == localItem.categoryId &&
            cloudItem.title == localItem.title &&
            cloudItem.assigneeId == localItem.assigneeId &&
            cloudItem.notes == localItem.notes
    }

    private func resolvedLogicalItemID(for cached: CachedBacklogItem) -> UUID {
        cached.logicalItemID ?? cached.id
    }

    private func deduplicatedVisibleBacklogItems(from cachedItems: [CachedBacklogItem]) -> [BacklogItem] {
        let tombstonedLogicalItemIDs = Set(
            cachedItems.compactMap { cachedItem in
                cachedItem.syncStatusRaw == BacklogSyncStatus.pendingDelete
                    ? resolvedLogicalItemID(for: cachedItem) : nil
            }
        )

        return canonicalCachedBacklogItemsByLogicalItemID(cachedItems)
            .filter { !tombstonedLogicalItemIDs.contains($0.key) }
            .values
            .filter { $0.syncStatusRaw != BacklogSyncStatus.pendingDelete }
            .map { $0.toBacklogItem() }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func canonicalCachedBacklogItemsByLogicalItemID(
        _ cachedItems: [CachedBacklogItem]
    ) -> [UUID: CachedBacklogItem] {
        var deduplicated: [UUID: CachedBacklogItem] = [:]

        for cached in cachedItems {
            let logicalItemID = resolvedLogicalItemID(for: cached)
            if let existing = deduplicated[logicalItemID] {
                if shouldPreferCachedBacklogItem(cached, over: existing) {
                    deduplicated[logicalItemID] = cached
                }
            } else {
                deduplicated[logicalItemID] = cached
            }
        }

        return deduplicated
    }

    private func shouldPreferCachedBacklogItem(
        _ candidate: CachedBacklogItem,
        over current: CachedBacklogItem
    ) -> Bool {
        let candidatePriority = backlogSyncPriority(candidate.syncStatusRaw)
        let currentPriority = backlogSyncPriority(current.syncStatusRaw)
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

    private func backlogSyncPriority(_ syncStatusRaw: String) -> Int {
        switch syncStatusRaw {
        case BacklogSyncStatus.pendingUpload, BacklogSyncStatus.awaitingCloudEcho:
            3
        case BacklogSyncStatus.synced:
            2
        case BacklogSyncStatus.pendingDelete:
            0
        default:
            1
        }
    }

    private func deduplicatedCloudBacklogItems(_ items: [BacklogItem]) -> [BacklogItem] {
        var deduplicated: [UUID: BacklogItem] = [:]

        for item in items {
            if let existing = deduplicated[item.logicalItemID] {
                if shouldPreferCloudBacklogItem(item, over: existing) {
                    deduplicated[item.logicalItemID] = item
                }
            } else {
                deduplicated[item.logicalItemID] = item
            }
        }

        return Array(deduplicated.values)
    }

    private func shouldPreferCloudBacklogItem(
        _ candidate: BacklogItem,
        over current: BacklogItem
    ) -> Bool {
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }
        if candidate.createdAt != current.createdAt {
            return candidate.createdAt > current.createdAt
        }
        return candidate.id.uuidString < current.id.uuidString
    }

    private func shouldReplaceBacklogLineageConflict(
        with cloudItem: BacklogItem,
        existing: BacklogItem
    ) -> Bool {
        cloudItem.updatedAt >= existing.updatedAt
    }

    private func existingDestinationTask(for logicalItemID: UUID) -> Task? {
        guard let context = modelContext, let householdId else { return nil }
        let cachedWorkItems = WorkItemCacheStoreSupport.fetchCachedWorkItems(
            householdId: householdId,
            context: context
        )

        return cachedWorkItems
            .filter {
                $0.logicalItemID == logicalItemID &&
                    $0.syncStatusRaw != BacklogSyncStatus.pendingDelete &&
                    $0.toWorkItem().status != .idea
            }
            .max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }?
            .toWorkItem()
            .asTask()
    }

    private func promotedTaskDestination(
        from item: BacklogItem,
        assigneeId: UUID?,
        preferredStatus: Task.TaskStatus,
        existing: Task?
    ) -> Task {
        if var existing {
            let previousStatus = existing.status
            existing.title = item.title
            existing.status = preferredStatus
            existing.assigneeId = assigneeId
            existing.assigneeIds = assigneeId.map { [$0] } ?? []
            existing.backlogCategoryId = item.categoryId
            existing.notes = item.notes
            existing.order = preferredStatus == .next
                ? (previousStatus == .next ? existing.order : nextTaskOrderBaselineFromCache() + 1)
                : 0
            existing.updatedAt = Date()
            existing.completedAt = preferredStatus == .done ? (existing.completedAt ?? Date()) : nil
            if preferredStatus != .done {
                existing.completedById = nil
            }
            return existing
        }

        return Task(
            id: UUID(),
            logicalItemID: item.logicalItemID,
            householdId: householdId ?? item.householdId,
            title: item.title,
            status: preferredStatus,
            assigneeId: assigneeId,
            assigneeIds: assigneeId.map { [$0] } ?? [],
            backlogCategoryId: item.categoryId,
            taskType: .oneOff,
            notes: item.notes,
            order: preferredStatus == .next ? nextTaskOrderBaselineFromCache() + 1 : 0,
            createdAt: item.createdAt,
            updatedAt: Date()
        )
    }

    private func shouldForceVisibleHydration() -> Bool {
        needsLocalRehydrate || !hasHydratedVisibleSnapshot || (categories.isEmpty && items.isEmpty)
    }
}

// swiftlint:enable file_length type_body_length
