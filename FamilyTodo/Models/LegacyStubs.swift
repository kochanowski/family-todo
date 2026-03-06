// swiftlint:disable file_length
import Foundation
import SwiftData
import SwiftUI

// MARK: - Legacy Stubs

// These types existed in the old implementation but are being refactored.
// Stubs allow existing code to compile while we migrate to new architecture.

// MARK: - Models

struct Area: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var name: String
    var icon: String?
    var colorHex: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    static var defaults: [Area] {
        [
            Area(name: "Kitchen", icon: "refrigerator", colorHex: "#FF5733"),
            Area(name: "Living Room", icon: "sofa", colorHex: "#33FF57"),
            Area(name: "Bathroom", icon: "shower", colorHex: "#3357FF"),
        ]
    }

    static func defaults(for householdId: UUID) -> [Area] {
        [
            Area(householdId: householdId, name: "Kitchen", icon: "refrigerator", colorHex: "#FF5733", sortOrder: 0),
            Area(householdId: householdId, name: "Living Room", icon: "sofa", colorHex: "#33FF57", sortOrder: 1),
            Area(householdId: householdId, name: "Bathroom", icon: "shower", colorHex: "#3357FF", sortOrder: 2),
            Area(householdId: householdId, name: "Bedroom", icon: "bed.double", colorHex: "#FF33A1", sortOrder: 3),
            Area(householdId: householdId, name: "Garden", icon: "leaf", colorHex: "#A1FF33", sortOrder: 4),
            Area(householdId: householdId, name: "Other", icon: "folder", colorHex: "#808080", sortOrder: 5),
        ]
    }

    init(
        id: UUID = UUID(),
        householdId: UUID = UUID(),
        name: String = "",
        icon: String? = "folder",
        colorHex: String = "#808080",
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct RecurringChore: Identifiable, Codable {
    enum RecurrenceType: String, Codable, CaseIterable {
        case daily
        case weekly
        case monthly
        case custom
    }

    let id: UUID
    let householdId: UUID
    var title: String
    var recurrenceType: RecurrenceType
    var recurrenceDay: Int?
    var recurrenceDayOfMonth: Int?
    var recurrenceInterval: Int?
    var defaultAssigneeIds: [UUID]
    var areaId: UUID?
    var categoryId: UUID?
    var isActive: Bool
    var lastGeneratedDate: Date?
    var nextScheduledDate: Date?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date
    // Legacy fields kept for compatibility with older snapshots.
    var frequencyDays: Int
    var assigneeIds: [UUID]
    var rotationEnabled: Bool
    var nextAssigneeIndex: Int

    init(
        id: UUID = UUID(),
        householdId: UUID = UUID(),
        title: String = "",
        recurrenceType: RecurrenceType = .weekly,
        recurrenceDay: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        recurrenceInterval: Int? = 1,
        defaultAssigneeIds: [UUID] = [],
        areaId: UUID? = nil,
        categoryId: UUID? = nil,
        isActive: Bool = true,
        lastGeneratedDate: Date? = nil,
        nextScheduledDate: Date? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        // Defaults for compatibility fields
        frequencyDays: Int = 7,
        assigneeIds: [UUID] = [],
        rotationEnabled: Bool = false,
        nextAssigneeIndex: Int = 0
    ) {
        let dedupedDefaultAssigneeIds = Self.uniqueAssigneeIDs(
            defaultAssigneeIds.isEmpty ? assigneeIds : defaultAssigneeIds
        )
        let dedupedLegacyAssigneeIds = Self.uniqueAssigneeIDs(
            assigneeIds.isEmpty ? dedupedDefaultAssigneeIds : assigneeIds
        )
        self.id = id
        self.householdId = householdId
        self.title = title
        self.recurrenceType = recurrenceType
        self.recurrenceDay = recurrenceDay
        self.recurrenceDayOfMonth = recurrenceDayOfMonth
        self.recurrenceInterval = recurrenceInterval
        self.defaultAssigneeIds = dedupedDefaultAssigneeIds
        self.areaId = areaId
        self.categoryId = categoryId
        self.isActive = isActive
        self.lastGeneratedDate = lastGeneratedDate
        self.nextScheduledDate = nextScheduledDate
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.frequencyDays = max(frequencyDays, 1)
        self.assigneeIds = dedupedLegacyAssigneeIds
        self.rotationEnabled = rotationEnabled
        self.nextAssigneeIndex = max(nextAssigneeIndex, 0)
    }

    var normalizedAssigneeIDs: [UUID] {
        let source = defaultAssigneeIds.isEmpty ? assigneeIds : defaultAssigneeIds
        return Self.uniqueAssigneeIDs(source)
    }

    func normalizedRotationCursor() -> Int {
        let count = normalizedAssigneeIDs.count
        guard count > 0 else { return 0 }
        return min(max(nextAssigneeIndex, 0), count - 1)
    }

    private static func uniqueAssigneeIDs(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}

// MARK: - CardKind for ThemeStore

enum CardKind: String, CaseIterable, Codable {
    case shoppingList
    case todo
    case backlog
    case recurring
    case household
    case areas
    case settings
}

// MARK: - Stub Views

struct TaskDetailView: View {
    let store: TaskStore
    let householdId: UUID
    let task: Task?
    let areas: [Area]

    init(
        store: TaskStore,
        householdId: UUID,
        task: Task? = nil,
        areas: [Area] = []
    ) {
        self.store = store
        self.householdId = householdId
        self.task = task
        self.areas = areas
    }

    var body: some View {
        Text("Task Detail - Coming Soon")
            .font(.headline)
    }
}

// MARK: - Stores

enum HouseholdError: Error, Equatable {
    case memberNotFound
    case householdNotFound
    case cloudSyncRequired
    case invalidInviteCode
    case displayNameAlreadyTaken
    case cacheNotAvailable
    case notAuthorized
    case transferOwnershipRequired
}

extension HouseholdError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .memberNotFound:
            "Member not found."
        case .householdNotFound:
            "Household not found."
        case .cloudSyncRequired:
            "This action requires cloud sync."
        case .invalidInviteCode:
            "The invite code is invalid."
        case .displayNameAlreadyTaken:
            "This display name is already used in the household."
        case .cacheNotAvailable:
            "Local cache is unavailable."
        case .notAuthorized:
            "You are not allowed to perform this action."
        case .transferOwnershipRequired:
            "Transfer ownership before leaving the household."
        }
    }
}

