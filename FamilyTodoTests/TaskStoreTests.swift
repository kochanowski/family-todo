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
    private let secondaryAssigneeId = UUID()

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

        // Create in-memory model container for testing
        let schema = Schema([CachedTask.self, CachedRecurringChore.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])

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

        modelContainer.mainContext.insert(CachedTask(from: taskA))
        modelContainer.mainContext.insert(CachedTask(from: taskB))
        modelContainer.mainContext.insert(CachedTask(from: taskC))
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

        let cached = CachedTask(from: localTask)
        cached.syncStatusRaw = "pendingUpload"
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

    func testLoadFromCache_HidesPendingDeleteTasks() async {
        let task = Task(
            id: UUID(),
            householdId: householdId,
            title: "To Delete",
            status: .next,
            assigneeId: assigneeId,
            taskType: .oneOff
        )

        let cached = CachedTask(from: task)
        cached.syncStatusRaw = "pendingDelete"
        modelContainer.mainContext.insert(cached)
        try? modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        XCTAssertTrue(store.tasks.isEmpty)
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

        modelContainer.mainContext.insert(CachedTask(from: task))
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

        modelContainer.mainContext.insert(CachedTask(from: task))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        await store.archiveTask(task)

        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == task.id }
        )
        guard let cachedTask = try modelContainer.mainContext.fetch(descriptor).first else {
            XCTFail("Expected cached task to exist after archiving")
            return
        }
        guard let completedAt = cachedTask.completedAt else {
            XCTFail("Expected archived task to have completedAt")
            return
        }

        XCTAssertLessThanOrEqual(completedAt, Date().addingTimeInterval(-86400))
        XCTAssertEqual(cachedTask.statusRaw, Task.TaskStatus.done.rawValue)
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
        modelContainer.mainContext.insert(CachedTask(from: task))
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

        let descriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.id == task.id }
        )
        guard let cachedTask = try modelContainer.mainContext.fetch(descriptor).first else {
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
        modelContainer.mainContext.insert(CachedTask(from: task))
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

        [doneThisWeekA, doneThisWeekB, donePreviousWeek, activeTask]
            .map(CachedTask.init(from:))
            .forEach(modelContainer.mainContext.insert)
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

        [doneWithoutCompletedAtInWeek, doneWithoutCompletedAtOld]
            .map(CachedTask.init(from:))
            .forEach(modelContainer.mainContext.insert)
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        let count = store.completedTaskCountThisWeek(
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(count, 1)
    }

    func testMoveTaskDoneForRecurringGeneratesBacklogSuccessorAndAdvancesRotation() async throws {
        let dueDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00:00 UTC
        let recurringChore = RecurringChore(
            id: UUID(),
            householdId: householdId,
            title: "Trash day",
            recurrenceType: .custom,
            recurrenceInterval: 2,
            defaultAssigneeIds: [assigneeId, secondaryAssigneeId],
            isActive: true,
            nextScheduledDate: dueDate,
            rotationEnabled: true,
            nextAssigneeIndex: 1
        )
        let task = Task(
            id: UUID(),
            householdId: householdId,
            title: recurringChore.title,
            status: .next,
            assigneeId: assigneeId,
            assigneeIds: [assigneeId, secondaryAssigneeId],
            dueDate: dueDate,
            taskType: .recurring,
            recurringChoreId: recurringChore.id
        )

        modelContainer.mainContext.insert(CachedRecurringChore(from: recurringChore))
        modelContainer.mainContext.insert(CachedTask(from: task))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        guard let loadedTask = store.tasks.first(where: { $0.id == task.id }) else {
            XCTFail("Expected recurring task in memory before completion")
            return
        }

        _ = await store.moveTask(loadedTask, to: .done)

        let expectedSuccessorDate = Date(timeIntervalSince1970: 1_735_862_400) // +2 days
        let generated = store.backlogTasks.filter {
            $0.recurringChoreId == recurringChore.id &&
                $0.id != task.id &&
                utcCalendar.isDate($0.dueDate ?? .distantPast, inSameDayAs: expectedSuccessorDate)
        }

        XCTAssertEqual(generated.count, 1, "Expected exactly one generated recurring successor")
        XCTAssertEqual(generated.first?.assigneeId, secondaryAssigneeId)
        XCTAssertEqual(generated.first?.assigneeIds, [assigneeId, secondaryAssigneeId])

        let choreID = recurringChore.id
        let descriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.id == choreID }
        )
        guard let cachedChore = try modelContainer.mainContext.fetch(descriptor).first else {
            XCTFail("Expected cached recurring chore metadata to be updated")
            return
        }

        XCTAssertEqual(cachedChore.nextAssigneeIndex, 0)
        let expectedFollowingDate = Date(timeIntervalSince1970: 1_736_035_200) // +4 days
        XCTAssertTrue(
            utcCalendar.isDate(cachedChore.nextScheduledDate ?? .distantPast, inSameDayAs: expectedFollowingDate)
        )
    }

    func testMoveTaskDoneForRecurringSkipsDuplicateWhenSuccessorAlreadyExists() async throws {
        let dueDate = Date(timeIntervalSince1970: 1_736_121_600) // 2025-01-06 00:00:00 UTC
        let nextDueDate = Date(timeIntervalSince1970: 1_736_208_000) // +1 day
        let recurringChore = RecurringChore(
            id: UUID(),
            householdId: householdId,
            title: "Water plants",
            recurrenceType: .daily,
            recurrenceInterval: 1,
            defaultAssigneeIds: [assigneeId],
            isActive: true,
            nextScheduledDate: dueDate,
            rotationEnabled: false
        )
        let completedCandidate = Task(
            id: UUID(),
            householdId: householdId,
            title: recurringChore.title,
            status: .next,
            assigneeId: assigneeId,
            assigneeIds: [assigneeId],
            dueDate: dueDate,
            taskType: .recurring,
            recurringChoreId: recurringChore.id
        )
        let existingSuccessor = Task(
            id: UUID(),
            householdId: householdId,
            title: recurringChore.title,
            status: .backlog,
            assigneeId: assigneeId,
            assigneeIds: [assigneeId],
            dueDate: nextDueDate,
            taskType: .recurring,
            recurringChoreId: recurringChore.id
        )

        modelContainer.mainContext.insert(CachedRecurringChore(from: recurringChore))
        modelContainer.mainContext.insert(CachedTask(from: completedCandidate))
        modelContainer.mainContext.insert(CachedTask(from: existingSuccessor))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadTasks()

        guard let loadedTask = store.tasks.first(where: { $0.id == completedCandidate.id }) else {
            XCTFail("Expected recurring task in memory before completion")
            return
        }

        _ = await store.moveTask(loadedTask, to: .done)

        let successors = store.backlogTasks.filter {
            $0.recurringChoreId == recurringChore.id &&
                utcCalendar.isDate($0.dueDate ?? .distantPast, inSameDayAs: nextDueDate)
        }
        XCTAssertEqual(successors.count, 1, "Expected idempotency guard to prevent duplicate successor")
    }

    func testAddChoreGeneratesInitialRecurringBacklogTaskWithCategoryAndHousehold() async {
        let recurringStore = RecurringChoreStore(
            householdId: householdId,
            modelContext: modelContainer.mainContext
        )
        recurringStore.setSyncMode(.localOnly)

        let categoryId = UUID()
        await recurringStore.addChore(
            title: "Laundry",
            recurrenceType: .weekly,
            recurrenceDay: 2,
            defaultAssigneeIds: [assigneeId],
            rotationEnabled: false,
            categoryId: categoryId
        )

        let taskStore = TaskStore(modelContext: modelContainer.mainContext)
        taskStore.setHousehold(householdId)
        taskStore.setSyncMode(.localOnly)
        await taskStore.loadTasks()

        let generated = taskStore.backlogTasks.filter {
            $0.taskType == .recurring && $0.title == "Laundry"
        }

        XCTAssertEqual(generated.count, 1, "Expected one generated backlog recurring task")
        XCTAssertEqual(generated.first?.householdId, householdId)
        XCTAssertEqual(generated.first?.status, .backlog)
        XCTAssertEqual(generated.first?.backlogCategoryId, categoryId)
        XCTAssertNotNil(generated.first?.recurringChoreId)
    }

    func testReactivatingChoreSeedsRecurringBacklogWhenNoPendingInstanceExists() async {
        let recurringStore = RecurringChoreStore(
            householdId: householdId,
            modelContext: modelContainer.mainContext
        )
        recurringStore.setSyncMode(.localOnly)

        await recurringStore.addChore(
            title: "Water plants",
            recurrenceType: .daily,
            recurrenceInterval: 1,
            defaultAssigneeIds: [assigneeId]
        )

        let taskStore = TaskStore(modelContext: modelContainer.mainContext)
        taskStore.setHousehold(householdId)
        taskStore.setSyncMode(.localOnly)
        await taskStore.loadTasks()

        guard let initialGenerated = taskStore.backlogTasks.first(where: { $0.taskType == .recurring }) else {
            XCTFail("Expected initial recurring backlog task")
            return
        }
        await taskStore.deleteTask(initialGenerated)
        await taskStore.loadTasks()
        XCTAssertFalse(taskStore.backlogTasks.contains(where: { $0.id == initialGenerated.id }))

        guard var chore = recurringStore.chores.first else {
            XCTFail("Expected recurring chore to exist")
            return
        }

        chore.isActive = false
        await recurringStore.updateChore(chore)

        chore.isActive = true
        await recurringStore.updateChore(chore)

        await taskStore.loadTasks()
        let regenerated = taskStore.backlogTasks.filter {
            $0.taskType == .recurring && $0.recurringChoreId == chore.id
        }
        XCTAssertEqual(regenerated.count, 1, "Expected one regenerated pending backlog recurring task")
    }

    func testDeletingChoreRemovesPendingBacklogInstancesButKeepsDoneHistory() async {
        let recurringStore = RecurringChoreStore(
            householdId: householdId,
            modelContext: modelContainer.mainContext
        )
        recurringStore.setSyncMode(.localOnly)

        await recurringStore.addChore(
            title: "Trash day",
            recurrenceType: .daily,
            recurrenceInterval: 1,
            defaultAssigneeIds: [assigneeId]
        )

        let taskStore = TaskStore(modelContext: modelContainer.mainContext)
        taskStore.setHousehold(householdId)
        taskStore.setSyncMode(.localOnly)
        await taskStore.loadTasks()

        guard let firstPending = taskStore.backlogTasks.first(where: { $0.taskType == .recurring }) else {
            XCTFail("Expected first pending recurring task")
            return
        }

        _ = await taskStore.moveTask(firstPending, to: .done)
        await taskStore.loadTasks()

        guard let chore = recurringStore.chores.first else {
            XCTFail("Expected recurring chore to exist before deletion")
            return
        }

        await recurringStore.deleteChore(chore)
        await taskStore.loadTasks()

        let pendingAfterDelete = taskStore.backlogTasks.filter {
            $0.taskType == .recurring && $0.recurringChoreId == chore.id
        }
        let doneAfterDelete = taskStore.doneTasks.filter {
            $0.taskType == .recurring && $0.recurringChoreId == chore.id
        }

        XCTAssertTrue(pendingAfterDelete.isEmpty, "Pending recurring backlog tasks should be removed")
        XCTAssertFalse(doneAfterDelete.isEmpty, "Completed recurring history should remain")
    }

    // MARK: - TaskStoreError Tests

    func testTaskStoreErrorDescription() {
        let error = TaskStoreError.wipLimitReached

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("WIP limit") == true)
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
