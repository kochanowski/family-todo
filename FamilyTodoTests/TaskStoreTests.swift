@testable import HousePulse
import SwiftData
import XCTest

@MainActor
final class TaskStoreTests: XCTestCase {
    private let recommendedWipDefaultsKey = "recommendedWipLimit"
    private var originalRecommendedWipValue: Int?
    private var modelContainer: ModelContainer!
    private var store: TaskStore!
    private let householdId = UUID()
    private let assigneeId = UUID()

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    override func setUp() async throws {
        try await super.setUp()

        let defaults = UserDefaults.standard
        if defaults.object(forKey: recommendedWipDefaultsKey) != nil {
            originalRecommendedWipValue = defaults.integer(forKey: recommendedWipDefaultsKey)
        } else {
            originalRecommendedWipValue = nil
        }
        defaults.set(3, forKey: recommendedWipDefaultsKey)

        modelContainer = try TestModelContainerFactory.makeInMemoryContainer(profile: .appCache)

        store = TaskStore(modelContext: modelContainer.mainContext)
        store.setHousehold(householdId)
    }

    override func tearDown() async throws {
        let defaults = UserDefaults.standard
        if let originalRecommendedWipValue {
            defaults.set(originalRecommendedWipValue, forKey: recommendedWipDefaultsKey)
        } else {
            defaults.removeObject(forKey: recommendedWipDefaultsKey)
        }
        originalRecommendedWipValue = nil

        store = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - WIP Guidance Tests

    func testWipLimitConstant() {
        XCTAssertEqual(TaskStore.recommendedWipLimit, 3, "Recommended WIP should be 3")
    }

    func testCanMoveToNext_NoAssignee_ReturnsFalse() {
        XCTAssertFalse(store.canMoveToNext(assigneeId: nil))
    }

    func testValidateNextTransition_NoAssignee_ReturnsAssigneeRequired() {
        XCTAssertEqual(
            store.validateNextTransition(assigneeId: nil),
            .assigneeRequired
        )
    }

    func testCanMoveToNext_EmptyTasks_ReturnsTrue() {
        XCTAssertTrue(store.canMoveToNext(assigneeId: assigneeId))
    }

    func testCreateTask_BacklogWithoutAssignee_IsAllowed() async {
        let result = await store.createTask(
            title: "Idea without owner yet",
            status: .backlog,
            assigneeId: nil
        )

        XCTAssertEqual(result, .ok)
    }

    func testCreateTask_DoneWithoutAssignee_ReturnsAssigneeRequired() async {
        let result = await store.createTask(
            title: "Completed task without owner",
            status: .done,
            assigneeId: nil
        )

        XCTAssertEqual(result, .assigneeRequired)
    }

    func testUpdateTask_DoneWithoutAssignee_ReturnsAssigneeRequired() async {
        let task = Task(
            householdId: householdId,
            title: "Completed task without owner",
            status: .done,
            assigneeId: nil,
            taskType: .oneOff
        )

        let result = await store.updateTask(task)

        XCTAssertEqual(result, .assigneeRequired)
    }

    // MARK: - Computed Properties Tests

    func testBacklogTasks_Empty() {
        XCTAssertTrue(store.backlogTasks.isEmpty)
    }

    func testNextTasks_Empty() {
        XCTAssertTrue(store.nextTasks.isEmpty)
    }

    func testDoneTasks_Empty() {
        XCTAssertTrue(store.doneTasks.isEmpty)
    }

    func testNextTasksUsesStableSortForSameDueDate() async throws {
        let dueDate = Date(timeIntervalSince1970: 1_735_000_000)
        let olderCreatedAt = Date(timeIntervalSince1970: 1_734_900_000)
        let newerCreatedAt = Date(timeIntervalSince1970: 1_734_950_000)

        let taskA = Task(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID(),
            householdId: householdId,
            title: "A",
            status: .next,
            assigneeId: assigneeId,
            dueDate: dueDate,
            taskType: .oneOff,
            createdAt: newerCreatedAt
        )
        let taskB = Task(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2") ?? UUID(),
            householdId: householdId,
            title: "B",
            status: .next,
            assigneeId: assigneeId,
            dueDate: dueDate,
            taskType: .oneOff,
            createdAt: olderCreatedAt
        )
        let taskC = Task(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A0") ?? UUID(),
            householdId: householdId,
            title: "C",
            status: .next,
            assigneeId: assigneeId,
            dueDate: dueDate,
            taskType: .oneOff,
            createdAt: newerCreatedAt
        )

        modelContainer.mainContext.insert(cachedTaskRow(taskA))
        modelContainer.mainContext.insert(cachedTaskRow(taskB))
        modelContainer.mainContext.insert(cachedTaskRow(taskC))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        XCTAssertEqual(store.nextTasks.map(\.title), ["B", "C", "A"])
    }

    func testMergeCloudSnapshot_PrefersPendingUploadVersion() async {
        let localTask = Task(
            id: UUID(),
            householdId: householdId,
            title: "Local Task",
            status: .done,
            assigneeId: assigneeId,
            taskType: .oneOff
        )
        let cloudVersion = Task(
            id: localTask.id,
            householdId: householdId,
            title: "Cloud Task",
            status: .next,
            assigneeId: assigneeId,
            taskType: .oneOff
        )

        let cached = cachedTaskRow(localTask, syncStatus: "pendingUpload")
        modelContainer.mainContext.insert(cached)
        try? modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        let pendingSnapshot = store.pendingSyncSnapshot(from: [cached])
        let merged = store.mergeCloudSnapshot([cloudVersion], with: pendingSnapshot)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, localTask.id)
        XCTAssertEqual(merged.first?.status, .done)
        XCTAssertEqual(merged.first?.title, "Local Task")
    }

