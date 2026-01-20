import CloudKit
import Foundation

// MARK: - Record Mapping

extension CloudKitManager {
    // MARK: - ID Helpers

    func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString)
    }

    func reference(for id: UUID) -> CKRecord.Reference {
        CKRecord.Reference(recordID: recordID(for: id), action: .none)
    }

    func references(from ids: [UUID]) -> [CKRecord.Reference] {
        ids.map { reference(for: $0) }
    }

    func uuid(from reference: CKRecord.Reference?) -> UUID? {
        guard let reference else { return nil }
        return UUID(uuidString: reference.recordID.recordName)
    }

    func uuidArray(from references: [CKRecord.Reference]?) -> [UUID] {
        guard let references else { return [] }
        return references.compactMap { UUID(uuidString: $0.recordID.recordName) }
    }

    // MARK: - Household Mapping

    func householdRecord(from household: Household) -> CKRecord {
        let record = CKRecord(recordType: "Household", recordID: recordID(for: household.id))
        record["id"] = household.id.uuidString as CKRecordValue
        record["name"] = household.name as CKRecordValue
        record["ownerId"] = household.ownerId as CKRecordValue
        record["createdAt"] = household.createdAt as CKRecordValue
        record["updatedAt"] = household.updatedAt as CKRecordValue
        return record
    }

    func household(from record: CKRecord) throws -> Household {
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

    // MARK: - Member Mapping

    func memberRecord(from member: Member) -> CKRecord {
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

    func member(from record: CKRecord) throws -> Member {
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

    // MARK: - Area Mapping

    func areaRecord(from area: Area) -> CKRecord {
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

    func area(from record: CKRecord) throws -> Area {
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

    // MARK: - Task Mapping

    func taskRecord(from task: Task) -> CKRecord {
        let record = CKRecord(recordType: "Task", recordID: recordID(for: task.id))
        record["id"] = task.id.uuidString as CKRecordValue
        record["householdId"] = reference(for: task.householdId)
        record["title"] = task.title as CKRecordValue
        record["status"] = task.status.rawValue as CKRecordValue
        if let assigneeId = task.assigneeId {
            record["assigneeId"] = reference(for: assigneeId)
        }
        if !task.assigneeIds.isEmpty {
            record["assigneeIds"] = references(from: task.assigneeIds) as CKRecordValue
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

    func task(from record: CKRecord) throws -> Task {
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
            assigneeIds: uuidArray(from: record["assigneeIds"] as? [CKRecord.Reference]),
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

    // MARK: - RecurringChore Mapping

    func recurringChoreRecord(from chore: RecurringChore) -> CKRecord {
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
        if let recurrenceInterval = chore.recurrenceInterval {
            record["recurrenceInterval"] = recurrenceInterval as CKRecordValue
        }
        if !chore.defaultAssigneeIds.isEmpty {
            record["defaultAssigneeIds"] =
                references(from: chore.defaultAssigneeIds) as CKRecordValue
        }
        if let firstAssignee = chore.defaultAssigneeIds.first {
            record["defaultAssigneeId"] = reference(for: firstAssignee)
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

    func recurringChore(from record: CKRecord) throws -> RecurringChore {
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

        let intervalValue =
            record["recurrenceInterval"] as? Int
                ?? (record["recurrenceInterval"] as? Int64).map(Int.init)
        let defaultAssigneeIds = uuidArray(
            from: record["defaultAssigneeIds"] as? [CKRecord.Reference])
        let fallbackAssigneeId = uuid(from: record["defaultAssigneeId"] as? CKRecord.Reference)
        let resolvedAssigneeIds =
            defaultAssigneeIds.isEmpty
                ? (fallbackAssigneeId.map { [$0] } ?? [])
                : defaultAssigneeIds

        return RecurringChore(
            id: id,
            householdId: householdId,
            title: title,
            recurrenceType: recurrenceType,
            recurrenceDay: record["recurrenceDay"] as? Int,
            recurrenceDayOfMonth: record["recurrenceDayOfMonth"] as? Int,
            recurrenceInterval: intervalValue,
            defaultAssigneeIds: resolvedAssigneeIds,
            areaId: uuid(from: record["areaId"] as? CKRecord.Reference),
            isActive: isActiveValue == 1,
            lastGeneratedDate: record["lastGeneratedDate"] as? Date,
            nextScheduledDate: record["nextScheduledDate"] as? Date,
            notes: record["notes"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - ShoppingItem Mapping

    func shoppingItemRecord(from item: ShoppingItem) -> CKRecord {
        let record = CKRecord(recordType: "ShoppingItem", recordID: recordID(for: item.id))
        record["id"] = item.id.uuidString as CKRecordValue
        record["householdId"] = reference(for: item.householdId)
        record["title"] = item.title as CKRecordValue
        if let quantityValue = item.quantityValue {
            record["quantityValue"] = quantityValue as CKRecordValue
        }
        if let quantityUnit = item.quantityUnit {
            record["quantityUnit"] = quantityUnit as CKRecordValue
        }
        record["isBought"] = (item.isBought ? 1 : 0) as CKRecordValue
        if let boughtAt = item.boughtAt {
            record["boughtAt"] = boughtAt as CKRecordValue
        }
        record["restockCount"] = item.restockCount as CKRecordValue
        record["createdAt"] = item.createdAt as CKRecordValue
        record["updatedAt"] = item.updatedAt as CKRecordValue
        return record
    }

    func shoppingItem(from record: CKRecord) throws -> ShoppingItem {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let householdReference = record["householdId"] as? CKRecord.Reference,
            let householdId = UUID(uuidString: householdReference.recordID.recordName),
            let title = record["title"] as? String,
            let isBoughtValue = record["isBought"] as? Int64,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw CloudKitManagerError.invalidRecord
        }

        let restockCountValue =
            record["restockCount"] as? Int
                ?? (record["restockCount"] as? Int64).map(Int.init)
                ?? 0

        return ShoppingItem(
            id: id,
            householdId: householdId,
            title: title,
            quantityValue: record["quantityValue"] as? String,
            quantityUnit: record["quantityUnit"] as? String,
            isBought: isBoughtValue == 1,
            boughtAt: record["boughtAt"] as? Date,
            restockCount: restockCountValue,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