@MainActor
class AreaStore: ObservableObject {
    @Published var areas: [Area] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let householdId: UUID?
    private var modelContext: ModelContext?
    private var syncMode: SyncMode = .cloud
    private lazy var cloudKit = CloudKitManager.shared

    init(householdId: UUID? = nil, modelContext: ModelContext? = nil) {
        self.householdId = householdId
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
    }

    private var isCloudSyncEnabled: Bool {
        syncMode == .cloud
    }

    func loadAreas(householdId: UUID? = nil) async {
        let resolvedHouseholdId = householdId ?? self.householdId
        guard let resolvedHouseholdId else { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        loadFromCache(householdId: resolvedHouseholdId)
        guard isCloudSyncEnabled else { return }

        do {
            await cloudKit.ensureReady()
            let fetched = try await cloudKit.fetchAreas(householdId: resolvedHouseholdId)
            areas = fetched
            syncToCache(fetched)
        } catch {
            self.error = error
        }
    }

    func addArea(name: String, icon: String? = nil, colorHex: String = "#808080") async {
        guard let householdId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let area = Area(
            householdId: householdId,
            name: trimmed,
            icon: icon,
            colorHex: colorHex,
            sortOrder: areas.count
        )
        areas.append(area)
        upsertCachedArea(area)

        guard isCloudSyncEnabled else { return }
        do {
            _ = try await cloudKit.saveArea(area)
        } catch {
            self.error = error
        }
    }

    func deleteArea(_ area: Area) async {
        areas.removeAll { $0.id == area.id }
        deleteCachedArea(id: area.id)

        guard isCloudSyncEnabled else { return }
        do {
            try await cloudKit.deleteArea(id: area.id)
        } catch {
            self.error = error
        }
    }

    private func loadFromCache(householdId: UUID) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<CachedArea>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        if let cached = try? modelContext.fetch(descriptor) {
            areas = cached.map { $0.toArea() }
        }
    }

    private func syncToCache(_ areas: [Area]) {
        for area in areas {
            upsertCachedArea(area)
        }
    }

    private func upsertCachedArea(_ area: Area) {
        guard let modelContext else { return }
        let areaId = area.id
        let descriptor = FetchDescriptor<CachedArea>(
            predicate: #Predicate { $0.id == areaId }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.update(from: area)
        } else {
            modelContext.insert(CachedArea(from: area))
        }
        try? modelContext.save()
    }

    private func deleteCachedArea(id: UUID) {
        guard let modelContext else { return }
        let areaId = id
        let descriptor = FetchDescriptor<CachedArea>(
            predicate: #Predicate { $0.id == areaId }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            modelContext.delete(cached)
            try? modelContext.save()
        }
    }
}

@MainActor
class NotificationSettingsStore: ObservableObject {
    @AppStorage("notifications.enabled") var isEnabled = true
    @AppStorage("notifications.taskReminders") var taskRemindersEnabled = true
    @AppStorage("notifications.dailyDigest") var dailyDigestEnabled = true
    @AppStorage("notifications.sound") var soundEnabled = true
    @AppStorage("notifications.reminderHour") private var reminderHour = 8
    @AppStorage("notifications.reminderMinute") private var reminderMinute = 0

    var reminderTime: Date {
        get {
            let components = DateComponents(hour: reminderHour, minute: reminderMinute)
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = components.hour ?? 8
            reminderMinute = components.minute ?? 0
        }
    }
}

@MainActor
final class RecurringChoreStore: ObservableObject {
    private struct PendingSyncSnapshot {
        var pendingUploadByID: [UUID: RecurringChore]
        var pendingDeleteIDs: Set<UUID>
    }

    @Published private(set) var chores: [RecurringChore] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let householdId: UUID?
    private var modelContext: ModelContext?
    private var syncMode: SyncMode = .cloud
    private lazy var cloudKit = CloudKitManager.shared
    private var pendingMutationIDs: Set<UUID> = []
    private var mutationIDsDuringCurrentLoad: Set<UUID> = []
    private var isReplayingPendingMutations = false
    private var needsReloadAfterCurrentLoad = false

    init(householdId: UUID?, modelContext: ModelContext? = nil) {
        self.householdId = householdId
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
    }

    private var isCloudSyncEnabled: Bool {
        syncMode == .cloud
    }