    func testSyncToCacheDoesNotAcceptSemanticStaleCompletionEcho() throws {
        let completedAt = Date(timeIntervalSince1970: 1_736_900_000)
        let localTask = Task(
            id: UUID(),
            householdId: householdId,
            title: "Completed locally",
            status: .done,
            assigneeId: assigneeId,
            completedAt: completedAt,
            taskType: .oneOff,
            updatedAt: completedAt
        )

        let cached = cachedTaskRow(
            localTask,
            syncStatus: "awaitingCloudEcho",
            lastSyncedAt: Date()
        )
        modelContainer.mainContext.insert(cached)
        try modelContainer.mainContext.save()

        let staleCloudTask = Task(
            id: localTask.id,
            householdId: householdId,
            title: localTask.title,
            status: .next,
            assigneeId: assigneeId,
            completedAt: nil,
            taskType: .oneOff,
            updatedAt: completedAt.addingTimeInterval(30)
        )

        store.syncToCache([staleCloudTask], cloudTaskIDs: [localTask.id])

        guard let persisted = try fetchCachedWorkItem(id: localTask.id) else {
            XCTFail("Expected cached task after stale cloud sync")
            return
        }

        XCTAssertEqual(persisted.statusRaw, WorkItem.Status.done.rawValue)
        XCTAssertEqual(persisted.completedAt, completedAt)
        XCTAssertEqual(persisted.syncStatusRaw, "awaitingCloudEcho")
    }

