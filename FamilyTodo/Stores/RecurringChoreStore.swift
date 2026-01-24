import Foundation
import SwiftData

/// Store for recurring chore management
@MainActor
final class RecurringChoreStore: ObservableObject {
    @Published private(set) var chores: [RecurringChore] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private lazy var cloudKit = CloudKitManager.shared
    private let householdId: UUID?
    private var modelContext: ModelContext?

    init(householdId: UUID?, modelContext: ModelContext? = nil) {
        self.householdId = householdId
        self.modelContext = modelContext
    }

    /// Set model context for offline caching
    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    var activeChores: [RecurringChore] {
        chores.filter(\.isActive)
    }

    // MARK: - Load Chores

    func loadChores() async {
        guard let householdId else { return }

        isLoading = true
        error = nil

        // 1. Load from cache first (instant UI)
        loadFromCache()

        // 2. Sync with CloudKit in background
        do {
            let fetchedChores = try await cloudKit.fetchRecurringChores(householdId: householdId)
            chores = fetchedChores

            // 3. Update cache
            syncToCache(fetchedChores)
        } catch {
            // Keep cached data on error
            self.error = error
        }

        isLoading = false
    }

    private func loadFromCache() {
        guard let context = modelContext, let householdId else { return }

        let descriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        if let cachedChores = try? context.fetch(descriptor) {
            chores = cachedChores.map { $0.toRecurringChore() }
        }
    }

    private func syncToCache(_ chores: [RecurringChore]) {
        guard let context = modelContext else { return }

        for chore in chores {
            let descriptor = FetchDescriptor<CachedRecurringChore>(
                predicate: #Predicate { $0.id == chore.id }
            )

            if let existing = try? context.fetch(descriptor).first {
                existing.update(from: chore)
            } else {
                let cached = CachedRecurringChore(from: chore)
                context.insert(cached)
            }
        }

        try? context.save()
    }

    // MARK: - Create Chore

    func createChore(
        title: String,
        recurrenceType: RecurringChore.RecurrenceType,
        recurrenceDay: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        recurrenceInterval: Int? = nil,
        defaultAssigneeIds: [UUID] = [],
        areaId: UUID? = nil,
        notes: String? = nil
    ) async {
        guard let householdId else { return }

        var chore = RecurringChore(
            householdId: householdId,
            title: title,
            recurrenceType: recurrenceType,
            recurrenceDay: recurrenceDay,
            recurrenceDayOfMonth: recurrenceDayOfMonth,
            recurrenceInterval: recurrenceInterval,
            defaultAssigneeIds: defaultAssigneeIds,
            areaId: areaId,
            notes: notes
        )
        chore.nextScheduledDate = chore.calculateNextScheduledDate()

        // Optimistic UI update
        chores.append(chore)

        // Save to cache with pending status
        if let context = modelContext {
            let cached = CachedRecurringChore(from: chore)
            cached.syncStatusRaw = "pendingUpload"
            context.insert(cached)
            try? context.save()
        }

        do {
            _ = try await cloudKit.saveRecurringChore(chore)

            // Mark as synced
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedRecurringChore>(
                    predicate: #Predicate { $0.id == chore.id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    cached.syncStatusRaw = "synced"
                    cached.lastSyncedAt = Date()
                    try? context.save()
                }
            }
        } catch {
            chores.removeAll { $0.id == chore.id }
            // Keep in cache with pending status
            self.error = error
        }
    }

    // MARK: - Update Chore

    func updateChore(_ chore: RecurringChore) async {
        var updatedChore = chore
        updatedChore.updatedAt = Date()

        // Optimistic UI update
        if let index = chores.firstIndex(where: { $0.id == chore.id }) {
            chores[index] = updatedChore
        }

        // Save to cache with pending status
        if let context = modelContext {
            let descriptor = FetchDescriptor<CachedRecurringChore>(
                predicate: #Predicate { $0.id == chore.id }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.update(from: updatedChore)
                cached.syncStatusRaw = "pendingUpload"
                try? context.save()
            }
        }

        do {
            _ = try await cloudKit.saveRecurringChore(updatedChore)

            // Mark as synced
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedRecurringChore>(
                    predicate: #Predicate { $0.id == chore.id }
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
            await loadChores()
        }
    }

    // MARK: - Toggle Active

    func toggleActive(_ chore: RecurringChore) async {
        var updatedChore = chore
        updatedChore.isActive.toggle()
        await updateChore(updatedChore)
    }

    // MARK: - Delete Chore

    func deleteChore(_ chore: RecurringChore) async {
        // Optimistic UI update
        chores.removeAll { $0.id == chore.id }

        // Mark as pending delete in cache
        if let context = modelContext {
            let descriptor = FetchDescriptor<CachedRecurringChore>(
                predicate: #Predicate { $0.id == chore.id }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.syncStatusRaw = "pendingDelete"
                try? context.save()
            }
        }

        do {
            try await cloudKit.deleteRecurringChore(id: chore.id)

            // Remove from cache
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedRecurringChore>(
                    predicate: #Predicate { $0.id == chore.id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    context.delete(cached)
                    try? context.save()
                }
            }
        } catch {
            self.error = error
            // Keep in cache with pending status, reload UI
            await loadChores()
        }
    }

    // MARK: - Generate Task from Chore

    func generateTask(from chore: RecurringChore, taskStore: TaskStore) async {
        guard let householdId else { return }

        // Create task from chore
        await taskStore.createTask(
            title: chore.title,
            status: .next,
            assigneeId: chore.defaultAssigneeIds.first,
            assigneeIds: chore.defaultAssigneeIds,
            areaId: chore.areaId,
            dueDate: chore.nextScheduledDate,
            notes: chore.notes
        )

        // Update chore with new dates
        var updatedChore = chore
        updatedChore.lastGeneratedDate = Date()
        updatedChore.nextScheduledDate = updatedChore.calculateNextScheduledDate()
        await updateChore(updatedChore)
    }
}