    @discardableResult
    private func saveContextOrSetError(
        operation: String = "persist recurring chore cache",
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        StoreContextSaver.saveContextOrSetError(
            modelContext,
            store: "RecurringChoreStore",
            operation: operation,
            file: file,
            line: line
        ) { [self] saveError in
            error = saveError
        }
    }

    func loadChores() async {
        guard let householdId else { return }
        guard !isLoading else {
            needsReloadAfterCurrentLoad = true
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        _ = loadFromCache(householdId: householdId)
        guard isCloudSyncEnabled else { return }

        do {
            await cloudKit.ensureReady()
            let fetched = try await cloudKit.fetchRecurringChores(householdId: householdId)
            let latestPendingSnapshot = pendingSyncSnapshot(from: fetchCachedChoresForCurrentHousehold())
            let locallyMutatedIDs = mutationIDsDuringCurrentLoad
            chores = mergeCloudSnapshot(
                fetched,
                with: latestPendingSnapshot,
                locallyMutatedIDs: locallyMutatedIDs
            )
            mutationIDsDuringCurrentLoad = []
            syncToCache(fetched)
            replayPendingMutationsInBackground()
        } catch {
            self.error = error
        }

        if needsReloadAfterCurrentLoad {
            needsReloadAfterCurrentLoad = false
            await loadChores()
        }
    }

    func addChore(
        title: String,
        recurrenceType: RecurringChore.RecurrenceType,
        recurrenceInterval: Int? = 1,
        recurrenceDay: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        defaultAssigneeIds: [UUID] = [],
        rotationEnabled: Bool = false,
        categoryId: UUID
    ) async {
        guard let householdId else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var seenAssigneeIDs = Set<UUID>()
        let normalizedAssigneeIDs = defaultAssigneeIds.filter { seenAssigneeIDs.insert($0).inserted }
        let resolvedRotationEnabled = rotationEnabled && normalizedAssigneeIDs.count > 1

        var chore = RecurringChore(
            householdId: householdId,
            title: trimmed,
            recurrenceType: recurrenceType,
            recurrenceDay: recurrenceDay,
            recurrenceDayOfMonth: recurrenceDayOfMonth,
            recurrenceInterval: recurrenceInterval,
            defaultAssigneeIds: normalizedAssigneeIDs,
            categoryId: categoryId,
            frequencyDays: max(recurrenceInterval ?? 1, 1),
            rotationEnabled: resolvedRotationEnabled
        )
        chore.nextScheduledDate = ChoreScheduler.nextScheduledDate(for: chore, from: Date())

        beginMutation(chore.id)
        defer { endMutation(chore.id) }

        chores.append(chore)
        upsertCachedChore(
            chore,
            syncStatus: isCloudSyncEnabled ? .pendingUpload : .synced
        )

        if let generatedChore = await seedInitialBacklogTaskIfNeeded(
            for: chore,
            deferCloudSync: isCloudSyncEnabled
        ) {
            chore = generatedChore
        }

        broadcastRecurringChoresDidChange()

        guard isCloudSyncEnabled else { return }
        await persistChoreUpload(chore)
    }

    func updateChore(_ chore: RecurringChore, reconcilePendingBacklog: Bool = true) async {
        var normalizedChore = chore
        let normalizedAssigneeIDs = normalizedChore.normalizedAssigneeIDs
        normalizedChore.defaultAssigneeIds = normalizedAssigneeIDs
        normalizedChore.assigneeIds = normalizedAssigneeIDs

        if normalizedAssigneeIDs.count < 2 {
            normalizedChore.rotationEnabled = false
        }
        if normalizedAssigneeIDs.isEmpty {
            normalizedChore.nextAssigneeIndex = 0
        } else {
            normalizedChore.nextAssigneeIndex = min(
                max(normalizedChore.nextAssigneeIndex, 0),
                normalizedAssigneeIDs.count - 1
            )
        }
        normalizedChore.frequencyDays = max(normalizedChore.recurrenceInterval ?? 1, 1)

        guard let index = chores.firstIndex(where: { $0.id == normalizedChore.id }) else { return }

        beginMutation(normalizedChore.id)
        defer { endMutation(normalizedChore.id) }

        let previous = chores[index]
        chores[index] = normalizedChore
        upsertCachedChore(
            normalizedChore,
            syncStatus: isCloudSyncEnabled ? .pendingUpload : .synced
        )

        if reconcilePendingBacklog {
            if previous.isActive, !normalizedChore.isActive {
                await deletePendingBacklogInstances(
                    for: normalizedChore,
                    deferCloudSync: isCloudSyncEnabled
                )
            } else if !previous.isActive,
                      normalizedChore.isActive,
                      let seeded = await seedInitialBacklogTaskIfNeeded(
                          for: normalizedChore,
                          deferCloudSync: isCloudSyncEnabled
                      )
            {
                normalizedChore = seeded
            } else if normalizedChore.isActive {
                await syncPendingBacklogInstances(
                    with: normalizedChore,
                    deferCloudSync: isCloudSyncEnabled
                )
            }
        }

        broadcastRecurringChoresDidChange()

        guard isCloudSyncEnabled else { return }
        await persistChoreUpload(normalizedChore)
    }

    func deleteChore(_ chore: RecurringChore) async {
        beginMutation(chore.id)
        defer { endMutation(chore.id) }

        chores.removeAll { $0.id == chore.id }
        if isCloudSyncEnabled {
            markCachedChorePendingDelete(chore)
        } else {
            deleteCachedChore(id: chore.id)
        }
        await deletePendingBacklogInstances(for: chore, deferCloudSync: isCloudSyncEnabled)
        broadcastRecurringChoresDidChange()
        NotificationCenter.default.post(name: .taskBoardDataDidChange, object: nil)

        guard isCloudSyncEnabled else { return }
        await persistChoreDelete(chore)
    }

    func markGenerated(
        _ chore: RecurringChore,
        generatedDueDate: Date,
        at date: Date,
        nextAssigneeIndex: Int? = nil
    ) async {
        var updated = chore
        updated.lastGeneratedDate = date
        updated.nextScheduledDate = ChoreScheduler.nextScheduledDate(for: updated, from: generatedDueDate)
            ?? generatedDueDate
        if let nextAssigneeIndex {
            let count = updated.normalizedAssigneeIDs.count
            if count > 0 {
                updated.nextAssigneeIndex = min(max(nextAssigneeIndex, 0), count - 1)
            } else {
                updated.nextAssigneeIndex = 0
            }
        }
        updated.updatedAt = Date()
        await updateChore(updated, reconcilePendingBacklog: false)
    }

    private func loadFromCache(householdId: UUID) -> [CachedRecurringChore] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let cached = (try? modelContext.fetch(descriptor)) ?? []
        chores = cached
            .filter { $0.syncStatusRaw != RecurringChoreSyncStatus.pendingDelete.rawValue }
            .map { $0.toRecurringChore() }
        return cached
    }

