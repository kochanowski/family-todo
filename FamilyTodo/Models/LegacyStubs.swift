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
    // Legacy/Unused fields kept for defaults
    var frequencyDays: Int
    var assigneeIds: [UUID]
    var rotationEnabled: Bool

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
        // Defaults for legacy fields
        frequencyDays: Int = 7,
        assigneeIds: [UUID] = [],
        rotationEnabled: Bool = false
    ) {
        self.id = id
        self.householdId = householdId
        self.title = title
        self.recurrenceType = recurrenceType
        self.recurrenceDay = recurrenceDay
        self.recurrenceDayOfMonth = recurrenceDayOfMonth
        self.recurrenceInterval = recurrenceInterval
        self.defaultAssigneeIds = defaultAssigneeIds
        self.areaId = areaId
        self.categoryId = categoryId
        self.isActive = isActive
        self.lastGeneratedDate = lastGeneratedDate
        self.nextScheduledDate = nextScheduledDate
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.frequencyDays = frequencyDays
        self.assigneeIds = assigneeIds
        self.rotationEnabled = rotationEnabled
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
    case alreadyInHousehold
    case displayNameRequired
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
        case .alreadyInHousehold:
            "Leave your current household before creating or joining another one."
        case .displayNameRequired:
            "Set your display name before creating or joining a household."
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
    @Published private(set) var chores: [RecurringChore] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let householdId: UUID?
    private var modelContext: ModelContext?
    private var syncMode: SyncMode = .cloud
    private lazy var cloudKit = CloudKitManager.shared

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

    func loadChores() async {
        guard let householdId else { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        loadFromCache(householdId: householdId)
        guard isCloudSyncEnabled else { return }

        do {
            await cloudKit.ensureReady()
            let fetched = try await cloudKit.fetchRecurringChores(householdId: householdId)
            chores = fetched
            syncToCache(fetched)
        } catch {
            self.error = error
        }
    }

    func addChore(
        title: String,
        recurrenceType: RecurringChore.RecurrenceType,
        recurrenceInterval: Int? = 1,
        recurrenceDay: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        defaultAssigneeIds: [UUID] = [],
        categoryId: UUID? = nil
    ) async {
        guard let householdId else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var chore = RecurringChore(
            householdId: householdId,
            title: trimmed,
            recurrenceType: recurrenceType,
            recurrenceDay: recurrenceDay,
            recurrenceDayOfMonth: recurrenceDayOfMonth,
            recurrenceInterval: recurrenceInterval,
            defaultAssigneeIds: defaultAssigneeIds,
            categoryId: categoryId
        )
        chore.nextScheduledDate = ChoreScheduler.nextScheduledDate(for: chore, from: Date())
        chores.append(chore)
        upsertCachedChore(chore)

        guard isCloudSyncEnabled else { return }
        do {
            _ = try await cloudKit.saveRecurringChore(chore)
        } catch {
            self.error = error
        }
    }

    func updateChore(_ chore: RecurringChore) async {
        guard let index = chores.firstIndex(where: { $0.id == chore.id }) else { return }
        chores[index] = chore
        upsertCachedChore(chore)

        guard isCloudSyncEnabled else { return }
        do {
            _ = try await cloudKit.saveRecurringChore(chore)
        } catch {
            self.error = error
        }
    }

    func deleteChore(_ chore: RecurringChore) async {
        chores.removeAll { $0.id == chore.id }
        deleteCachedChore(id: chore.id)

        guard isCloudSyncEnabled else { return }
        do {
            try await cloudKit.deleteRecurringChore(id: chore.id)
        } catch {
            self.error = error
        }
    }

    func markGenerated(_ chore: RecurringChore, at date: Date) async {
        var updated = chore
        updated.lastGeneratedDate = date
        updated.nextScheduledDate = ChoreScheduler.nextScheduledDate(for: updated, from: date)
        updated.updatedAt = Date()
        await updateChore(updated)
    }

    private func loadFromCache(householdId: UUID) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let cached = try? modelContext.fetch(descriptor) {
            chores = cached.map { $0.toRecurringChore() }
        }
    }

    private func syncToCache(_ chores: [RecurringChore]) {
        for chore in chores {
            upsertCachedChore(chore)
        }
    }

    private func upsertCachedChore(_ chore: RecurringChore) {
        guard let modelContext else { return }
        let choreId = chore.id
        let descriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.id == choreId }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            cached.update(from: chore)
        } else {
            modelContext.insert(CachedRecurringChore(from: chore))
        }
        try? modelContext.save()
    }

    private func deleteCachedChore(id: UUID) {
        guard let modelContext else { return }
        let choreId = id
        let descriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.id == choreId }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            modelContext.delete(cached)
            try? modelContext.save()
        }
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
                    await recurringStore.markGenerated(chore, at: now)
                    continue
                }

                await taskStore.createTask(
                    title: chore.title,
                    status: .backlog,
                    assigneeId: chore.defaultAssigneeIds.first,
                    assigneeIds: chore.defaultAssigneeIds,
                    backlogCategoryId: chore.categoryId,
                    areaId: chore.areaId,
                    dueDate: nextDate,
                    notes: chore.notes,
                    taskType: .recurring,
                    recurringChoreId: chore.id
                )
                await recurringStore.markGenerated(chore, at: now)
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
    var categoryId: UUID?
    var frequencyDays: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID = UUID(),
        title: String = "",
        categoryId: UUID? = nil,
        frequencyDays: Int = 7,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.title = title
        self.categoryId = categoryId
        self.frequencyDays = frequencyDays
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    convenience init(from chore: RecurringChore) {
        self.init(
            id: chore.id,
            householdId: chore.householdId,
            title: chore.title,
            categoryId: chore.categoryId,
            frequencyDays: max(chore.recurrenceInterval ?? 1, 1),
            createdAt: chore.createdAt,
            updatedAt: chore.updatedAt
        )
    }

    func update(from chore: RecurringChore) {
        householdId = chore.householdId
        title = chore.title
        categoryId = chore.categoryId
        frequencyDays = max(chore.recurrenceInterval ?? 1, 1)
        createdAt = chore.createdAt
        updatedAt = chore.updatedAt
    }

    func toRecurringChore() -> RecurringChore {
        RecurringChore(
            id: id,
            householdId: householdId,
            title: title,
            recurrenceType: .custom,
            recurrenceInterval: max(frequencyDays, 1),
            categoryId: categoryId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
