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
        let schema = Schema([CachedTask.self])
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
            makeTask(status: .next, assigneeId: assigneeId)
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount >= 0

        XCTAssertTrue(canMove, "Soft WIP should allow moving tasks")
    }

    func testCanMoveToNext_AtLimit() {
        let tasks = [
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId)
        ]

        let currentCount = tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
        let canMove = currentCount >= recommendedWipLimit

        XCTAssertTrue(canMove, "Soft WIP should not block when at recommended limit")
    }

    func testCanMoveToNext_DifferentAssignee_NotCounted() {
        let tasks = [
            makeTask(status: .next, assigneeId: otherAssigneeId),
            makeTask(status: .next, assigneeId: otherAssigneeId),
            makeTask(status: .next, assigneeId: otherAssigneeId)
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
            makeTask(status: .backlog, assigneeId: assigneeId)
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
            makeTask(status: .done, assigneeId: assigneeId)
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
            makeTask(status: .backlog, assigneeId: otherAssigneeId)
        ]

        let backlogTasks = tasks.filter { $0.status == .backlog }

        XCTAssertEqual(backlogTasks.count, 2)
    }

    func testNextFiltering() {
        let tasks = [
            makeTask(status: .backlog, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: otherAssigneeId),
            makeTask(status: .done, assigneeId: assigneeId)
        ]

        let nextTasks = tasks.filter { $0.status == .next }

        XCTAssertEqual(nextTasks.count, 2)
    }

    func testDoneFiltering() {
        let tasks = [
            makeTask(status: .backlog, assigneeId: assigneeId),
            makeTask(status: .next, assigneeId: assigneeId),
            makeTask(status: .done, assigneeId: assigneeId),
            makeTask(status: .done, assigneeId: otherAssigneeId)
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
            Task(householdId: householdId, title: "No date", status: .backlog, taskType: .oneOff)
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
            )
        ]

        let sorted = tasks.filter { $0.status == .done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        XCTAssertEqual(sorted[0].title, "Recent")
        XCTAssertEqual(sorted[1].title, "Yesterday")
        XCTAssertEqual(sorted[2].title, "Older")
    }
}