    private func mergeCloudSnapshot(
        _ cloudChores: [RecurringChore],
        with pendingSnapshot: PendingSyncSnapshot,
        locallyMutatedIDs: Set<UUID>
    ) -> [RecurringChore] {
        var mergedByID = Dictionary(uniqueKeysWithValues: cloudChores.map { ($0.id, $0) })
        let localByID = Dictionary(uniqueKeysWithValues: chores.map { ($0.id, $0) })

        for (id, pendingChore) in pendingSnapshot.pendingUploadByID {
            if let cloudChore = mergedByID[id], cloudChore.updatedAt > pendingChore.updatedAt {
                continue
            }
            mergedByID[id] = pendingChore
        }

        for id in pendingSnapshot.pendingDeleteIDs {
            mergedByID.removeValue(forKey: id)
        }

        for id in locallyMutatedIDs.union(pendingMutationIDs) {
            if let localChore = localByID[id] {
                mergedByID[id] = localChore
            } else {
                mergedByID.removeValue(forKey: id)
            }
        }

        return mergedByID
            .values
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private func pendingSyncSnapshot(
        from cachedChores: [CachedRecurringChore]
    ) -> PendingSyncSnapshot {
        var pendingUploadByID: [UUID: RecurringChore] = [:]
        var pendingDeleteIDs = Set<UUID>()

        for cached in cachedChores {
            switch cached.syncStatusRaw {
            case RecurringChoreSyncStatus.pendingUpload.rawValue:
                pendingUploadByID[cached.id] = cached.toRecurringChore()
            case RecurringChoreSyncStatus.pendingDelete.rawValue:
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

    private func replayPendingMutationsInBackground() {
        guard !isReplayingPendingMutations else { return }
        isReplayingPendingMutations = true

        _ = _Concurrency.Task(priority: .utility) { [self] in
            await flushPendingSync()
            isReplayingPendingMutations = false
        }
    }

    private func flushPendingSync() async {
        guard isCloudSyncEnabled, householdId != nil else { return }

        let cachedChores = fetchCachedChoresForCurrentHousehold()
        let pendingUploads = cachedChores.filter {
            $0.syncStatusRaw == RecurringChoreSyncStatus.pendingUpload.rawValue
        }
        let pendingDeletes = cachedChores.filter {
            $0.syncStatusRaw == RecurringChoreSyncStatus.pendingDelete.rawValue
        }

        guard !pendingUploads.isEmpty || !pendingDeletes.isEmpty else { return }

        var didMutateCache = false

        for cached in pendingUploads where !pendingMutationIDs.contains(cached.id) {
            do {
                await cloudKit.ensureReady()
                _ = try await cloudKit.saveRecurringChore(cached.toRecurringChore())
                cached.syncStatusRaw = RecurringChoreSyncStatus.synced.rawValue
                cached.lastSyncedAt = Date()
                didMutateCache = true
                await replayPendingTaskMutations()
            } catch {
                self.error = error
            }
        }

        for cached in pendingDeletes where !pendingMutationIDs.contains(cached.id) {
            do {
                await cloudKit.ensureReady()
                try await cloudKit.deleteRecurringChore(id: cached.id, householdId: cached.householdId)
                modelContext?.delete(cached)
                didMutateCache = true
                await replayPendingTaskMutations()
            } catch {
                self.error = error
            }
        }

        if didMutateCache {
            _ = saveContextOrSetError(operation: "flush pending recurring chore sync")
        }
    }

    private func seedInitialBacklogTaskIfNeeded(
        for chore: RecurringChore,
        deferCloudSync: Bool
    ) async -> RecurringChore? {
        guard chore.isActive else { return nil }
        guard let modelContext else { return nil }

        let generatedDueDate = chore.nextScheduledDate
            ?? ChoreScheduler.nextScheduledDate(for: chore, from: Date())
            ?? Date()

        guard !hasGeneratedTask(for: chore.id, dueDate: generatedDueDate) else {
            return nil
        }

        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(chore.householdId)
        taskStore.setSyncMode(syncMode)
        await taskStore.loadTasks()

        if taskStore.tasks.contains(where: { task in
            task.recurringChoreId == chore.id &&
                task.dueDate.map { Calendar.current.isDate($0, inSameDayAs: generatedDueDate) } == true
        }) {
            return nil
        }

        let assignment = resolveAssignment(for: chore)
        let creationResult = await taskStore.createTask(
            title: chore.title,
            status: .backlog,
            assigneeId: assignment.assigneeId,
            assigneeIds: chore.normalizedAssigneeIDs,
            backlogCategoryId: chore.categoryId,
            areaId: chore.areaId,
            dueDate: generatedDueDate,
            notes: chore.notes,
            taskType: .recurring,
            recurringChoreId: chore.id,
            deferCloudSync: deferCloudSync
        )
        guard creationResult == .ok else {
            if let storeError = taskStore.error {
                error = storeError
            }
            return nil
        }

        var generatedChore = chore
        generatedChore.lastGeneratedDate = Date()
        generatedChore.nextScheduledDate =
            ChoreScheduler.nextScheduledDate(for: generatedChore, from: generatedDueDate)
                ?? generatedDueDate
        generatedChore.nextAssigneeIndex = assignment.nextAssigneeIndex
        generatedChore.updatedAt = Date()

        if let index = chores.firstIndex(where: { $0.id == generatedChore.id }) {
            chores[index] = generatedChore
        }
        upsertCachedChore(
            generatedChore,
            syncStatus: isCloudSyncEnabled ? .pendingUpload : .synced
        )
        NotificationCenter.default.post(name: .taskBoardDataDidChange, object: nil)
        return generatedChore
    }

    private func hasGeneratedTask(for recurringChoreId: UUID, dueDate: Date) -> Bool {
        guard let householdId else { return false }
        guard let modelContext else { return false }

        let targetHouseholdId = householdId
        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate {
                $0.householdId == targetHouseholdId
            }
        )
        let calendar = Calendar.current
        let cachedTasks = (try? modelContext.fetch(descriptor)) ?? []
        return cachedTasks.contains { cachedTask in
            guard cachedTask.syncStatusRaw != "pendingDelete" else { return false }
            guard cachedTask.recurringChoreId == recurringChoreId else { return false }
            return cachedTask.dueDate.map { calendar.isDate($0, inSameDayAs: dueDate) } == true
        }
    }

    private func resolveAssignment(
        for chore: RecurringChore
    ) -> (assigneeId: UUID?, nextAssigneeIndex: Int) {
        let assigneeIds = chore.normalizedAssigneeIDs
        guard !assigneeIds.isEmpty else {
            return (nil, 0)
        }

        guard chore.rotationEnabled, assigneeIds.count > 1 else {
            return (assigneeIds.first, 0)
        }

        let currentIndex = chore.normalizedRotationCursor()
        let assigneeId = assigneeIds[currentIndex]
        let nextIndex = (currentIndex + 1) % assigneeIds.count
        return (assigneeId, nextIndex)
    }

    private func syncToCache(_ chores: [RecurringChore]) {
        guard let modelContext, let householdId else { return }
        let descriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedChores = (try? modelContext.fetch(descriptor)) ?? []
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedChores.map { ($0.id, $0) })
        let cloudIDs = Set(chores.map(\.id))

        for chore in chores {
            if let existing = cachedByID[chore.id] {
                if existing.syncStatusRaw == RecurringChoreSyncStatus.pendingUpload.rawValue ||
                    existing.syncStatusRaw == RecurringChoreSyncStatus.pendingDelete.rawValue
                {
                    continue
                }
                existing.update(from: chore)
                existing.syncStatusRaw = RecurringChoreSyncStatus.synced.rawValue
                existing.lastSyncedAt = Date()
            } else {
                let cached = CachedRecurringChore(from: chore)
                cached.syncStatusRaw = RecurringChoreSyncStatus.synced.rawValue
                cached.lastSyncedAt = Date()
                modelContext.insert(cached)
            }
        }

        for cached in cachedChores where
            cached.syncStatusRaw == RecurringChoreSyncStatus.synced.rawValue &&
            !cloudIDs.contains(cached.id)
        {
            modelContext.delete(cached)
        }

        _ = saveContextOrSetError(operation: "sync recurring chore cache from cloud")
    }

    private func upsertCachedChore(
        _ chore: RecurringChore,
        syncStatus: RecurringChoreSyncStatus
    ) {
        guard let modelContext else { return }
        let choreId = chore.id
        let descriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.id == choreId }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.update(from: chore)
            cached.syncStatusRaw = syncStatus.rawValue
            cached.lastSyncedAt = syncStatus == .synced ? Date() : nil
        } else {
            let cached = CachedRecurringChore(from: chore)
            cached.syncStatusRaw = syncStatus.rawValue
            cached.lastSyncedAt = syncStatus == .synced ? Date() : nil
            modelContext.insert(cached)
        }
        _ = saveContextOrSetError(operation: "upsert recurring chore cache")
    }

