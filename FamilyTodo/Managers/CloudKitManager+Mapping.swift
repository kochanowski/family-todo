import CloudKit
import Foundation

// MARK: - Record Mapping

extension CloudKitManager {
    // MARK: - ID Helpers

    func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString)
    }

    func recordID(for id: UUID, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    func reference(for id: UUID) -> CKRecord.Reference {
        CKRecord.Reference(recordID: recordID(for: id), action: .none)
    }

    func reference(for id: UUID, in zoneID: CKRecordZone.ID) -> CKRecord.Reference {
        CKRecord.Reference(recordID: recordID(for: id, in: zoneID), action: .none)
    }

    func reference(for id: UUID, zoneID: CKRecordZone.ID?) -> CKRecord.Reference {
        if let zoneID {
            return reference(for: id, in: zoneID)
        }
        return reference(for: id)
    }

    func references(from ids: [UUID]) -> [CKRecord.Reference] {
        ids.map { reference(for: $0) }
    }

    func references(from ids: [UUID], zoneID: CKRecordZone.ID?) -> [CKRecord.Reference] {
        ids.map { reference(for: $0, zoneID: zoneID) }
    }

    func uuid(from reference: CKRecord.Reference?) -> UUID? {
        guard let reference else { return nil }
        return UUID(uuidString: reference.recordID.recordName)
    }

    func uuidArray(from references: [CKRecord.Reference]?) -> [UUID] {
        guard let references else { return [] }
        return references.compactMap { UUID(uuidString: $0.recordID.recordName) }
    }

    func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Int64 {
            return Int(value)
        }
        return nil
    }

    // MARK: - Household Mapping

    func householdRecord(from household: Household) -> CKRecord {
        let record = CKRecord(recordType: "Household", recordID: recordID(for: household.id))
        record["id"] = household.id.uuidString as CKRecordValue
        record["name"] = household.name as CKRecordValue
        record["iconSymbol"] = household.iconSymbol as CKRecordValue
        record["isPremium"] = (household.isPremium ? 1 : 0) as CKRecordValue
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
            iconSymbol: (record["iconSymbol"] as? String) ?? "house.fill",
            isPremium: (record["isPremium"] as? Int64 ?? 0) == 1,
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
        record["colorHex"] = member.colorHex as CKRecordValue
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
            isActive: isActiveValue == 1,
            colorHex: (record["colorHex"] as? String) ?? MemberColorToken.migratedHex(for: id)
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
        record["logicalItemId"] = task.logicalItemID.uuidString as CKRecordValue
        record["householdId"] = reference(for: task.householdId)
        record["title"] = task.title as CKRecordValue
        record["status"] = task.status.rawValue as CKRecordValue
        if let assigneeId = task.assigneeId {
            record["assigneeId"] = reference(for: assigneeId)
        }
        if !task.assigneeIds.isEmpty {
            record["assigneeIds"] = references(from: task.assigneeIds) as CKRecordValue
        }
        if let backlogCategoryId = task.backlogCategoryId {
            record["backlogCategoryId"] = reference(for: backlogCategoryId)
        }
        if let areaId = task.areaId {
            record["areaId"] = reference(for: areaId)
        }
        if let dueDate = task.dueDate {
            record["dueDate"] = dueDate as CKRecordValue
        }
        if let lastPokedAt = task.lastPokedAt {
            record["lastPokedAt"] = lastPokedAt as CKRecordValue
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
        record["order"] = Int64(task.order) as CKRecordValue
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
            logicalItemID: UUID(uuidString: record["logicalItemId"] as? String ?? "") ?? id,
            householdId: householdId,
            title: title,
            status: status,
            assigneeId: uuid(from: record["assigneeId"] as? CKRecord.Reference),
            assigneeIds: uuidArray(from: record["assigneeIds"] as? [CKRecord.Reference]),
            backlogCategoryId: uuid(from: record["backlogCategoryId"] as? CKRecord.Reference),
            areaId: uuid(from: record["areaId"] as? CKRecord.Reference),
            dueDate: record["dueDate"] as? Date,
            lastPokedAt: record["lastPokedAt"] as? Date,
            completedAt: record["completedAt"] as? Date,
            completedById: record["completedById"] as? String,
            taskType: taskType,
            recurringChoreId: uuid(from: record["recurringChoreId"] as? CKRecord.Reference),
            notes: record["notes"] as? String,
            order: Int(record["order"] as? Int64 ?? 0),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - WorkItem Mapping

    func workItemRecord(from item: WorkItem) -> CKRecord {
        let record = CKRecord(recordType: "WorkItem", recordID: recordID(for: item.id))
        record["id"] = item.id.uuidString as CKRecordValue
        record["logicalItemId"] = item.logicalItemID.uuidString as CKRecordValue
        record["householdId"] = reference(for: item.householdId)
        record["title"] = item.title as CKRecordValue
        record["status"] = item.status.rawValue as CKRecordValue
        if let assigneeId = item.assigneeId {
            record["assigneeId"] = reference(for: assigneeId)
        }
        if !item.assigneeIds.isEmpty {
            record["assigneeIds"] = references(from: item.assigneeIds) as CKRecordValue
        }
        if let categoryId = item.categoryId {
            record["categoryId"] = reference(for: categoryId)
        }
        if let areaId = item.areaId {
            record["areaId"] = reference(for: areaId)
        }
        if let dueDate = item.dueDate {
            record["dueDate"] = dueDate as CKRecordValue
        }
        if let lastPokedAt = item.lastPokedAt {
            record["lastPokedAt"] = lastPokedAt as CKRecordValue
        }
        if let completedAt = item.completedAt {
            record["completedAt"] = completedAt as CKRecordValue
        }
        if let completedById = item.completedById {
            record["completedById"] = completedById as CKRecordValue
        }
        record["taskType"] = item.taskType.rawValue as CKRecordValue
        if let recurringChoreId = item.recurringChoreId {
            record["recurringChoreId"] = reference(for: recurringChoreId)
        }
        if let notes = item.notes {
            record["notes"] = notes as CKRecordValue
        }
        record["order"] = Int64(item.order) as CKRecordValue
        record["createdAt"] = item.createdAt as CKRecordValue
        record["updatedAt"] = item.updatedAt as CKRecordValue
        return record
    }

    func workItem(from record: CKRecord) throws -> WorkItem {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let householdReference = record["householdId"] as? CKRecord.Reference,
            let householdId = UUID(uuidString: householdReference.recordID.recordName),
            let title = record["title"] as? String,
            let statusRaw = record["status"] as? String,
            let status = WorkItem.Status(rawValue: statusRaw),
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw CloudKitManagerError.invalidRecord
        }

        return WorkItem(
            id: id,
            logicalItemID: UUID(uuidString: record["logicalItemId"] as? String ?? "") ?? id,
            householdId: householdId,
            title: title,
            status: status,
            assigneeId: uuid(from: record["assigneeId"] as? CKRecord.Reference),
            assigneeIds: uuidArray(from: record["assigneeIds"] as? [CKRecord.Reference]),
            categoryId: uuid(from: record["categoryId"] as? CKRecord.Reference),
            areaId: uuid(from: record["areaId"] as? CKRecord.Reference),
            dueDate: record["dueDate"] as? Date,
            lastPokedAt: record["lastPokedAt"] as? Date,
            completedAt: record["completedAt"] as? Date,
            completedById: record["completedById"] as? String,
            taskType: WorkItem.ItemType(rawValue: record["taskType"] as? String ?? "") ?? .oneOff,
            recurringChoreId: uuid(from: record["recurringChoreId"] as? CKRecord.Reference),
            notes: record["notes"] as? String,
            order: Int(record["order"] as? Int64 ?? 0),
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
        if let assigneeId = chore.assigneeId {
            record["assigneeId"] = reference(for: assigneeId)
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
        if let categoryId = chore.categoryId {
            record["categoryId"] = reference(for: categoryId)
        }
        record["isActive"] = (chore.isActive ? 1 : 0) as CKRecordValue
        if let lastGeneratedDate = chore.lastGeneratedDate {
            record["lastGeneratedDate"] = lastGeneratedDate as CKRecordValue
        }
        if let nextScheduledDate = chore.nextScheduledDate {
            record["nextScheduledDate"] = nextScheduledDate as CKRecordValue
        }
        if let scheduleStartDate = chore.scheduleStartDate {
            record["scheduleStartDate"] = scheduleStartDate as CKRecordValue
        }
        record["scheduledHour"] = chore.scheduledHour as CKRecordValue
        record["scheduledMinute"] = chore.scheduledMinute as CKRecordValue
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
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw CloudKitManagerError.invalidRecord
        }

        let intervalValue =
            record["recurrenceInterval"] as? Int
                ?? (record["recurrenceInterval"] as? Int64).map(Int.init)
        let defaultAssigneeIds = uuidArray(
            from: record["defaultAssigneeIds"] as? [CKRecord.Reference]
        )
        let fallbackAssigneeId = uuid(from: record["defaultAssigneeId"] as? CKRecord.Reference)
        let assigneeId = uuid(from: record["assigneeId"] as? CKRecord.Reference) ?? fallbackAssigneeId
        let resolvedAssigneeIds =
            defaultAssigneeIds.isEmpty
                ? (assigneeId.map { [$0] } ?? [])
                : defaultAssigneeIds
        let scheduleStartDate = record["scheduleStartDate"] as? Date
            ?? record["nextScheduledDate"] as? Date
            ?? createdAt
        let fallbackTimeDate = record["nextScheduledDate"] as? Date ?? scheduleStartDate
        let fallbackTimeComponents = Calendar.current.dateComponents([.hour, .minute], from: fallbackTimeDate)
        let scheduledHour = min(max(intValue(record["scheduledHour"]) ?? fallbackTimeComponents.hour ?? 12, 0), 23)
        let scheduledMinute = min(max(intValue(record["scheduledMinute"]) ?? fallbackTimeComponents.minute ?? 0, 0), 59)

        return RecurringChore(
            id: id,
            householdId: householdId,
            title: title,
            recurrenceType: recurrenceType,
            recurrenceDay: intValue(record["recurrenceDay"]),
            recurrenceDayOfMonth: intValue(record["recurrenceDayOfMonth"]),
            recurrenceInterval: intervalValue,
            assigneeId: assigneeId,
            defaultAssigneeIds: resolvedAssigneeIds,
            areaId: uuid(from: record["areaId"] as? CKRecord.Reference),
            categoryId: uuid(from: record["categoryId"] as? CKRecord.Reference),
            isActive: intValue(record["isActive"]) != 0,
            lastGeneratedDate: record["lastGeneratedDate"] as? Date,
            nextScheduledDate: record["nextScheduledDate"] as? Date,
            scheduleStartDate: scheduleStartDate,
            scheduledHour: scheduledHour,
            scheduledMinute: scheduledMinute,
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
        record["sortOrder"] = item.sortOrder as CKRecordValue
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
        let sortOrderValue =
            record["sortOrder"] as? Int
                ?? (record["sortOrder"] as? Int64).map(Int.init)
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
            sortOrder: sortOrderValue,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - ShoppingBundle Mapping

    func shoppingBundleRecord(from bundle: ShoppingBundle) -> CKRecord {
        let record = CKRecord(recordType: "ShoppingBundle", recordID: recordID(for: bundle.id))
        record["id"] = bundle.id.uuidString as CKRecordValue
        record["householdId"] = reference(for: bundle.householdId)
        record["name"] = bundle.normalizedName as CKRecordValue
        record["icon"] = bundle.resolvedIcon as CKRecordValue
        record["itemsJSON"] = ShoppingBundle.encodeItemsJSON(bundle.normalizedItems) as CKRecordValue
        record["sortOrder"] = bundle.sortOrder as CKRecordValue
        record["createdAt"] = bundle.createdAt as CKRecordValue
        record["updatedAt"] = bundle.updatedAt as CKRecordValue
        return record
    }

    func shoppingBundle(from record: CKRecord) throws -> ShoppingBundle {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let householdReference = record["householdId"] as? CKRecord.Reference,
            let householdId = UUID(uuidString: householdReference.recordID.recordName),
            let name = record["name"] as? String,
            let icon = record["icon"] as? String,
            let itemsJSON = record["itemsJSON"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw CloudKitManagerError.invalidRecord
        }

        let sortOrderValue =
            record["sortOrder"] as? Int
                ?? (record["sortOrder"] as? Int64).map(Int.init)
                ?? 0

        return ShoppingBundle(
            id: id,
            householdId: householdId,
            name: name,
            icon: icon,
            items: ShoppingBundle.decodeItemsJSON(itemsJSON),
            sortOrder: sortOrderValue,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - BacklogCategory Mapping

    func backlogCategoryRecord(from category: BacklogCategory) -> CKRecord {
        let record = CKRecord(recordType: "BacklogCategory", recordID: recordID(for: category.id))
        record["id"] = category.id.uuidString as CKRecordValue
        record["householdId"] = reference(for: category.householdId)
        record["title"] = category.title as CKRecordValue
        record["colorHex"] = category.colorHex as CKRecordValue
        record["sortOrder"] = category.sortOrder as CKRecordValue
        record["createdAt"] = category.createdAt as CKRecordValue
        record["updatedAt"] = category.updatedAt as CKRecordValue
        return record
    }

    func backlogCategory(from record: CKRecord) throws -> BacklogCategory {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let householdReference = record["householdId"] as? CKRecord.Reference,
            let householdId = UUID(uuidString: householdReference.recordID.recordName),
            let title = record["title"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw CloudKitManagerError.invalidRecord
        }

        let sortOrder =
            record["sortOrder"] as? Int
                ?? (record["sortOrder"] as? Int64).map(Int.init)
                ?? 0

        return BacklogCategory(
            id: id,
            householdId: householdId,
            title: title,
            colorHex: (record["colorHex"] as? String) ?? MemberColorToken.migratedHex(for: id),
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - BacklogItem Mapping

    func backlogItemRecord(from item: BacklogItem) -> CKRecord {
        let record = CKRecord(recordType: "BacklogItem", recordID: recordID(for: item.id))
        record["id"] = item.id.uuidString as CKRecordValue
        record["logicalItemId"] = item.logicalItemID.uuidString as CKRecordValue
        record["categoryId"] = reference(for: item.categoryId)
        record["householdId"] = reference(for: item.householdId)
        record["title"] = item.title as CKRecordValue
        if let assigneeId = item.assigneeId {
            record["assigneeId"] = reference(for: assigneeId)
        }
        if let notes = item.notes {
            record["notes"] = notes as CKRecordValue
        }
        record["createdAt"] = item.createdAt as CKRecordValue
        record["updatedAt"] = item.updatedAt as CKRecordValue
        return record
    }

    func backlogItem(from record: CKRecord) throws -> BacklogItem {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let categoryReference = record["categoryId"] as? CKRecord.Reference,
            let categoryId = UUID(uuidString: categoryReference.recordID.recordName),
            let householdReference = record["householdId"] as? CKRecord.Reference,
            let householdId = UUID(uuidString: householdReference.recordID.recordName),
            let title = record["title"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw CloudKitManagerError.invalidRecord
        }

        return BacklogItem(
            id: id,
            logicalItemID: UUID(uuidString: record["logicalItemId"] as? String ?? "") ?? id,
            categoryId: categoryId,
            householdId: householdId,
            title: title,
            assigneeId: uuid(from: record["assigneeId"] as? CKRecord.Reference),
            notes: record["notes"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - InviteToken Mapping

    func inviteTokenRecord(from token: InviteToken) -> CKRecord {
        let record = CKRecord(
            recordType: "InviteToken",
            recordID: CKRecord.ID(recordName: token.id)
        )
        record["code"] = token.code as CKRecordValue
        record["householdId"] = token.householdId.uuidString as CKRecordValue
        record["shareURL"] = token.shareURL as CKRecordValue
        record["createdAt"] = token.createdAt as CKRecordValue
        record["expiresAt"] = token.expiresAt as CKRecordValue
        record["isRevoked"] = (token.isRevoked ? 1 : 0) as CKRecordValue
        record["usesCount"] = Int64(token.usesCount) as CKRecordValue
        record["failedAttempts"] = Int64(token.failedAttempts) as CKRecordValue
        if let lastAttemptAt = token.lastAttemptAt {
            record["lastAttemptAt"] = lastAttemptAt as CKRecordValue
        }
        if let lastRedeemedAt = token.lastRedeemedAt {
            record["lastRedeemedAt"] = lastRedeemedAt as CKRecordValue
        }
        return record
    }

    func inviteToken(from record: CKRecord) throws -> InviteToken {
        guard
            let code = record["code"] as? String,
            let householdRaw = record["householdId"] as? String,
            let householdId = UUID(uuidString: householdRaw),
            let shareURL = record["shareURL"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let expiresAt = record["expiresAt"] as? Date
        else {
            throw CloudKitManagerError.invalidRecord
        }

        let isRevokedRaw =
            record["isRevoked"] as? Int64
                ?? Int64(record["isRevoked"] as? Int ?? 0)
        let usesCountRaw =
            record["usesCount"] as? Int64
                ?? Int64(record["usesCount"] as? Int ?? 0)
        let failedAttemptsRaw =
            record["failedAttempts"] as? Int64
                ?? Int64(record["failedAttempts"] as? Int ?? 0)

        return InviteToken(
            id: record.recordID.recordName,
            code: code,
            householdId: householdId,
            shareURL: shareURL,
            createdAt: createdAt,
            expiresAt: expiresAt,
            isRevoked: isRevokedRaw == 1,
            usesCount: max(Int(usesCountRaw), 0),
            failedAttempts: max(Int(failedAttemptsRaw), 0),
            lastAttemptAt: record["lastAttemptAt"] as? Date,
            lastRedeemedAt: record["lastRedeemedAt"] as? Date
        )
    }
}
