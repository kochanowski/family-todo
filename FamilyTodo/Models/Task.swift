import Foundation

struct Task: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var title: String
    var status: TaskStatus
    var assigneeId: UUID?
    var assigneeIds: [UUID]
    var backlogCategoryId: UUID?
    var areaId: UUID?
    var dueDate: Date?
    var lastPokedAt: Date?
    var completedAt: Date?
    var completedById: String?
    let taskType: TaskType
    var recurringChoreId: UUID?
    var notes: String?
    var order: Int
    let createdAt: Date
    var updatedAt: Date

    enum TaskStatus: String, Codable {
        case backlog
        case next
        case done
    }

    enum TaskType: String, Codable {
        case oneOff = "one-off"
        case recurring
    }

    init(
        id: UUID = UUID(),
        householdId: UUID,
        title: String,
        status: TaskStatus,
        assigneeId: UUID? = nil,
        assigneeIds: [UUID] = [],
        backlogCategoryId: UUID? = nil,
        areaId: UUID? = nil,
        dueDate: Date? = nil,
        lastPokedAt: Date? = nil,
        completedAt: Date? = nil,
        completedById: String? = nil,
        taskType: TaskType,
        recurringChoreId: UUID? = nil,
        notes: String? = nil,
        order: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.title = title
        self.status = status
        self.assigneeId = assigneeId
        self.assigneeIds = assigneeIds
        self.backlogCategoryId = backlogCategoryId
        self.areaId = areaId
        self.dueDate = dueDate
        self.lastPokedAt = lastPokedAt
        self.completedAt = completedAt
        self.completedById = completedById
        self.taskType = taskType
        self.recurringChoreId = recurringChoreId
        self.notes = notes
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isOverdue: Bool {
        guard let dueDate, status != .done else {
            return false
        }

        return dueDate < Date()
    }
}