    private func markCachedChoreSynced(id: UUID) {
        guard let modelContext else { return }
        let choreId = id
        let descriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.id == choreId }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.syncStatusRaw = RecurringChoreSyncStatus.synced.rawValue
            cached.lastSyncedAt = Date()
            _ = saveContextOrSetError(operation: "mark recurring chore as synced")
        }
    }

    private func markCachedChorePendingDelete(_ chore: RecurringChore) {
        guard let modelContext else { return }
        let choreId = chore.id
        let descriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.id == choreId }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.update(from: chore)
            cached.syncStatusRaw = RecurringChoreSyncStatus.pendingDelete.rawValue
            cached.lastSyncedAt = nil
        } else {
            let cached = CachedRecurringChore(from: chore)
            cached.syncStatusRaw = RecurringChoreSyncStatus.pendingDelete.rawValue
            cached.lastSyncedAt = nil
            modelContext.insert(cached)
        }
        _ = saveContextOrSetError(operation: "mark recurring chore pending delete")
    }

    private func deleteCachedChore(id: UUID) {
        guard let modelContext else { return }
        let choreId = id
        let descriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.id == choreId }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            modelContext.delete(cached)
            _ = saveContextOrSetError(operation: "delete recurring chore cache")
        }
    }

    private func deletePendingBacklogInstances(
        for chore: RecurringChore,
        deferCloudSync: Bool
    ) async {
        guard let modelContext else { return }
        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(chore.householdId)
        taskStore.setSyncMode(syncMode)
        await taskStore.loadTasks()

        let pendingBacklogInstances = taskStore.backlogTasks.filter { task in
            task.taskType == .recurring && task.recurringChoreId == chore.id
        }
        for task in pendingBacklogInstances {
            await taskStore.deleteTask(task, deferCloudSync: deferCloudSync)
        }
    }

    private func syncPendingBacklogInstances(
        with chore: RecurringChore,
        deferCloudSync: Bool
    ) async {
        guard let modelContext else { return }
        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(chore.householdId)
        taskStore.setSyncMode(syncMode)
        await taskStore.loadTasks()

        let assignment = resolveAssignment(for: chore)
        let pendingBacklogInstances = taskStore.backlogTasks.filter { task in
            task.taskType == .recurring && task.recurringChoreId == chore.id
        }

        for task in pendingBacklogInstances {
            var updatedTask = task
            updatedTask.title = chore.title
            updatedTask.assigneeIds = chore.normalizedAssigneeIDs
            updatedTask.assigneeId = resolvedAssigneeID(
                for: task,
                fallback: assignment.assigneeId,
                chore: chore
            )
            updatedTask.backlogCategoryId = chore.categoryId
            updatedTask.areaId = chore.areaId
            updatedTask.notes = chore.notes
            updatedTask.dueDate = rescheduledDueDate(for: task, using: chore)
            _ = await taskStore.updateTask(updatedTask, deferCloudSync: deferCloudSync)
        }

        if !pendingBacklogInstances.isEmpty {
            NotificationCenter.default.post(name: .taskBoardDataDidChange, object: nil)
        }
    }

    private func rescheduledDueDate(for task: Task, using chore: RecurringChore) -> Date? {
        guard let dueDate = task.dueDate else { return nil }
        let anchor = Calendar.current.date(byAdding: .day, value: -1, to: dueDate) ?? dueDate
        return ChoreScheduler.nextScheduledDate(for: chore, from: anchor) ?? dueDate
    }

    private func resolvedAssigneeID(
        for task: Task,
        fallback: UUID?,
        chore: RecurringChore
    ) -> UUID? {
        if let assigneeId = task.assigneeId,
           chore.normalizedAssigneeIDs.contains(assigneeId)
        {
            return assigneeId
        }

        return fallback
    }

    private func fetchCachedChoresForCurrentHousehold() -> [CachedRecurringChore] {
        guard let modelContext else { return [] }

        if let householdId {
            let descriptor = FetchDescriptor<CachedRecurringChore>(
                predicate: #Predicate { $0.householdId == householdId }
            )
            return (try? modelContext.fetch(descriptor)) ?? []
        }

        let descriptor = FetchDescriptor<CachedRecurringChore>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func beginMutation(_ id: UUID) {
        pendingMutationIDs.insert(id)
        if isLoading {
            mutationIDsDuringCurrentLoad.insert(id)
        }
    }

    private func endMutation(_ id: UUID) {
        pendingMutationIDs.remove(id)
    }

    private func persistChoreUpload(_ chore: RecurringChore) async {
        do {
            await cloudKit.ensureReady()
            _ = try await cloudKit.saveRecurringChore(chore)
            markCachedChoreSynced(id: chore.id)
            await replayPendingTaskMutations()
        } catch {
            self.error = error
        }
    }

    private func persistChoreDelete(_ chore: RecurringChore) async {
        do {
            await cloudKit.ensureReady()
            try await cloudKit.deleteRecurringChore(id: chore.id, householdId: chore.householdId)
            deleteCachedChore(id: chore.id)
            await replayPendingTaskMutations()
        } catch {
            self.error = error
        }
    }

    private func replayPendingTaskMutations() async {
        guard let modelContext, let householdId else { return }
        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(householdId)
        taskStore.setSyncMode(syncMode)
        taskStore.replayPendingMutationsIfNeeded()
    }

    private func broadcastRecurringChoresDidChange() {
        NotificationCenter.default.post(name: .recurringChoresDidChange, object: nil)
    }
}

