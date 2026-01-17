import CloudKit
import Foundation

actor CloudKitManager {
    static let shared = CloudKitManager()

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase

    init(container: CKContainer = .default()) {
        self.container = container
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
    }

    enum CloudKitManagerError: Error {
        case invalidRecord
    }

    // MARK: - Household

    func saveHousehold(_ household: Household) async throws -> CKRecord {
        let record = householdRecord(from: household)
        return try await sharedDatabase.save(record)
    }

    func fetchHousehold(id: UUID) async throws -> Household {
        let record = try await sharedDatabase.record(for: recordID(for: id))
        return try household(from: record)
    }

    func deleteHousehold(id: UUID) async throws {
        _ = try await sharedDatabase.deleteRecord(withID: recordID(for: id))
    }

    // MARK: - Member

    func saveMember(_ member: Member) async throws -> CKRecord {
        let record = memberRecord(from: member)
        return try await sharedDatabase.save(record)
    }

    func fetchMember(id: UUID) async throws -> Member {
        let record = try await sharedDatabase.record(for: recordID(for: id))
        return try member(from: record)
    }

    func deleteMember(id: UUID) async throws {
        _ = try await sharedDatabase.deleteRecord(withID: recordID(for: id))
    }

    /// Find member by Apple user ID
    func fetchMemberByUserId(_ userId: String) async throws -> Member? {
        let predicate = NSPredicate(format: "userId == %@", userId)
        let query = CKQuery(recordType: "Member", predicate: predicate)

        let (results, _) = try await sharedDatabase.records(matching: query)
        guard let (_, result) = results.first,
              case let .success(record) = result
        else {
            return nil
        }
        return try member(from: record)
    }

    // MARK: - Area

    func saveArea(_ area: Area) async throws -> CKRecord {
        let record = areaRecord(from: area)
        return try await sharedDatabase.save(record)
    }

    func fetchArea(id: UUID) async throws -> Area {
        let record = try await sharedDatabase.record(for: recordID(for: id))
        return try area(from: record)
    }

    func deleteArea(id: UUID) async throws {
        _ = try await sharedDatabase.deleteRecord(withID: recordID(for: id))
    }

    /// Fetch all areas for a household
    func fetchAreas(householdId: UUID) async throws -> [Area] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "Area", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

        let (results, _) = try await sharedDatabase.records(matching: query)
        return try results.compactMap { _, result in
            guard case let .success(record) = result else { return nil }
            return try area(from: record)
        }
    }

    // MARK: - Task

    func saveTask(_ task: Task) async throws -> CKRecord {
        let record = taskRecord(from: task)
        return try await sharedDatabase.save(record)
    }

    func fetchTask(id: UUID) async throws -> Task {
        let record = try await sharedDatabase.record(for: recordID(for: id))
        return try task(from: record)
    }

    func deleteTask(id: UUID) async throws {
        _ = try await sharedDatabase.deleteRecord(withID: recordID(for: id))
    }

    /// Fetch all tasks for a household
    func fetchTasks(householdId: UUID) async throws -> [Task] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "Task", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let (results, _) = try await sharedDatabase.records(matching: query)
        return try results.compactMap { _, result in
            guard case let .success(record) = result else { return nil }
            return try task(from: record)
        }
    }

    /// Fetch tasks filtered by status
    func fetchTasks(householdId: UUID, status: Task.TaskStatus) async throws -> [Task] {
        let predicate = NSPredicate(
            format: "householdId == %@ AND status == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none),
            status.rawValue
        )
        let query = CKQuery(recordType: "Task", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let (results, _) = try await sharedDatabase.records(matching: query)
        return try results.compactMap { _, result in
            guard case let .success(record) = result else { return nil }
            return try task(from: record)
        }
    }

    /// Fetch tasks assigned to a specific member in "next" status (for WIP limit check)
    func fetchNextTasks(assigneeId: UUID) async throws -> [Task] {
        let predicate = NSPredicate(
            format: "assigneeId == %@ AND status == %@",
            CKRecord.Reference(recordID: recordID(for: assigneeId), action: .none),
            Task.TaskStatus.next.rawValue
        )
        let query = CKQuery(recordType: "Task", predicate: predicate)

        let (results, _) = try await sharedDatabase.records(matching: query)
        return try results.compactMap { _, result in
            guard case let .success(record) = result else { return nil }
            return try task(from: record)
        }
    }

    /// Count tasks in "next" for a member (WIP limit = 3)
    func countNextTasks(assigneeId: UUID) async throws -> Int {
        try await fetchNextTasks(assigneeId: assigneeId).count
    }

    // MARK: - Recurring Chore

    func saveRecurringChore(_ chore: RecurringChore) async throws -> CKRecord {
        let record = recurringChoreRecord(from: chore)
        return try await sharedDatabase.save(record)
    }

    func fetchRecurringChore(id: UUID) async throws -> RecurringChore {
        let record = try await sharedDatabase.record(for: recordID(for: id))
        return try recurringChore(from: record)
    }

    func deleteRecurringChore(id: UUID) async throws {
        _ = try await sharedDatabase.deleteRecord(withID: recordID(for: id))
    }

    /// Fetch all recurring chores for a household
    func fetchRecurringChores(householdId: UUID) async throws -> [RecurringChore] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "RecurringChore", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]

        let (results, _) = try await sharedDatabase.records(matching: query)
        return try results.compactMap { _, result in
            guard case let .success(record) = result else { return nil }
            return try recurringChore(from: record)
        }
    }

    // MARK: - Mapping

    private func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString)
    }

    private func reference(for id: UUID) -> CKRecord.Reference {
        CKRecord.Reference(recordID: recordID(for: id), action: .none)
    }

    private func uuid(from reference: CKRecord.Reference?) -> UUID? {
        guard let reference else { return nil }
        return UUID(uuidString: reference.recordID.recordName)
    }

    private func householdRecord(from household: Household) -> CKRecord {
        let record = CKRecord(recordType: "Household", recordID: recordID(for: household.id))
        record["id"] = household.id.uuidString as CKRecordValue
        record["name"] = household.name as CKRecordValue
        record["ownerId"] = household.ownerId as CKRecordValue
        record["createdAt"] = household.createdAt as CKRecordValue
        record["updatedAt"] = household.updatedAt as CKRecordValue
        return record
    }

    private func household(from record: CKRecord) throws -> Household {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let name = record["name"] as? String,
            let ownerId = record["ownerId"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw CloudKitManagerError.invalidRecord
        }

        return Household(
            id: id,
            name: name,
            ownerId: ownerId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func memberRecord(from member: Member) -> CKRecord {
        let record = CKRecord(recordType: "Member", recordID: recordID(for: member.id))
        record["id"] = member.id.uuidString as CKRecordValue
        record["householdId"] = reference(for: member.householdId)
        record["userId"] = member.userId as CKRecordValue
        record["displayName"] = member.displayName as CKRecordValue
        record["role"] = member.role.rawValue as CKRecordValue
        record["joinedAt"] = member.joinedAt as CKRecordValue
        record["isActive"] = (member.isActive ? 1 : 0) as CKRecordValue
        return record
    }

    private func member(from record: CKRecord) throws -> Member {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let householdReference = record["householdId"] as? CKRecord.Reference,
            let householdId = UUID(uuidString: householdReference.recordID.recordName),
            let userId = record["userId"] as? String,
            let displayName = record["displayName"] as? String,
            let roleRaw = record["role"] as? String,
            let role = Member.MemberRole(rawValue: roleRaw),
            let joinedAt = record["joinedAt"] as? Date,
            let isActiveValue = record["isActive"] as? Int64
        else {
            throw CloudKitManagerError.invalidRecord
        }

        return Member(
            id: id,
            householdId: householdId,
            userId: userId,
            displayName: displayName,
            role: role,
            joinedAt: joinedAt,
            isActive: isActiveValue == 1
        )
    }

    private func areaRecord(from area: Area) -> CKRecord {
        let record = CKRecord(recordType: "Area", recordID: recordID(for: area.id))
        record["id"] = area.id.uuidString as CKRecordValue
        record["householdId"] = reference(for: area.householdId)
        record["name"] = area.name as CKRecordValue
        if let icon = area.icon {
            record["icon"] = icon as CKRecordValue
        }
        record["sortOrder"] = area.sortOrder as CKRecordValue
        record["createdAt"] = area.createdAt as CKRecordValue
        return record
    }

    private func area(from record: CKRecord) throws -> Area {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let householdReference = record["householdId"] as? CKRecord.Reference,
            let householdId = UUID(uuidString: householdReference.recordID.recordName),
            let name = record["name"] as? String,
            let sortOrder = record["sortOrder"] as? Int64,
            let createdAt = record["createdAt"] as? Date
        else {
            throw CloudKitManagerError.invalidRecord
        }

        let icon = record["icon"] as? String

        return Area(
            id: id,
            householdId: householdId,
            name: name,
            icon: icon,
            sortOrder: Int(sortOrder),
            createdAt: createdAt
        )
    }

    private func taskRecord(from task: Task) -> CKRecord {
        let record = CKRecord(recordType: "Task", recordID: recordID(for: task.id))
        record["id"] = task.id.uuidString as CKRecordValue
        record["householdId"] = reference(for: task.householdId)
        record["title"] = task.title as CKRecordValue
        record["status"] = task.status.rawValue as CKRecordValue
        if let assigneeId = task.assigneeId {
            record["assigneeId"] = reference(for: assigneeId)
        }
        if let areaId = task.areaId {
            record["areaId"] = reference(for: areaId)
        }
        if let dueDate = task.dueDate {
            record["dueDate"] = dueDate as CKRecordValue
        }
        if let completedAt = task.completedAt {
            record["completedAt"] = completedAt as CKRecordValue
        }
        if let completedById = task.completedById {
            record["completedById"] = completedById as CKRecordValue
        }
        record["taskType"] = task.taskType.rawValue as CKRecordValue
        if let recurringChoreId = task.recurringChoreId {
            record["recurringChoreId"] = reference(for: recurringChoreId)
        }
        if let notes = task.notes {
            record["notes"] = notes as CKRecordValue
        }
        record["createdAt"] = task.createdAt as CKRecordValue
        record["updatedAt"] = task.updatedAt as CKRecordValue
        return record
    }

    private func task(from record: CKRecord) throws -> Task {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let householdReference = record["householdId"] as? CKRecord.Reference,
            let householdId = UUID(uuidString: householdReference.recordID.recordName),
            let title = record["title"] as? String,
            let statusRaw = record["status"] as? String,
            let status = Task.TaskStatus(rawValue: statusRaw),
            let taskTypeRaw = record["taskType"] as? String,
            let taskType = Task.TaskType(rawValue: taskTypeRaw),
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw CloudKitManagerError.invalidRecord
        }

        return Task(
            id: id,
            householdId: householdId,
            title: title,
            status: status,
            assigneeId: uuid(from: record["assigneeId"] as? CKRecord.Reference),
            areaId: uuid(from: record["areaId"] as? CKRecord.Reference),
            dueDate: record["dueDate"] as? Date,
            completedAt: record["completedAt"] as? Date,
            completedById: record["completedById"] as? String,
            taskType: taskType,
            recurringChoreId: uuid(from: record["recurringChoreId"] as? CKRecord.Reference),
            notes: record["notes"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func recurringChoreRecord(from chore: RecurringChore) -> CKRecord {
        let record = CKRecord(recordType: "RecurringChore", recordID: recordID(for: chore.id))
        record["id"] = chore.id.uuidString as CKRecordValue
        record["householdId"] = reference(for: chore.householdId)
        record["title"] = chore.title as CKRecordValue
        record["recurrenceType"] = chore.recurrenceType.rawValue as CKRecordValue
        if let recurrenceDay = chore.recurrenceDay {
            record["recurrenceDay"] = recurrenceDay as CKRecordValue
        }
        if let recurrenceDayOfMonth = chore.recurrenceDayOfMonth {
            record["recurrenceDayOfMonth"] = recurrenceDayOfMonth as CKRecordValue
        }
        if let defaultAssigneeId = chore.defaultAssigneeId {
            record["defaultAssigneeId"] = reference(for: defaultAssigneeId)
        }
        if let areaId = chore.areaId {
            record["areaId"] = reference(for: areaId)
        }
        record["isActive"] = (chore.isActive ? 1 : 0) as CKRecordValue
        if let lastGeneratedDate = chore.lastGeneratedDate {
            record["lastGeneratedDate"] = lastGeneratedDate as CKRecordValue
        }
        if let nextScheduledDate = chore.nextScheduledDate {
            record["nextScheduledDate"] = nextScheduledDate as CKRecordValue
        }
        if let notes = chore.notes {
            record["notes"] = notes as CKRecordValue
        }
        record["createdAt"] = chore.createdAt as CKRecordValue
        record["updatedAt"] = chore.updatedAt as CKRecordValue
        return record
    }

    private func recurringChore(from record: CKRecord) throws -> RecurringChore {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let householdReference = record["householdId"] as? CKRecord.Reference,
            let householdId = UUID(uuidString: householdReference.recordID.recordName),
            let title = record["title"] as? String,
            let recurrenceTypeRaw = record["recurrenceType"] as? String,
            let recurrenceType = RecurringChore.RecurrenceType(rawValue: recurrenceTypeRaw),
            let isActiveValue = record["isActive"] as? Int64,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw CloudKitManagerError.invalidRecord
        }

        return RecurringChore(
            id: id,
            householdId: householdId,
            title: title,
            recurrenceType: recurrenceType,
            recurrenceDay: record["recurrenceDay"] as? Int,
            recurrenceDayOfMonth: record["recurrenceDayOfMonth"] as? Int,
            defaultAssigneeId: uuid(from: record["defaultAssigneeId"] as? CKRecord.Reference),
            areaId: uuid(from: record["areaId"] as? CKRecord.Reference),
            isActive: isActiveValue == 1,
            lastGeneratedDate: record["lastGeneratedDate"] as? Date,
            nextScheduledDate: record["nextScheduledDate"] as? Date,
            notes: record["notes"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
