@testable import FamilyTodo
import SwiftData
import XCTest

@MainActor
final class TaskStoreTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var store: TaskStore!
    private let householdId = UUID()
    private let assigneeId = UUID()

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container for testing
        let schema = Schema([CachedTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])

        store = TaskStore(modelContext: modelContainer.mainContext)
        store.setHousehold(householdId)
    }

    override func tearDown() async throws {
        store = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - WIP Limit Tests

    func testWipLimitConstant() {
        XCTAssertEqual(TaskStore.wipLimit, 3, "WIP limit should be 3")
    }

    func testCanMoveToNext_NoAssignee_ReturnsTrue() {
        XCTAssertTrue(store.canMoveToNext(assigneeId: nil))
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

    // MARK: - TaskStoreError Tests

    func testTaskStoreErrorDescription() {
        let error = TaskStoreError.wipLimitReached

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("WIP limit"))
    }
}

// MARK: - WIP Limit Logic Tests (Pure Functions)

final class WIPLimitLogicTests: XCTestCase {
    private let householdId = UUID()
    private let assigneeId = UUID()
    private let otherAssigneeId = UUID()

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

    // MARK: - canMoveToNext Logic

    func testCanMoveToNext_UnderLimit() {
        let tasks = [
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount < TaskStore.wipLimit

        XCTAssertTrue(canMove, "Should be able to move when under WIP limit")
    }

    func testCanMoveToNext_AtLimit() {
        let tasks = [
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount < TaskStore.wipLimit

        XCTAssertFalse(canMove, "Should not be able to move when at WIP limit")
    }

    func testCanMoveToNext_DifferentAssignee_NotCounted() {
        let tasks = [
            makeTask(status: .next, assigneeId: otherAssigneeId),
            makeTask(status: .next, assigneeId: otherAssigneeId),
            makeTask(status: .next, assigneeId: otherAssigneeId),
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount < TaskStore.wipLimit

        XCTAssertTrue(canMove, "Other assignee's tasks should not count towards WIP limit")
    }

    func testCanMoveToNext_BacklogNotCounted() {
        let tasks = [
            makeTask(status: .backlog, assigneeId: assigneeId),
            makeTask(status: .backlog, assigneeId: assigneeId),
            makeTask(status: .backlog, assigneeId: assigneeId),
            makeTask(status: .backlog, assigneeId: assigneeId),
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount < TaskStore.wipLimit

        XCTAssertTrue(canMove, "Backlog tasks should not count towards WIP limit")
    }

    func testCanMoveToNext_DoneNotCounted() {
        let tasks = [
            makeTask(status: .done, assigneeId: assigneeId),
            makeTask(status: .done, assigneeId: assigneeId),
            makeTask(status: .done, assigneeId: assigneeId),
            makeTask(status: .done, assigneeId: assigneeId),
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount < TaskStore.wipLimit

        XCTAssertTrue(canMove, "Done tasks should not count towards WIP limit")
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
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: now)!

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
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: now)!

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