@MainActor
final class ChoreScheduler {
    static let shared = ChoreScheduler()

    func runIfNeeded(
        householdId: UUID?,
        modelContext: ModelContext,
        syncMode: SyncMode
    ) async {
        guard let householdId else { return }

        let recurringStore = RecurringChoreStore(householdId: householdId, modelContext: modelContext)
        recurringStore.setSyncMode(syncMode)
        await recurringStore.loadChores()

        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(householdId)
        taskStore.setSyncMode(syncMode)
        await taskStore.loadTasks()

        let now = Date()
        for chore in recurringStore.chores where chore.isActive {
            guard let nextDate = chore.nextScheduledDate ?? Self.nextScheduledDate(for: chore, from: now) else {
                continue
            }
            if nextDate <= now {
                if Self.hasGeneratedTask(for: chore, dueDate: nextDate, tasks: taskStore.tasks) {
                    await recurringStore.markGenerated(
                        chore,
                        generatedDueDate: nextDate,
                        at: now
                    )
                    continue
                }

                let assignment = Self.resolveAssignment(for: chore)
                await taskStore.createTask(
                    title: chore.title,
                    status: .backlog,
                    assigneeId: assignment.assigneeId,
                    assigneeIds: chore.normalizedAssigneeIDs,
                    backlogCategoryId: chore.categoryId,
                    areaId: chore.areaId,
                    dueDate: nextDate,
                    notes: chore.notes,
                    taskType: .recurring,
                    recurringChoreId: chore.id,
                    deferCloudSync: syncMode == .cloud
                )
                await recurringStore.markGenerated(
                    chore,
                    generatedDueDate: nextDate,
                    at: now,
                    nextAssigneeIndex: assignment.nextAssigneeIndex
                )
            }
        }
    }

