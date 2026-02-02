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
    case cacheNotAvailable
}

@MainActor
class AreaStore: ObservableObject {
    @Published var areas: [Area] = []
    @Published var isLoading = false

    init(householdId _: UUID? = nil, modelContext _: ModelContext? = nil) {
        // Stub init
    }

    func setSyncMode(_: SyncMode) {}

    func loadAreas(householdId _: UUID? = nil) async {}
}

@MainActor
class NotificationSettingsStore: ObservableObject {
    @Published var isEnabled = true
    @Published var reminderTime = Date()
    @Published var taskRemindersEnabled = true
    @Published var dailyDigestEnabled = true
    @Published var soundEnabled = true
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
}

@Model
final class CachedRecurringChore {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var title: String
    var frequencyDays: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        householdId: UUID = UUID(),
        title: String = "",
        frequencyDays: Int = 7,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.title = title
        self.frequencyDays = frequencyDays
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