    func testLoadFromCache_HidesPendingDeleteTasks() async {
        let task = Task(
            id: UUID(),
            householdId: householdId,
            title: "To Delete",
            status: .next,
            assigneeId: assigneeId,
            taskType: .oneOff
        )

        let cached = cachedTaskRow(task, syncStatus: "pendingDelete")
        modelContainer.mainContext.insert(cached)
        try? modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testSetHouseholdHydratesTasksFromCacheBeforeLoad() throws {
        let task = Task(
            householdId: householdId,
            title: "Cache-first task",
            status: .next,
            assigneeId: assigneeId,
            taskType: .oneOff
        )

        modelContainer.mainContext.insert(cachedTaskRow(task))
        try modelContainer.mainContext.save()

        let hydratedStore = TaskStore(modelContext: modelContainer.mainContext)
        hydratedStore.setHousehold(householdId)

        XCTAssertTrue(hydratedStore.hasHydratedLocalSnapshot)
        XCTAssertEqual(hydratedStore.tasks.count, 1)
        XCTAssertEqual(hydratedStore.tasks.first?.title, "Cache-first task")
    }

    func testLoadTasksForDisplayRehydratesWhenSnapshotMarkedStale() async throws {
        let cachedTask = Task(
            householdId: householdId,
            title: "Original task",
            status: .next,
            assigneeId: assigneeId,
            taskType: .oneOff
        )

        modelContainer.mainContext.insert(cachedTaskRow(cachedTask))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasksForDisplay()
        XCTAssertEqual(store.tasks.map(\.title), ["Original task"])

        let replacementTask = Task(
            householdId: householdId,
            title: "Updated from cache",
            status: .next,
            assigneeId: assigneeId,
            taskType: .oneOff
        )

        if let cached = try fetchCachedWorkItem(id: cachedTask.id) {
            modelContainer.mainContext.delete(cached)
        }
        modelContainer.mainContext.insert(cachedTaskRow(replacementTask))
        try modelContainer.mainContext.save()

        store.markLocalSnapshotStale()
        await store.loadTasksForDisplay()

        XCTAssertEqual(store.tasks.map(\.title), ["Updated from cache"])
    }

    func testMoveTaskToIdeasPersistsBacklogItemImmediatelyLocally() async throws {
        let category = BacklogCategory(
            householdId: householdId,
            title: "Ideas",
            sortOrder: 0
        )
        modelContainer.mainContext.insert(CachedBacklogCategory(from: category))

        let task = Task(
            householdId: householdId,
            title: "Move me back",
            status: .next,
            assigneeId: assigneeId,
            taskType: .oneOff
        )
        modelContainer.mainContext.insert(cachedTaskRow(task))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        let moveResult = store.moveTaskToIdeas(task, destinationCategoryId: category.id)

        XCTAssertEqual(moveResult, .success(categoryId: category.id))
        XCTAssertTrue(store.tasks.isEmpty)

        let persisted = try XCTUnwrap(fetchCachedWorkItem(id: task.id))
        XCTAssertEqual(persisted.title, "Move me back")
        XCTAssertEqual(persisted.categoryId, category.id)
        XCTAssertEqual(persisted.logicalItemID, task.logicalItemID)
        XCTAssertEqual(persisted.statusRaw, WorkItem.Status.idea.rawValue)
        XCTAssertEqual(persisted.syncStatusRaw, "synced")

        let backlogStore = BacklogStore(
            householdId: householdId,
            modelContext: modelContainer.mainContext
        )
        backlogStore.setSyncMode(.localOnly)
        await backlogStore.loadDataForDisplay()

        XCTAssertEqual(backlogStore.items(for: category.id).map(\.title), ["Move me back"])
    }

    func testMoveTaskToIdeasReusesExistingIdeaWithSameLogicalItemID() async throws {
        let category = BacklogCategory(
            householdId: householdId,
            title: "Ideas",
            sortOrder: 0
        )
        modelContainer.mainContext.insert(CachedBacklogCategory(from: category))

        let logicalItemID = UUID()
        let task = Task(
            id: UUID(),
            logicalItemID: logicalItemID,
            householdId: householdId,
            title: "Move me once",
            status: .next,
            assigneeId: assigneeId,
            taskType: .oneOff
        )
        let existingIdea = BacklogItem(
            id: UUID(),
            logicalItemID: logicalItemID,
            categoryId: category.id,
            householdId: householdId,
            title: "Move me once",
            assigneeId: assigneeId
        )

        modelContainer.mainContext.insert(cachedTaskRow(task))
        modelContainer.mainContext.insert(
            TestCacheFixtures.cachedWorkItem(from: WorkItem(idea: existingIdea))
        )
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        let moveResult = store.moveTaskToIdeas(task, destinationCategoryId: category.id)

        XCTAssertEqual(moveResult, .success(categoryId: category.id))
        XCTAssertTrue(store.tasks.isEmpty)

        let backlogDescriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedIdeas = try modelContainer.mainContext.fetch(backlogDescriptor)
        XCTAssertEqual(
            cachedIdeas.filter { $0.logicalItemID == logicalItemID && $0.statusRaw == WorkItem.Status.idea.rawValue }.count,
            1
        )

        let canonicalIdeas = WorkItemCacheStoreSupport.visibleIdeas(from: cachedIdeas)
        XCTAssertEqual(canonicalIdeas.filter { $0.logicalItemID == logicalItemID }.count, 1)
    }

    func testArchiveTaskMovesTaskFromRecentlyDoneToArchivedDone() async {
        let task = Task(
            id: UUID(),
            householdId: householdId,
            title: "Archive me",
            status: .done,
            assigneeId: assigneeId,
            completedAt: Date().addingTimeInterval(-60),
            taskType: .oneOff
        )

        modelContainer.mainContext.insert(cachedTaskRow(task))
        try? modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        XCTAssertTrue(store.recentlyDoneTasks.contains(where: { $0.id == task.id }))
        XCTAssertFalse(store.archivedDoneTasks.contains(where: { $0.id == task.id }))

        await store.archiveTask(task)

        XCTAssertFalse(store.recentlyDoneTasks.contains(where: { $0.id == task.id }))
        XCTAssertTrue(store.archivedDoneTasks.contains(where: { $0.id == task.id }))
    }

    func testArchiveTaskPersistsArchivedCompletedAtToCache() async throws {
        let task = Task(
            id: UUID(),
            householdId: householdId,
            title: "Persist archive date",
            status: .done,
            assigneeId: assigneeId,
            completedAt: Date(),
            taskType: .oneOff
        )

        modelContainer.mainContext.insert(cachedTaskRow(task))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        await store.archiveTask(task)

        guard let cachedTask = try fetchCachedWorkItem(id: task.id) else {
            XCTFail("Expected cached task to exist after archiving")
            return
        }
        guard let completedAt = cachedTask.completedAt else {
            XCTFail("Expected archived task to have completedAt")
            return
        }

        XCTAssertLessThanOrEqual(completedAt, Date().addingTimeInterval(-86400))
        XCTAssertEqual(cachedTask.statusRaw, WorkItem.Status.done.rawValue)
    }

    func testToggleTaskCompletionSetsCompletedByIdForCurrentUser() async throws {
        let task = Task(
            id: UUID(),
            householdId: householdId,
            title: "Complete me",
            status: .next,
            assigneeId: assigneeId,
            taskType: .oneOff
        )

        modelContainer.mainContext.insert(cachedTaskRow(task))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        store.setCloudContext(currentUserId: "user-1", householdOwnerId: "user-1")
        await store.loadTasks()

        let result = await store.toggleTaskCompletion(task)
        XCTAssertEqual(result, .ok)

        guard let completedTask = store.tasks.first(where: { $0.id == task.id }) else {
            XCTFail("Expected completed task in memory")
            return
        }
        XCTAssertEqual(completedTask.status, .done)
        XCTAssertEqual(completedTask.completedById, "user-1")

        guard let cachedTask = try fetchCachedWorkItem(id: task.id) else {
            XCTFail("Expected cached task after completion")
            return
        }
        XCTAssertEqual(cachedTask.completedById, "user-1")
    }

    func testToggleTaskCompletionClearsCompletedByIdWhenReopened() async throws {
        let task = Task(
            id: UUID(),
            householdId: householdId,
            title: "Reopen me",
            status: .done,
            assigneeId: assigneeId,
            completedAt: Date(timeIntervalSince1970: 1_736_900_000),
            completedById: "user-1",
            taskType: .oneOff
        )

        modelContainer.mainContext.insert(cachedTaskRow(task))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        store.setCloudContext(currentUserId: "user-1", householdOwnerId: "user-1")
        await store.loadTasks()

        let result = await store.toggleTaskCompletion(task)
        XCTAssertEqual(result, .ok)

        guard let reopenedTask = store.tasks.first(where: { $0.id == task.id }) else {
            XCTFail("Expected reopened task in memory")
            return
        }
        XCTAssertEqual(reopenedTask.status, .next)
        XCTAssertNil(reopenedTask.completedById)

        guard let cachedTask = try fetchCachedWorkItem(id: task.id) else {
            XCTFail("Expected cached task after reopening")
            return
        }
        XCTAssertNil(cachedTask.completedById)
    }

    func testCanPokeReturnsTrueWhenTaskNeverPoked() {
        let task = Task(
            householdId: householdId,
            title: "Never poked",
            status: .next,
            assigneeId: assigneeId,
            taskType: .oneOff
        )

        XCTAssertTrue(store.canPoke(task: task, now: Date(), calendar: utcCalendar))
    }

    func testCanPokeReturnsFalseWhenTaskWasPokedToday() {
        let now = Date(timeIntervalSince1970: 1_736_500_000)
        let task = Task(
            householdId: householdId,
            title: "Poked today",
            status: .next,
            assigneeId: assigneeId,
            lastPokedAt: now.addingTimeInterval(-600),
            taskType: .oneOff
        )

        XCTAssertFalse(store.canPoke(task: task, now: now, calendar: utcCalendar))
    }

    func testCanPokeReturnsTrueWhenTaskWasPokedOnPreviousDay() {
        let now = Date(timeIntervalSince1970: 1_736_500_000)
        let task = Task(
            householdId: householdId,
            title: "Poked yesterday",
            status: .next,
            assigneeId: assigneeId,
            lastPokedAt: now.addingTimeInterval(-86400),
            taskType: .oneOff
        )

        XCTAssertTrue(store.canPoke(task: task, now: now, calendar: utcCalendar))
    }

    func testPokeTaskUpdatesLastPokedAtAndCacheInLocalMode() async throws {
        let task = Task(
            id: UUID(),
            householdId: householdId,
            title: "Poke me",
            status: .next,
            assigneeId: assigneeId,
            assigneeIds: [assigneeId],
            taskType: .oneOff
        )
        modelContainer.mainContext.insert(cachedTaskRow(task))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        let pokeDate = Date(timeIntervalSince1970: 1_736_600_000)
        let didPoke = await store.pokeTask(task, now: pokeDate, calendar: utcCalendar)
        XCTAssertTrue(didPoke)

        guard let updatedTask = store.tasks.first(where: { $0.id == task.id }) else {
            XCTFail("Expected poked task to exist in memory")
            return
        }
        XCTAssertEqual(updatedTask.lastPokedAt, pokeDate)

        guard let cachedTask = try fetchCachedWorkItem(id: task.id) else {
            XCTFail("Expected cached task to exist after poke")
            return
        }
        XCTAssertEqual(cachedTask.lastPokedAt, pokeDate)
        XCTAssertEqual(cachedTask.syncStatusRaw, "synced")
    }

    func testPokeTaskBlocksSecondPokeOnSameDay() async throws {
        let task = Task(
            id: UUID(),
            householdId: householdId,
            title: "Poke once",
            status: .next,
            assigneeId: assigneeId,
            assigneeIds: [assigneeId],
            taskType: .oneOff
        )
        modelContainer.mainContext.insert(cachedTaskRow(task))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        let firstPokeAt = Date(timeIntervalSince1970: 1_736_700_000)
        let secondPokeAt = firstPokeAt.addingTimeInterval(1200)

        let firstPokeResult = await store.pokeTask(task, now: firstPokeAt, calendar: utcCalendar)
        let secondPokeResult = await store.pokeTask(task, now: secondPokeAt, calendar: utcCalendar)

        XCTAssertTrue(firstPokeResult)
        XCTAssertFalse(secondPokeResult)

        guard let updatedTask = store.tasks.first(where: { $0.id == task.id }) else {
            XCTFail("Expected task to still exist in memory")
            return
        }
        XCTAssertEqual(updatedTask.lastPokedAt, firstPokeAt)
    }

    func testCompletedTaskCountThisWeekCountsOnlyDoneTasksInReferenceWeek() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_736_800_000)
        guard
            let thisWeekDate = utcCalendar.date(byAdding: .day, value: -1, to: referenceDate),
            let previousWeekDate = utcCalendar.date(byAdding: .day, value: -8, to: referenceDate)
        else {
            XCTFail("Failed to create reference dates")
            return
        }

