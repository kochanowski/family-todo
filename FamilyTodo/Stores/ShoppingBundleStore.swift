import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ShoppingBundleStore: ObservableObject {
    private enum BundleSyncStatus {
        static let synced = "synced"
        static let pendingUpload = "pendingUpload"
        static let pendingDelete = "pendingDelete"
        static let awaitingCloudEcho = "awaitingCloudEcho"
        static let awaitingDeleteEcho = "awaitingDeleteEcho"
    }

    struct PendingSyncSnapshot {
        var pendingUploadByID: [UUID: ShoppingBundle]
        var pendingDeleteIDs: Set<UUID>
    }

    @Published private(set) var bundles: [ShoppingBundle] = []
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
    private var isReplayingPendingMutations = false
    private var shouldReplayPendingMutationsAfterCurrentPass = false
    private var activeLoadTask: _Concurrency.Task<Void, Never>?
    private var shouldReloadAfterCurrentLoad = false
    private var hasHydratedVisibleSnapshot = false

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
        operation: String = "persist shopping bundle cache",
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        StoreContextSaver.saveContextOrSetError(
            context ?? modelContext,
            store: "ShoppingBundleStore",
            operation: operation,
            file: file,
            line: line
        ) { [self] saveError in
            error = saveError
        }
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
        hydrateVisibleSnapshotFromCacheIfNeeded(force: true)
    }

    var quickAddBundles: [ShoppingBundle] {
        bundles.filter { !$0.normalizedItems.isEmpty }
    }

    func loadBundlesForDisplay() async {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: !hasHydratedVisibleSnapshot || bundles.isEmpty)
        guard isCloudSyncEnabled else { return }
        scheduleBackgroundRefresh()
    }

    func loadBundles() async {
        hydrateVisibleSnapshotFromCacheIfNeeded(force: !hasHydratedVisibleSnapshot || bundles.isEmpty)
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
                await performLoadBundlesPass()
            } while shouldReloadAfterCurrentLoad

            activeLoadTask = nil
        }

        activeLoadTask = loadTask
        return loadTask
    }

    private func performLoadBundlesPass() async {
        guard let householdId else { return }

        isLoading = true
        isRefreshingInBackground = true
        error = nil
        defer {
            isLoading = false
            isRefreshingInBackground = false
        }

        hydrateVisibleSnapshotFromCacheIfNeeded(force: !hasHydratedVisibleSnapshot || bundles.isEmpty)

        if !isCloudSyncEnabled {
            return
        }

        do {
            await cloudKit.ensureReady()
            let fetchedBundles = try await cloudKit.fetchShoppingBundles(
                householdId: householdId,
                scope: cloudScope
            )
            let latestCachedBundles = fetchCachedBundles(updateVisibleState: false)
            let latestPendingSnapshot = pendingSyncSnapshot(from: latestCachedBundles)
            bundles = mergeCloudSnapshot(fetchedBundles, with: latestPendingSnapshot)
            syncToCache(fetchedBundles, cloudBundleIDs: Set(fetchedBundles.map(\.id)))
            replayPendingMutationsInBackground()
        } catch {
            self.error = error
        }
    }

    private func hydrateVisibleSnapshotFromCacheIfNeeded(force: Bool = false) {
        _ = fetchCachedBundles(updateVisibleState: force || !hasHydratedVisibleSnapshot || bundles.isEmpty)
    }

    private func fetchCachedBundles(updateVisibleState: Bool) -> [CachedShoppingBundle] {
        guard let context = modelContext, let householdId else {
            if updateVisibleState {
                bundles = []
                hasHydratedVisibleSnapshot = true
                hasHydratedLocalSnapshot = true
            }
            return []
        }

        let descriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )

        let cachedBundles = (try? context.fetch(descriptor)) ?? []
        if updateVisibleState {
            bundles = cachedBundles
                .filter {
                    $0.syncStatusRaw != BundleSyncStatus.pendingDelete &&
                        $0.syncStatusRaw != BundleSyncStatus.awaitingDeleteEcho
                }
                .map { $0.toShoppingBundle() }
            hasHydratedVisibleSnapshot = true
            hasHydratedLocalSnapshot = true
        }
        return cachedBundles
    }

    private func syncToCache(_ bundles: [ShoppingBundle], cloudBundleIDs: Set<UUID>) {
        guard let context = modelContext, let householdId else { return }

        let descriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedBundles = (try? context.fetch(descriptor)) ?? []
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedBundles.map { ($0.id, $0) })
        let pendingDeleteSnapshot = pendingSyncSnapshot(from: cachedBundles)
        let pendingDeleteIDs = pendingDeleteSnapshot.pendingDeleteIDs

        for bundle in bundles {
            if pendingDeleteIDs.contains(bundle.id) {
                continue
            }
            if let existing = cachedByID[bundle.id] {
                if existing.syncStatusRaw == BundleSyncStatus.pendingUpload ||
                    existing.syncStatusRaw == BundleSyncStatus.pendingDelete ||
                    existing.syncStatusRaw == BundleSyncStatus.awaitingDeleteEcho
                {
                    continue
                }
                if existing.syncStatusRaw == BundleSyncStatus.awaitingCloudEcho,
                   !cloudBundleIDs.contains(bundle.id)
                {
                    continue
                }
                existing.update(from: bundle)
                existing.lastSyncedAt = Date()
            } else {
                context.insert(CachedShoppingBundle(from: bundle))
            }
        }

        for cached in cachedBundles where
            cached.syncStatusRaw == BundleSyncStatus.awaitingDeleteEcho &&
            !cloudBundleIDs.contains(cached.id) &&
            !pendingDeleteIDs.contains(cached.id)
        {
            context.delete(cached)
        }

        saveContextOrSetError(context, operation: "sync shopping bundle cache from cloud")
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

        let descriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedBundles = (try? context.fetch(descriptor)) ?? []

        let pendingUploads = cachedBundles.filter {
            $0.syncStatusRaw == BundleSyncStatus.pendingUpload
        }
        let pendingDeletes = cachedBundles.filter {
            $0.syncStatusRaw == BundleSyncStatus.pendingDelete
        }

        guard !pendingUploads.isEmpty || !pendingDeletes.isEmpty else { return }

        var didMutateCache = false

        for cached in pendingUploads {
            do {
                _ = try await cloudKit.saveShoppingBundle(
                    cached.toShoppingBundle(),
                    scope: cloudScope
                )
                cached.syncStatusRaw = BundleSyncStatus.awaitingCloudEcho
                cached.lastSyncedAt = Date()
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        for cached in pendingDeletes {
            do {
                try await cloudKit.deleteShoppingBundle(
                    id: cached.id,
                    householdId: cached.householdId,
                    scope: cloudScope
                )
                cached.syncStatusRaw = BundleSyncStatus.awaitingDeleteEcho
                cached.lastSyncedAt = Date()
                didMutateCache = true
            } catch {
                self.error = error
            }
        }

        if didMutateCache {
            saveContextOrSetError(context, operation: "flush pending shopping bundle sync")
        }
    }

    func createBundle(
        name: String,
        icon: String = ShoppingBundle.creationDefaultIcon,
        items: [String]
    ) async {
        guard let householdId else { return }

        let cleanedName = ShoppingBundle.sanitizedName(name)
        let cleanedItems = ShoppingBundle.sanitizedItems(items)
        guard !cleanedName.isEmpty, !cleanedItems.isEmpty else { return }

        let bundle = ShoppingBundle(
            householdId: householdId,
            name: cleanedName,
            icon: icon,
            items: cleanedItems,
            sortOrder: nextSortOrder()
        )

        withAnimation {
            bundles.append(bundle)
            sortBundlesInPlace()
        }

        upsertCachedBundle(
            bundle,
            syncStatusRaw: isCloudSyncEnabled ? BundleSyncStatus.pendingUpload : BundleSyncStatus.synced,
            lastSyncedAt: isCloudSyncEnabled ? nil : Date()
        )

        guard isCloudSyncEnabled else { return }
        replayPendingMutationsInBackground()
    }

    func updateBundle(_ bundle: ShoppingBundle) async {
        guard let index = bundles.firstIndex(where: { $0.id == bundle.id }) else { return }

        let cleanedName = bundle.normalizedName
        let cleanedItems = bundle.normalizedItems
        guard !cleanedName.isEmpty, !cleanedItems.isEmpty else { return }

        var updatedBundle = bundle
        updatedBundle.name = cleanedName
        updatedBundle.icon = bundle.resolvedIcon
        updatedBundle.items = cleanedItems
        updatedBundle.updatedAt = Date()

        withAnimation {
            bundles[index] = updatedBundle
            sortBundlesInPlace()
        }

        upsertCachedBundle(
            updatedBundle,
            syncStatusRaw: isCloudSyncEnabled ? BundleSyncStatus.pendingUpload : BundleSyncStatus.synced,
            lastSyncedAt: isCloudSyncEnabled ? nil : Date()
        )

        guard isCloudSyncEnabled else { return }
        replayPendingMutationsInBackground()
    }

    func deleteBundle(_ bundle: ShoppingBundle) async {
        withAnimation {
            bundles.removeAll { $0.id == bundle.id }
        }

        let bundleId = bundle.id
        let descriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.id == bundleId }
        )

        if let context = modelContext {
            if let cached = try? context.fetch(descriptor).first {
                if isCloudSyncEnabled {
                    cached.syncStatusRaw = BundleSyncStatus.pendingDelete
                    cached.lastSyncedAt = nil
                    saveContextOrSetError(context, operation: "mark shopping bundle pending delete")
                } else {
                    context.delete(cached)
                    saveContextOrSetError(context, operation: "delete shopping bundle from cache")
                }
            } else if isCloudSyncEnabled {
                let cached = CachedShoppingBundle(from: bundle)
                cached.syncStatusRaw = BundleSyncStatus.pendingDelete
                cached.lastSyncedAt = nil
                context.insert(cached)
                saveContextOrSetError(context, operation: "cache shopping bundle pending delete")
            }
        }

        guard isCloudSyncEnabled else { return }
        replayPendingMutationsInBackground()
    }

    func pendingSyncSnapshot(from cachedBundles: [CachedShoppingBundle]) -> PendingSyncSnapshot {
        var pendingUploadByID: [UUID: ShoppingBundle] = [:]
        var pendingDeleteIDs = Set<UUID>()

        for cached in cachedBundles {
            switch cached.syncStatusRaw {
            case BundleSyncStatus.pendingUpload, BundleSyncStatus.awaitingCloudEcho:
                pendingUploadByID[cached.id] = cached.toShoppingBundle()
            case BundleSyncStatus.pendingDelete, BundleSyncStatus.awaitingDeleteEcho:
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
        _ cloudBundles: [ShoppingBundle],
        with pendingSnapshot: PendingSyncSnapshot
    ) -> [ShoppingBundle] {
        var mergedByID = Dictionary(uniqueKeysWithValues: cloudBundles.map { ($0.id, $0) })

        for (id, pendingBundle) in pendingSnapshot.pendingUploadByID {
            if let cloudBundle = mergedByID[id], cloudBundle.updatedAt > pendingBundle.updatedAt {
                continue
            }
            mergedByID[id] = pendingBundle
        }

        for id in pendingSnapshot.pendingDeleteIDs {
            mergedByID.removeValue(forKey: id)
        }

        return mergedByID.values.sorted { lhs, rhs in
            sortPredicate(lhs, rhs)
        }
    }

    private func nextSortOrder() -> Int {
        (bundles.map(\.sortOrder).max() ?? -1) + 1
    }

    private func sortBundlesInPlace() {
        bundles.sort { lhs, rhs in
            sortPredicate(lhs, rhs)
        }
    }

    private func sortPredicate(_ lhs: ShoppingBundle, _ rhs: ShoppingBundle) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func upsertCachedBundle(
        _ bundle: ShoppingBundle,
        syncStatusRaw: String,
        lastSyncedAt: Date?
    ) {
        guard let context = modelContext else { return }

        let bundleId = bundle.id
        let descriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.id == bundleId }
        )

        if let cached = try? context.fetch(descriptor).first {
            cached.update(from: bundle)
            cached.syncStatusRaw = syncStatusRaw
            cached.lastSyncedAt = lastSyncedAt
        } else {
            let cached = CachedShoppingBundle(from: bundle)
            cached.syncStatusRaw = syncStatusRaw
            cached.lastSyncedAt = lastSyncedAt
            context.insert(cached)
        }

        saveContextOrSetError(context, operation: "upsert shopping bundle cache")
    }

    private func markCachedBundleAwaitingCloudEcho(id: UUID) {
        guard let context = modelContext else { return }

        let bundleId = id
        let descriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.id == bundleId }
        )

        if let cached = try? context.fetch(descriptor).first {
            cached.syncStatusRaw = BundleSyncStatus.awaitingCloudEcho
            cached.lastSyncedAt = Date()
            saveContextOrSetError(context, operation: "mark shopping bundle awaiting cloud echo")
        }
    }
}