    private static func hasGeneratedTask(for chore: RecurringChore, dueDate: Date, tasks: [Task]) -> Bool {
        let calendar = Calendar.current
        return tasks.contains { task in
            task.recurringChoreId == chore.id &&
                task.dueDate.map { calendar.isDate($0, inSameDayAs: dueDate) } == true
        }
    }

    private static func resolveAssignment(
        for chore: RecurringChore
    ) -> (assigneeId: UUID?, nextAssigneeIndex: Int) {
        let assigneeIds = chore.normalizedAssigneeIDs
        guard !assigneeIds.isEmpty else {
            return (nil, 0)
        }

        guard chore.rotationEnabled, assigneeIds.count > 1 else {
            return (assigneeIds.first, 0)
        }

        let currentIndex = chore.normalizedRotationCursor()
        let assigneeId = assigneeIds[currentIndex]
        let nextIndex = (currentIndex + 1) % assigneeIds.count
        return (assigneeId, nextIndex)
    }

    static func nextScheduledDate(for chore: RecurringChore, from baseDate: Date) -> Date? {
        let calendar = Calendar.current
        let interval = max(chore.recurrenceInterval ?? 1, 1)

        switch chore.recurrenceType {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: baseDate)
        case .weekly:
            let targetWeekday = chore.recurrenceDay ?? 2
            let start = calendar.startOfDay(for: baseDate)
            for offset in 0 ... (7 * interval) {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                if calendar.component(.weekday, from: candidate) == targetWeekday {
                    if candidate > start {
                        return candidate
                    }
                }
            }
            return calendar.date(byAdding: .day, value: 7 * interval, to: start)
        case .monthly:
            let day = min(max(chore.recurrenceDayOfMonth ?? 1, 1), 28)
            guard let nextMonth = calendar.date(byAdding: .month, value: interval, to: baseDate) else {
                return nil
            }
            var components = calendar.dateComponents([.year, .month], from: nextMonth)
            components.day = day
            return calendar.date(from: components)
        case .custom:
            return calendar.date(byAdding: .day, value: interval, to: baseDate)
        }
    }
}

// MARK: - Cached Models

enum RecurringChoreSyncStatus: String {
    case synced
    case pendingUpload
    case pendingDelete
}

@Model
final class CachedArea {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID = UUID(),
        name: String = "",
        colorHex: String = "#808080",
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    convenience init(from area: Area) {
        self.init(
            id: area.id,
            householdId: area.householdId,
            name: area.name,
            colorHex: area.colorHex,
            sortOrder: area.sortOrder,
            createdAt: area.createdAt,
            updatedAt: area.updatedAt
        )
    }

    func update(from area: Area) {
        householdId = area.householdId
        name = area.name
        colorHex = area.colorHex
        sortOrder = area.sortOrder
        createdAt = area.createdAt
        updatedAt = area.updatedAt
    }

