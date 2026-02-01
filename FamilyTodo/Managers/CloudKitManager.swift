import CloudKit
import Foundation

actor CloudKitManager {
    static let shared = CloudKitManager()

    // CloudKit container identifier - matches the app's iCloud container
    #if CI
        private static let containerIdentifier = "iCloud.com.example.familytodo"
    #else
        private static let containerIdentifier = "iCloud.com.kochanowski.housepulse"
    #endif

    /// Container created on main thread during ensureReady().
    /// Using MainActor isolation for container to ensure it's created on main thread.
    @MainActor private static var _sharedContainer: CKContainer?

    private var isAvailable: Bool?
    private var isReady = false

    /// Gets the shared container, must call ensureReady() first
    private var container: CKContainer {
        get async {
            // Container should be created by ensureReady() on main thread
            await MainActor.run {
                if Self._sharedContainer == nil {
                    Self._sharedContainer = CKContainer(identifier: Self.containerIdentifier)
                }
                return Self._sharedContainer!
            }
        }
    }

    private var privateDatabase: CKDatabase {
        get async {
            await container.privateCloudDatabase
        }
    }

    private var sharedDatabase: CKDatabase {
        get async {
            await container.sharedCloudDatabase
        }
    }

    init() {
        // Container is lazily initialized on first use via ensureReady()
    }

    // MARK: - Readiness

    /// Call this after app launch to ensure CloudKit is ready.
    /// This prevents crashes when CloudKit is accessed too early during app initialization.
    /// CKContainer is created on the main thread to avoid crashes.
    func ensureReady() async {
        guard !isReady else { return }

        // Yield to let the main run loop complete initialization
        await _Concurrency.Task.yield()

        // Delay to ensure app is fully launched before accessing CloudKit.
        // CloudKit can crash with SIGTRAP if accessed during early app startup on iOS 26+.
        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Create container on main thread to avoid CloudKit crashes.
        // CKContainer init crashes on background threads during early app startup.
        await MainActor.run {
            if Self._sharedContainer == nil {
                Self._sharedContainer = CKContainer(identifier: Self.containerIdentifier)
            }
        }

        isReady = true
    }

    // MARK: - Availability Check

    /// Check if CloudKit is available before performing operations
    func checkAvailability() async throws {
        // Ensure we're ready first
        await ensureReady()

        // Return cached result if available
        if let isAvailable = self.isAvailable {
            if !isAvailable {
                throw CloudKitManagerError.notAuthenticated
            }
            return
        }

        let ckContainer = await container
        let status = try await ckContainer.accountStatus()
        let isAvailable = status == .available
        self.isAvailable = isAvailable

        if !isAvailable {
            throw CloudKitManagerError.notAuthenticated
        }
    }

    /// Reset availability cache (call when user signs in/out)
    func resetAvailabilityCache() {
        isAvailable = nil
    }

    /// Get the CloudKit container (for use with UICloudSharingController)
    func getContainer() async -> CKContainer {
        await container
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
        let db = await sharedDatabase
        return try await db.save(record)
    }

    func fetchHousehold(id: UUID) async throws -> Household {
        let db = await sharedDatabase
        let record = try await db.record(for: recordID(for: id))
        return try household(from: record)
    }

    func deleteHousehold(id: UUID) async throws {
        let db = await sharedDatabase
        _ = try await db.deleteRecord(withID: recordID(for: id))
    }

    // MARK: - Member

    func saveMember(_ member: Member) async throws -> CKRecord {
        let record = memberRecord(from: member)
        let db = await sharedDatabase
        return try await db.save(record)
    }

    func fetchMember(id: UUID) async throws -> Member {
        let db = await sharedDatabase
        let record = try await db.record(for: recordID(for: id))
        return try member(from: record)
    }

    func deleteMember(id: UUID) async throws {
        let db = await sharedDatabase
        _ = try await db.deleteRecord(withID: recordID(for: id))
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
        let db = await sharedDatabase

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

            db.add(modifyOperation)
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
        let ckContainer = await container
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
            ckContainer.add(acceptOperation)
        }
    }

    /// Accept a share using an invite code (share URL string)
    /// Returns the shared household after accepting
    func acceptShare(inviteCode: String) async throws -> Household {
        guard let shareURL = URL(string: inviteCode) else {
            throw HouseholdError.invalidInviteCode
        }

        // Fetch share metadata from the URL
        let ckContainer = await container
        let metadata = try await ckContainer.shareMetadata(for: shareURL)

        // Accept the share
        try await acceptShare(metadata: metadata)

        // After accepting, the shared records should be available in sharedDatabase
        // We need to find the household that was shared with us
        // The rootRecord of the share should be the household
        let rootRecordID = metadata.rootRecordID

        // Fetch the household from the shared database
        let db = await sharedDatabase
        let record = try await db.record(for: rootRecordID)
        return try household(from: record)
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