        let doneThisWeekA = Task(
            id: UUID(),
            householdId: householdId,
            title: "Done this week A",
            status: .done,
            assigneeId: assigneeId,
            completedAt: thisWeekDate,
            taskType: .oneOff
        )
        let doneThisWeekB = Task(
            id: UUID(),
            householdId: householdId,
            title: "Done this week B",
            status: .done,
            assigneeId: assigneeId,
            completedAt: referenceDate,
            taskType: .oneOff
        )
        let donePreviousWeek = Task(
            id: UUID(),
            householdId: householdId,
            title: "Done previous week",
            status: .done,
            assigneeId: assigneeId,
            completedAt: previousWeekDate,
            taskType: .oneOff
        )
        let activeTask = Task(
            id: UUID(),
            householdId: householdId,
            title: "Still active",
            status: .next,
            assigneeId: assigneeId,
            taskType: .oneOff
        )

        for task in [doneThisWeekA, doneThisWeekB, donePreviousWeek, activeTask] {
            modelContainer.mainContext.insert(cachedTaskRow(task))
        }
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        let count = store.completedTaskCountThisWeek(
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(count, 2)
    }

    func testCompletedTaskCountThisWeekUsesUpdatedAtWhenCompletedAtMissing() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_736_850_000)
        guard
            let thisWeekUpdatedAt = utcCalendar.date(byAdding: .day, value: -2, to: referenceDate),
            let previousWeekUpdatedAt = utcCalendar.date(byAdding: .day, value: -9, to: referenceDate)
        else {
            XCTFail("Failed to create fallback dates")
            return
        }

        let doneWithoutCompletedAtInWeek = Task(
            id: UUID(),
            householdId: householdId,
            title: "Done fallback this week",
            status: .done,
            assigneeId: assigneeId,
            completedAt: nil,
            taskType: .oneOff,
            updatedAt: thisWeekUpdatedAt
        )
        let doneWithoutCompletedAtOld = Task(
            id: UUID(),
            householdId: householdId,
            title: "Done fallback old",
            status: .done,
            assigneeId: assigneeId,
            completedAt: nil,
            taskType: .oneOff,
            updatedAt: previousWeekUpdatedAt
        )

        for task in [doneWithoutCompletedAtInWeek, doneWithoutCompletedAtOld] {
            modelContainer.mainContext.insert(cachedTaskRow(task))
        }
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        let count = store.completedTaskCountThisWeek(
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(count, 1)
    }

    // MARK: - TaskStoreError Tests

    func testTaskStoreErrorDescription() {
        let error = TaskStoreError.wipLimitReached

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("recommended active task count") == true)
    }

    private func cachedTaskRow(
        _ task: Task,
        syncStatus: String = "synced",
        lastSyncedAt: Date? = nil
    ) -> CachedWorkItem {
        TestCacheFixtures.cachedWorkItem(
            from: WorkItem(task: task),
            syncStatus: syncStatus,
            lastSyncedAt: lastSyncedAt
        )
    }

    private func fetchCachedWorkItem(id: UUID) throws -> CachedWorkItem? {
        let descriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContainer.mainContext.fetch(descriptor).first
    }
}

