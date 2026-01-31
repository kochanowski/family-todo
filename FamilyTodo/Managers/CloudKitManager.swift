import CloudKit
import Foundation

actor CloudKitManager {
    static let shared = CloudKitManager()

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase

    init(container: CKContainer? = nil) {
        #if CI
            // Use a stub container in CI to prevent crashes
            self.container = CKContainer(identifier: "iCloud.com.example.familytodo")
        #else
            self.container = container ?? .default()
        #endif
        privateDatabase = self.container.privateCloudDatabase
        sharedDatabase = self.container.sharedCloudDatabase
    }

    enum CloudKitManagerError: LocalizedError {
        case invalidRecord
        case shareNotCreated
        case networkUnavailable
        case notAuthenticated
        case quotaExceeded
        case serverRecordChanged
        case unknownError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidRecord:
                "Invalid record data"
            case .shareNotCreated:
                "Failed to create share"
            case .networkUnavailable:
                "No internet connection. Changes will sync when online."
            case .notAuthenticated:
                "Please sign in to iCloud in Settings."
            case .quotaExceeded:
                "iCloud storage is full. Please free up space."
            case .serverRecordChanged:
                "This item was modified elsewhere. Refreshing..."
            case let .unknownError(error):
                "An error occurred: \(error.localizedDescription)"
            }
        }
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

    /// Fetch all members for a household
    func fetchMembers(householdId: UUID) async throws -> [Member] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "Member", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: true)]

        let (results, _) = try await sharedDatabase.records(matching: query)
        return try results.compactMap { _, result in
            guard case let .success(record) = result else { return nil }
            return try member(from: record)
        }
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

    // MARK: - Shopping Item

    func saveShoppingItem(_ item: ShoppingItem) async throws -> CKRecord {
        let record = shoppingItemRecord(from: item)
        return try await sharedDatabase.save(record)
    }

    func fetchShoppingItem(id: UUID) async throws -> ShoppingItem {
        let record = try await sharedDatabase.record(for: recordID(for: id))
        return try shoppingItem(from: record)
    }

    func deleteShoppingItem(id: UUID) async throws {
        _ = try await sharedDatabase.deleteRecord(withID: recordID(for: id))
    }

    /// Fetch all shopping items for a household
    func fetchShoppingItems(householdId: UUID) async throws -> [ShoppingItem] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "ShoppingItem", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let (results, _) = try await sharedDatabase.records(matching: query)
        return try results.compactMap { _, result in
            guard case let .success(record) = result else { return nil }
            return try shoppingItem(from: record)
        }
    }

    // MARK: - Backlog Category

    func saveBacklogCategory(_ category: BacklogCategory) async throws -> CKRecord {
        let record = backlogCategoryRecord(from: category)
        return try await sharedDatabase.save(record)
    }

    func fetchBacklogCategory(id: UUID) async throws -> BacklogCategory {
        let record = try await sharedDatabase.record(for: recordID(for: id))
        return try backlogCategory(from: record)
    }

    func deleteBacklogCategory(id: UUID) async throws {
        _ = try await sharedDatabase.deleteRecord(withID: recordID(for: id))
    }

    /// Fetch all backlog categories for a household
    func fetchBacklogCategories(householdId: UUID) async throws -> [BacklogCategory] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "BacklogCategory", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

        let (results, _) = try await sharedDatabase.records(matching: query)
        return try results.compactMap { _, result in
            guard case let .success(record) = result else { return nil }
            return try backlogCategory(from: record)
        }
    }

    // MARK: - Backlog Item

    func saveBacklogItem(_ item: BacklogItem) async throws -> CKRecord {
        let record = backlogItemRecord(from: item)
        return try await sharedDatabase.save(record)
    }

    func fetchBacklogItem(id: UUID) async throws -> BacklogItem {
        let record = try await sharedDatabase.record(for: recordID(for: id))
        return try backlogItem(from: record)
    }

    func deleteBacklogItem(id: UUID) async throws {
        _ = try await sharedDatabase.deleteRecord(withID: recordID(for: id))
    }

    /// Fetch all backlog items for a category
    func fetchBacklogItems(categoryId: UUID) async throws -> [BacklogItem] {
        let predicate = NSPredicate(
            format: "categoryId == %@",
            CKRecord.Reference(recordID: recordID(for: categoryId), action: .none)
        )
        let query = CKQuery(recordType: "BacklogItem", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let (results, _) = try await sharedDatabase.records(matching: query)
        return try results.compactMap { _, result in
            guard case let .success(record) = result else { return nil }
            return try backlogItem(from: record)
        }
    }

    /// Fetch all backlog items for a household
    func fetchBacklogItems(householdId: UUID) async throws -> [BacklogItem] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "BacklogItem", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let (results, _) = try await sharedDatabase.records(matching: query)
        return try results.compactMap { _, result in
            guard case let .success(record) = result else { return nil }
            return try backlogItem(from: record)
        }
    }

    // MARK: - Mapping

    // MARK: - Sharing

    /// Fetch raw CKRecord for household (needed for CKShare)
    func fetchHouseholdRecord(id: UUID) async throws -> CKRecord {
        try await sharedDatabase.record(for: recordID(for: id))
    }

    /// Create a CKShare for a household
    func createShare(for household: Household) async throws -> CKShare {
        let householdRecord = try await fetchHouseholdRecord(id: household.id)

        let share = CKShare(rootRecord: householdRecord)
        share[CKShare.SystemFieldKey.title] = household.name as CKRecordValue
        share.publicPermission = .none // Private - requires invitation

        let modifyOperation = CKModifyRecordsOperation(
            recordsToSave: [householdRecord, share],
            recordIDsToDelete: nil
        )
        modifyOperation.savePolicy = .changedKeys

        return try await withCheckedThrowingContinuation { continuation in
            var savedShare: CKShare?

            modifyOperation.perRecordSaveBlock = { _, result in
                if case let .success(record) = result, let ckshare = record as? CKShare {
                    savedShare = ckshare
                }
            }

            modifyOperation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let share = savedShare {
                        continuation.resume(returning: share)
                    } else {
                        continuation.resume(throwing: CloudKitManagerError.shareNotCreated)
                    }
                case let .failure(error):
                    continuation.resume(throwing: self.categorizeError(error))
                }
            }

            sharedDatabase.add(modifyOperation)
        }
    }

    /// Get share URL for inviting members
    func getShareURL(for householdId: UUID) async throws -> URL? {
        let record = try await fetchHouseholdRecord(id: householdId)
        guard let shareReference = record.share else { return nil }

        let shareRecord = try await sharedDatabase.record(for: shareReference.recordID)
        return (shareRecord as? CKShare)?.url
    }

    /// Accept a CloudKit share invitation
    func acceptShare(metadata: CKShare.Metadata) async throws {
        let acceptOperation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        acceptOperation.qualityOfService = .userInitiated

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            acceptOperation.perShareResultBlock = { _, result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: self.categorizeError(error))
                }
            }
            container.add(acceptOperation)
        }
    }

    // MARK: - Error Handling

    /// Categorize CloudKit errors into user-friendly error messages
    private func categorizeError(_ error: Error) -> CloudKitManagerError {
        guard let ckError = error as? CKError else {
            return .unknownError(error)
        }

        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .notAuthenticated:
            return .notAuthenticated
        case .quotaExceeded:
            return .quotaExceeded
        case .serverRecordChanged:
            return .serverRecordChanged
        default:
            return .unknownError(error)
        }
    }
}
