import Foundation
import SwiftData

/// Store for area/board management
@MainActor
final class AreaStore: ObservableObject {
    @Published private(set) var areas: [Area] = []
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

    // MARK: - Load Areas

    func loadAreas() async {
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
            let fetchedAreas = try await cloudKit.fetchAreas(householdId: householdId)
            areas = fetchedAreas
            areas.sort { $0.sortOrder < $1.sortOrder }

            // 3. Update cache
            syncToCache(fetchedAreas)
        } catch {
            // Keep cached data on error
            self.error = error
        }

        isLoading = false
    }

    private func loadFromCache() {
        guard let context = modelContext, let householdId else { return }

        let descriptor = FetchDescriptor<CachedArea>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\CachedArea.sortOrder)]
        )

        if let cachedAreas = try? context.fetch(descriptor) {
            areas = cachedAreas.map { $0.toArea() }
        }
    }

    private func syncToCache(_ areas: [Area]) {
        guard let context = modelContext else { return }

        for area in areas {
            let descriptor = FetchDescriptor<CachedArea>(
                predicate: #Predicate { $0.id == area.id }
            )

            if let existing = try? context.fetch(descriptor).first {
                existing.update(from: area)
            } else {
                let cached = CachedArea(from: area)
                context.insert(cached)
            }
        }

        try? context.save()
    }

    // MARK: - Create Area

    func createArea(name: String, icon: String?) async {
        guard let householdId else { return }

        let sortOrder = (areas.map(\.sortOrder).max() ?? -1) + 1

        let area = Area(
            householdId: householdId,
            name: name,
            icon: icon,
            sortOrder: sortOrder
        )

        // Optimistic UI update
        areas.append(area)

        // Save to cache with pending status
        if let context = modelContext {
            let cached = CachedArea(from: area)
            cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
            cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
            context.insert(cached)
            try? context.save()
        }

        if !isCloudSyncEnabled {
            return
        }

        do {
            _ = try await cloudKit.saveArea(area)

            // Mark as synced
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedArea>(
                    predicate: #Predicate { $0.id == area.id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    cached.syncStatusRaw = "synced"
                    cached.lastSyncedAt = Date()
                    try? context.save()
                }
            }
        } catch {
            // Rollback UI
            areas.removeAll { $0.id == area.id }
            // Keep in cache with pending status
            self.error = error
        }
    }

    // MARK: - Update Area

    func updateArea(_ area: Area) async {
        // Optimistic UI update
        if let index = areas.firstIndex(where: { $0.id == area.id }) {
            areas[index] = area
        }

        // Save to cache with pending status
        if let context = modelContext {
            let descriptor = FetchDescriptor<CachedArea>(
                predicate: #Predicate { $0.id == area.id }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.update(from: area)
                cached.syncStatusRaw = isCloudSyncEnabled ? "pendingUpload" : "synced"
                cached.lastSyncedAt = isCloudSyncEnabled ? nil : Date()
                try? context.save()
            }
        }

        if !isCloudSyncEnabled {
            return
        }

        do {
            _ = try await cloudKit.saveArea(area)

            // Mark as synced
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedArea>(
                    predicate: #Predicate { $0.id == area.id }
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
            await loadAreas() // Reload to get correct state
        }
    }

    // MARK: - Delete Area

    func deleteArea(_ area: Area) async {
        // Optimistic UI update
        areas.removeAll { $0.id == area.id }

        // Mark as pending delete in cache
        if let context = modelContext {
            let descriptor = FetchDescriptor<CachedArea>(
                predicate: #Predicate { $0.id == area.id }
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
            try await cloudKit.deleteArea(id: area.id)

            // Remove from cache
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedArea>(
                    predicate: #Predicate { $0.id == area.id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    context.delete(cached)
                    try? context.save()
                }
            }
        } catch {
            self.error = error
            // Keep in cache with pending status, reload UI
            await loadAreas() // Reload to get correct state
        }
    }
}