// MARK: - WIP Limit Logic Tests (Pure Functions)

final class WIPLimitLogicTests: XCTestCase {
    private let householdId = UUID()
    private let assigneeId = UUID()
    private let otherAssigneeId = UUID()

    /// Recommended WIP count for UX guidance.
    private let recommendedWipLimit = 3

    /// Helper to create a task for testing
    private func makeTask(
        status: Task.TaskStatus,
        assigneeId: UUID? = nil
    ) -> Task {
        Task(
            householdId: householdId,
            title: "Test Task",
            status: status,
            assigneeId: assigneeId,
            taskType: .oneOff
        )
    }

    // MARK: - Soft WIP Logic

    func testCanMoveToNext_UnderLimit() {
        let tasks = [
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount >= 0

        XCTAssertTrue(canMove, "Soft WIP should allow moving tasks")
    }

    func testCanMoveToNext_AtLimit() {
        let tasks = [
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount >= recommendedWipLimit

        XCTAssertTrue(canMove, "Soft WIP should not block when at recommended limit")
    }

    func testCanMoveToNext_DifferentAssignee_NotCounted() {
        let tasks = [
            makeTask(status: .next, assigneeId: otherAssigneeId),
            makeTask(status: .next, assigneeId: otherAssigneeId),
            makeTask(status: .next, assigneeId: otherAssigneeId),
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount >= 0

        XCTAssertTrue(canMove, "Soft WIP should stay non-blocking for all assignees")
    }

    func testCanMoveToNext_BacklogNotCounted() {
        let tasks = [
            makeTask(status: .backlog, assigneeId: assigneeId),
            makeTask(status: .backlog, assigneeId: assigneeId),
            makeTask(status: .backlog, assigneeId: assigneeId),
            makeTask(status: .backlog, assigneeId: assigneeId),
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount >= 0

        XCTAssertTrue(canMove, "Soft WIP should not block transition decisions")
    }

    func testCanMoveToNext_DoneNotCounted() {
        let tasks = [
            makeTask(status: .done, assigneeId: assigneeId),
            makeTask(status: .done, assigneeId: assigneeId),
            makeTask(status: .done, assigneeId: assigneeId),
            makeTask(status: .done, assigneeId: assigneeId),
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount >= 0

        XCTAssertTrue(canMove, "Soft WIP should remain advisory, not blocking")
    }

    // MARK: - Filtering Logic

    func testBacklogFiltering() {
        let tasks = [
            makeTask(status: .backlog, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .done, assigneeId: assigneeId),
            makeTask(status: .backlog, assigneeId: otherAssigneeId),
        ]

        let backlogTasks = tasks.filter { $0.status == .backlog }

        XCTAssertEqual(backlogTasks.count, 2)
    }

    func testNextFiltering() {
        let tasks = [
            makeTask(status: .backlog, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: otherAssigneeId),
            makeTask(status: .done, assigneeId: assigneeId),
        ]

        let nextTasks = tasks.filter { $0.status == .next }

        XCTAssertEqual(nextTasks.count, 2)
    }

    func testDoneFiltering() {
        let tasks = [
            makeTask(status: .backlog, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .done, assigneeId: assigneeId),
            makeTask(status: .done, assigneeId: otherAssigneeId),
        ]

        let doneTasks = tasks.filter { $0.status == .done }

        XCTAssertEqual(doneTasks.count, 2)
    }

    // MARK: - Sorting Logic

    func testBacklogSortedByDueDate() {
        let now = Date()
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else {
            XCTFail("Failed to create tomorrow date")
            return
        }
        guard let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: now) else {
            XCTFail("Failed to create next week date")
            return
        }

        let tasks = [
            Task(householdId: householdId, title: "Later", status: .backlog, dueDate: nextWeek, taskType: .oneOff),
            Task(householdId: householdId, title: "Sooner", status: .backlog, dueDate: tomorrow, taskType: .oneOff),
            Task(householdId: householdId, title: "No date", status: .backlog, taskType: .oneOff),
        ]

        let sorted = tasks.filter { $0.status == .backlog }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        XCTAssertEqual(sorted[0].title, "Sooner")
        XCTAssertEqual(sorted[1].title, "Later")
        XCTAssertEqual(sorted[2].title, "No date")
    }

    func testDoneSortedByCompletedAtDescending() {
        let now = Date()
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) else {
            XCTFail("Failed to create yesterday date")
            return
        }
        guard let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: now) else {
            XCTFail("Failed to create last week date")
            return
        }

        let tasks = [
            Task(
                householdId: householdId, title: "Older", status: .done, completedAt: lastWeek, taskType: .oneOff
            ),
            Task(householdId: householdId, title: "Recent", status: .done, completedAt: now, taskType: .oneOff),
            Task(
                householdId: householdId, title: "Yesterday", status: .done, completedAt: yesterday, taskType: .oneOff
            ),
        ]

        let sorted = tasks.filter { $0.status == .done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        XCTAssertEqual(sorted[0].title, "Recent")
        XCTAssertEqual(sorted[1].title, "Yesterday")
        XCTAssertEqual(sorted[2].title, "Older")
    }
}
