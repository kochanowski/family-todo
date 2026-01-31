import Foundation
import SwiftData
import SwiftUI

// MARK: - Legacy Stubs
// These types existed in the old implementation but are being refactored.
// Stubs allow existing code to compile while we migrate to new architecture.

// MARK: - Models

struct Household: Identifiable, Codable {
    let id: UUID
    var name: String
    let ownerId: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct Area: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var name: String
    var icon: String?
    var colorHex: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

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

struct ShareInviteView: View {
    let householdId: UUID

    init(householdId: UUID) {
        self.householdId = householdId
    }

    var body: some View {
        Text("Share Invite - Coming Soon")
            .font(.headline)
    }
}

struct TaskDetailView: View {
    @Binding var task: Task
    let householdId: UUID
    let members: [Member]
    let areas: [Area]
    let onSave: (Task) -> Void
    let onDelete: () -> Void

    init(
        task: Binding<Task>,
        householdId: UUID,
        members: [Member] = [],
        areas: [Area] = [],
        onSave: @escaping (Task) -> Void = { _ in },
        onDelete: @escaping () -> Void = {}
    ) {
        self._task = task
        self.householdId = householdId
        self.members = members
        self.areas = areas
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        Text("Task Detail - Coming Soon")
            .font(.headline)
    }
}

// MARK: - Stores

@MainActor
class HouseholdStore: ObservableObject {
    @Published var currentHousehold: Household?
    @Published var isLoading = false
    @Published var hasHousehold: Bool = false

    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setSyncMode(_: SyncMode) {}

    func loadHousehold(userId _: String) async {
        isLoading = true
        // Stub - will load from CloudKit
        isLoading = false
    }

    func createHousehold(name _: String, userId: String, displayName: String) async throws -> Household {
        Household(name: name, ownerId: userId)
    }

    func joinHousehold(inviteCode: String, userId _: String, displayName _: String) async throws {}
}

@MainActor
class AreaStore: ObservableObject {
    @Published var areas: [Area] = []
    @Published var isLoading = false

    init(householdId: UUID? = nil, modelContext: ModelContext? = nil) {
        // Stub init
    }

    func setSyncMode(_: SyncMode) {}

    func loadAreas(householdId _: UUID? = nil) async {}
}

@MainActor
class MemberStore: ObservableObject {
    @Published var members: [Member] = []
    @Published var isLoading = false

    func loadMembers(householdId _: UUID) async {}
}

@MainActor
class NotificationSettingsStore: ObservableObject {
    @Published var isEnabled = true
    @Published var reminderTime = Date()
}

// MARK: - Cached Models

@Model
final class CachedHousehold {
    @Attribute(.unique) var id: UUID
    var name: String
    var ownerId: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        ownerId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
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