    func toArea() -> Area {
        Area(
            id: id,
            householdId: householdId,
            name: name,
            icon: nil,
            colorHex: colorHex,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class CachedRecurringChore {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var title: String
    var recurrenceTypeRaw: String
    var recurrenceDay: Int?
    var recurrenceDayOfMonth: Int?
    var recurrenceInterval: Int
    var defaultAssigneeIdsData: Data?
    var areaId: UUID?
    var categoryId: UUID?
    var isActive: Bool
    var lastGeneratedDate: Date?
    var nextScheduledDate: Date?
    var notes: String?
    var rotationEnabled: Bool
    var nextAssigneeIndex: Int
    var frequencyDays: Int
    var createdAt: Date
    var updatedAt: Date
    var syncStatusRaw: String
    var lastSyncedAt: Date?

    init(
        id: UUID = UUID(),
        householdId: UUID = UUID(),
        title: String = "",
        recurrenceTypeRaw: String = RecurringChore.RecurrenceType.custom.rawValue,
        recurrenceDay: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        recurrenceInterval: Int = 1,
        defaultAssigneeIdsData: Data? = nil,
        areaId: UUID? = nil,
        categoryId: UUID? = nil,
        isActive: Bool = true,
        lastGeneratedDate: Date? = nil,
        nextScheduledDate: Date? = nil,
        notes: String? = nil,
        rotationEnabled: Bool = false,
        nextAssigneeIndex: Int = 0,
        frequencyDays: Int = 7,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncStatusRaw: String = RecurringChoreSyncStatus.synced.rawValue,
        lastSyncedAt: Date? = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.title = title
        self.recurrenceTypeRaw = recurrenceTypeRaw
        self.recurrenceDay = recurrenceDay
        self.recurrenceDayOfMonth = recurrenceDayOfMonth
        self.recurrenceInterval = max(recurrenceInterval, 1)
        self.defaultAssigneeIdsData = defaultAssigneeIdsData
        self.areaId = areaId
        self.categoryId = categoryId
        self.isActive = isActive
        self.lastGeneratedDate = lastGeneratedDate
        self.nextScheduledDate = nextScheduledDate
        self.notes = notes
        self.rotationEnabled = rotationEnabled
        self.nextAssigneeIndex = max(nextAssigneeIndex, 0)
        self.frequencyDays = max(frequencyDays, 1)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatusRaw = syncStatusRaw
        self.lastSyncedAt = lastSyncedAt
    }

    convenience init(from chore: RecurringChore) {
        self.init(
            id: chore.id,
            householdId: chore.householdId,
            title: chore.title,
            recurrenceTypeRaw: chore.recurrenceType.rawValue,
            recurrenceDay: chore.recurrenceDay,
            recurrenceDayOfMonth: chore.recurrenceDayOfMonth,
            recurrenceInterval: max(chore.recurrenceInterval ?? 1, 1),
            defaultAssigneeIdsData: Self.encodeAssigneeIds(chore.normalizedAssigneeIDs),
            areaId: chore.areaId,
            categoryId: chore.categoryId,
            isActive: chore.isActive,
            lastGeneratedDate: chore.lastGeneratedDate,
            nextScheduledDate: chore.nextScheduledDate,
            notes: chore.notes,
            rotationEnabled: chore.rotationEnabled,
            nextAssigneeIndex: chore.normalizedRotationCursor(),
            frequencyDays: max(chore.recurrenceInterval ?? 1, 1),
            createdAt: chore.createdAt,
            updatedAt: chore.updatedAt
        )
    }

    func update(from chore: RecurringChore) {
        householdId = chore.householdId
        title = chore.title
        recurrenceTypeRaw = chore.recurrenceType.rawValue
        recurrenceDay = chore.recurrenceDay
        recurrenceDayOfMonth = chore.recurrenceDayOfMonth
        recurrenceInterval = max(chore.recurrenceInterval ?? 1, 1)
        defaultAssigneeIdsData = Self.encodeAssigneeIds(chore.normalizedAssigneeIDs)
        areaId = chore.areaId
        categoryId = chore.categoryId
        isActive = chore.isActive
        lastGeneratedDate = chore.lastGeneratedDate
        nextScheduledDate = chore.nextScheduledDate
        notes = chore.notes
        rotationEnabled = chore.rotationEnabled
        nextAssigneeIndex = chore.normalizedRotationCursor()
        frequencyDays = max(chore.recurrenceInterval ?? 1, 1)
        createdAt = chore.createdAt
        updatedAt = chore.updatedAt
    }

    func toRecurringChore() -> RecurringChore {
        let recurrenceType = RecurringChore.RecurrenceType(rawValue: recurrenceTypeRaw) ?? .custom
        let assigneeIds = Self.decodeAssigneeIds(defaultAssigneeIdsData)
        let clampedCursor: Int = {
            guard !assigneeIds.isEmpty else { return 0 }
            return min(max(nextAssigneeIndex, 0), assigneeIds.count - 1)
        }()

        return RecurringChore(
            id: id,
            householdId: householdId,
            title: title,
            recurrenceType: recurrenceType,
            recurrenceDay: recurrenceDay,
            recurrenceDayOfMonth: recurrenceDayOfMonth,
            recurrenceInterval: max(recurrenceInterval, 1),
            defaultAssigneeIds: assigneeIds,
            areaId: areaId,
            categoryId: categoryId,
            isActive: isActive,
            lastGeneratedDate: lastGeneratedDate,
            nextScheduledDate: nextScheduledDate,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            frequencyDays: max(frequencyDays, 1),
            assigneeIds: assigneeIds,
            rotationEnabled: rotationEnabled,
            nextAssigneeIndex: clampedCursor
        )
    }

    private static func encodeAssigneeIds(_ ids: [UUID]) -> Data? {
        try? JSONEncoder().encode(ids)
    }

    private static func decodeAssigneeIds(_ data: Data?) -> [UUID] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
    }
}

// swiftlint:enable file_length
