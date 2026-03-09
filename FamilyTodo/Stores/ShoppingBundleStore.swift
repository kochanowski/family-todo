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
    }

    struct PendingSyncSnapshot {
        var pendingUploadByID: [UUID: ShoppingBundle]
        var pendingDeleteIDs: Set<UUID>
    }

    @Published private(set) var bundles: [ShoppingBundle] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private lazy var cloudKit = CloudKitManager.shared
    private let householdId: UUID?
    private var modelContext: ModelContext?
    private var syncMode: SyncMode = .cloud
    private var isReplayingPendingMutations = false
    private var shouldReplayPendingMutationsAfterCurrentPass = false

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
    }

    var quickAddBundles: [ShoppingBundle] {
        bundles.filter { !$0.normalizedItems.isEmpty }
    }

    func loadBundles() async {
        guard let householdId else { return }

        isLoading = true
        error = nil

        let cachedBundles = loadFromCache()
        let pendingSnapshot = pendingSyncSnapshot(from: cachedBundles)

        if !isCloudSyncEnabled {
            isLoading = false
            return
        }

        do {
            await cloudKit.ensureReady()
            let fetchedBundles = try await cloudKit.fetchShoppingBundles(householdId: householdId)
            bundles = mergeCloudSnapshot(fetchedBundles, with: pendingSnapshot)
            syncToCache(fetchedBundles, cloudBundleIDs: Set(fetchedBundles.map(\.id)))
            replayPendingMutationsInBackground()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func loadFromCache() -> [CachedShoppingBundle] {
        guard let context = modelContext, let householdId else { return [] }

        let descriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )

        if let cachedBundles = try? context.fetch(descriptor) {
            bundles = cachedBundles
                .filter { $0.syncStatusRaw != BundleSyncStatus.pendingDelete }
                .map { $0.toShoppingBundle() }
            return cachedBundles
        }

        return []
    }

    private func syncToCache(_ bundles: [ShoppingBundle], cloudBundleIDs: Set<UUID>) {
        guard let context = modelContext, let householdId else { return }

        let descriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedBundles = (try? context.fetch(descriptor)) ?? []
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedBundles.map { ($0.id, $0) })

        for bundle in bundles {
            if let existing = cachedByID[bundle.id] {
                if existing.syncStatusRaw == BundleSyncStatus.pendingUpload ||
                    existing.syncStatusRaw == BundleSyncStatus.pendingDelete
                {
                    continue
                }
                if existing.syncStatusRaw == BundleSyncStatus.awaitingCloudEcho,
                   !cloudBundleIDs.contains(bundle.id)
                {
                    continue
                }
                existing.update(from: bundle)
            } else {
                context.insert(CachedShoppingBundle(from: bundle))
            }
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
                _ = try await cloudKit.saveShoppingBundle(cached.toShoppingBundle())
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
                    householdId: cached.householdId
                )
                context.delete(cached)
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
        icon: String = ShoppingBundle.defaultIcon,
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
            case BundleSyncStatus.pendingDelete:
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
