import Foundation

struct WorkItem: Identifiable, Codable {
    let id: UUID
    let logicalItemID: UUID
    let householdId: UUID
    var title: String
    var status: Status
    var assigneeId: UUID?
    var assigneeIds: [UUID]
    var categoryId: UUID?
    var areaId: UUID?
    var dueDate: Date?
    var lastPokedAt: Date?
    var completedAt: Date?
    var completedById: String?
    var taskType: ItemType
    var recurringChoreId: UUID?
    var notes: String?
    var order: Int
    let createdAt: Date
    var updatedAt: Date

    enum Status: String, Codable {
        case idea
        case backlog
        case next
        case done
    }

    enum ItemType: String, Codable {
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
        case categoryId
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
        status: Status,
        assigneeId: UUID? = nil,
        assigneeIds: [UUID] = [],
        categoryId: UUID? = nil,
        areaId: UUID? = nil,
        dueDate: Date? = nil,
        lastPokedAt: Date? = nil,
        completedAt: Date? = nil,
        completedById: String? = nil,
        taskType: ItemType = .oneOff,
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
        self.categoryId = categoryId
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
        status = try container.decode(Status.self, forKey: .status)
        assigneeId = try container.decodeIfPresent(UUID.self, forKey: .assigneeId)
        assigneeIds = try container.decodeIfPresent([UUID].self, forKey: .assigneeIds) ?? []
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        areaId = try container.decodeIfPresent(UUID.self, forKey: .areaId)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        lastPokedAt = try container.decodeIfPresent(Date.self, forKey: .lastPokedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        completedById = try container.decodeIfPresent(String.self, forKey: .completedById)
        taskType = try container.decodeIfPresent(ItemType.self, forKey: .taskType) ?? .oneOff
        recurringChoreId = try container.decodeIfPresent(UUID.self, forKey: .recurringChoreId)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

extension WorkItem {
    init(
        id: UUID = UUID(),
        logicalItemID: UUID? = nil,
        task: Task
    ) {
        self.init(
            id: id,
            logicalItemID: logicalItemID ?? task.logicalItemID,
            householdId: task.householdId,
            title: task.title,
            status: Status(taskStatus: task.status),
            assigneeId: task.assigneeId,
            assigneeIds: task.assigneeIds,
            categoryId: task.backlogCategoryId,
            areaId: task.areaId,
            dueDate: task.dueDate,
            lastPokedAt: task.lastPokedAt,
            completedAt: task.completedAt,
            completedById: task.completedById,
            taskType: ItemType(taskType: task.taskType),
            recurringChoreId: task.recurringChoreId,
            notes: task.notes,
            order: task.order,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt
        )
    }

    init(from task: Task) {
        self.init(task: task)
    }

    init(task: Task) {
        self.init(
            id: task.id,
            logicalItemID: task.logicalItemID,
            householdId: task.householdId,
            title: task.title,
            status: Status(taskStatus: task.status),
            assigneeId: task.assigneeId,
            assigneeIds: task.assigneeIds,
            categoryId: task.backlogCategoryId,
            areaId: task.areaId,
            dueDate: task.dueDate,
            lastPokedAt: task.lastPokedAt,
            completedAt: task.completedAt,
            completedById: task.completedById,
            taskType: ItemType(taskType: task.taskType),
            recurringChoreId: task.recurringChoreId,
            notes: task.notes,
            order: task.order,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt
        )
    }

    init(from idea: BacklogItem) {
        self.init(idea: idea)
    }

    init(idea: BacklogItem) {
        self.init(
            id: idea.id,
            logicalItemID: idea.logicalItemID,
            householdId: idea.householdId,
            title: idea.title,
            status: .idea,
            assigneeId: idea.assigneeId,
            assigneeIds: idea.assigneeId.map { [$0] } ?? [],
            categoryId: idea.categoryId,
            notes: idea.notes,
            createdAt: idea.createdAt,
            updatedAt: idea.updatedAt
        )
    }

    func toTask() -> Task {
        guard let task = asTask() else {
            preconditionFailure("Ideas cannot be converted to Task")
        }
        return task
    }

    func asTask() -> Task? {
        let taskStatus: Task.TaskStatus
        switch status {
        case .idea:
            return nil
        case .backlog:
            taskStatus = .backlog
        case .next:
            taskStatus = .next
        case .done:
            taskStatus = .done
        }

        return Task(
            id: id,
            logicalItemID: logicalItemID,
            householdId: householdId,
            title: title,
            status: taskStatus,
            assigneeId: assigneeId,
            assigneeIds: assigneeIds,
            backlogCategoryId: categoryId,
            areaId: areaId,
            dueDate: dueDate,
            lastPokedAt: lastPokedAt,
            completedAt: completedAt,
            completedById: completedById,
            taskType: Task.TaskType(workItemType: taskType),
            recurringChoreId: recurringChoreId,
            notes: notes,
            order: order,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func toBacklogItem(fallbackCategoryId: UUID? = nil) -> BacklogItem {
        if let item = asBacklogItem() {
            return item
        }

        return BacklogItem(
            id: id,
            logicalItemID: logicalItemID,
            categoryId: categoryId ?? fallbackCategoryId ?? UUID(),
            householdId: householdId,
            title: title,
            assigneeId: assigneeId,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func asBacklogItem() -> BacklogItem? {
        guard status == .idea, let categoryId else { return nil }
        return BacklogItem(
            id: id,
            logicalItemID: logicalItemID,
            categoryId: categoryId,
            householdId: householdId,
            title: title,
            assigneeId: assigneeId,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension WorkItem.Status {
    init(taskStatus: Task.TaskStatus) {
        switch taskStatus {
        case .backlog:
            self = .backlog
        case .next:
            self = .next
        case .done:
            self = .done
        }
    }
}

extension WorkItem.ItemType {
    init(taskType: Task.TaskType) {
        switch taskType {
        case .oneOff:
            self = .oneOff
        case .recurring:
            self = .recurring
        }
    }
}

extension Task.TaskType {
    init(workItemType: WorkItem.ItemType) {
        switch workItemType {
        case .oneOff:
            self = .oneOff
        case .recurring:
            self = .recurring
        }
    }
}
