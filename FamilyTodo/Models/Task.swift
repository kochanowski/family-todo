import Foundation

struct Task: Identifiable, Codable {
    let id: UUID
    let logicalItemID: UUID
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

    private enum CodingKeys: String, CodingKey {
        case id
        case logicalItemID
        case householdId
        case title
        case status
        case assigneeId
        case assigneeIds
        case backlogCategoryId
        case areaId
        case dueDate
        case lastPokedAt
        case completedAt
        case completedById
        case taskType
        case recurringChoreId
        case notes
        case order
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        logicalItemID: UUID? = nil,
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
        self.logicalItemID = logicalItemID ?? id
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decode(UUID.self, forKey: .id)

        id = decodedID
        logicalItemID = try container.decodeIfPresent(UUID.self, forKey: .logicalItemID) ?? decodedID
        householdId = try container.decode(UUID.self, forKey: .householdId)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(TaskStatus.self, forKey: .status)
        assigneeId = try container.decodeIfPresent(UUID.self, forKey: .assigneeId)
        assigneeIds = try container.decodeIfPresent([UUID].self, forKey: .assigneeIds) ?? []
        backlogCategoryId = try container.decodeIfPresent(UUID.self, forKey: .backlogCategoryId)
        areaId = try container.decodeIfPresent(UUID.self, forKey: .areaId)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        lastPokedAt = try container.decodeIfPresent(Date.self, forKey: .lastPokedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        completedById = try container.decodeIfPresent(String.self, forKey: .completedById)
        taskType = try container.decode(TaskType.self, forKey: .taskType)
        recurringChoreId = try container.decodeIfPresent(UUID.self, forKey: .recurringChoreId)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var isOverdue: Bool {
        guard let dueDate, status != .done else {
            return false
        }

        return dueDate < Date()
    }

    static func dueDateHasExplicitTime(
        _ dueDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let components = calendar.dateComponents([.hour, .minute, .second], from: dueDate)
        return (components.hour ?? 0) != 0 ||
            (components.minute ?? 0) != 0 ||
            (components.second ?? 0) != 0
    }

    static func date(
        byApplyingTimeFrom sourceTime: Date,
        to destinationDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: destinationDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: sourceTime)
        var merged = DateComponents()
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second
        return calendar.date(from: merged)
    }
}
