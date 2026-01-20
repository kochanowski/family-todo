@testable import FamilyTodo
import XCTest

final class TaskTests: XCTestCase {
    private let householdId = UUID()

    // MARK: - Initialization Tests

    func testTaskInitialization() {
        let task = Task(
            householdId: householdId,
            title: "Test Task",
            status: .backlog,
            taskType: .oneOff
        )

        XCTAssertEqual(task.title, "Test Task")
        XCTAssertEqual(task.status, .backlog)
        XCTAssertEqual(task.householdId, householdId)
        XCTAssertEqual(task.taskType, .oneOff)
        XCTAssertNil(task.assigneeId)
        XCTAssertTrue(task.assigneeIds.isEmpty)
        XCTAssertNil(task.areaId)
        XCTAssertNil(task.dueDate)
        XCTAssertNil(task.completedAt)
    }

    func testTaskWithAllFields() {
        let assigneeId = UUID()
        let areaId = UUID()
        let dueDate = Date()

        let task = Task(
            householdId: householdId,
            title: "Complete Task",
            status: .next,
            assigneeId: assigneeId,
            assigneeIds: [assigneeId],
            areaId: areaId,
            dueDate: dueDate,
            taskType: .recurring,
            notes: "Test notes"
        )

        XCTAssertEqual(task.assigneeId, assigneeId)
        XCTAssertEqual(task.assigneeIds, [assigneeId])
        XCTAssertEqual(task.areaId, areaId)
        XCTAssertEqual(task.dueDate, dueDate)
        XCTAssertEqual(task.notes, "Test notes")
        XCTAssertEqual(task.taskType, .recurring)
    }

    // MARK: - isOverdue Tests

    func testIsOverdue_NoDueDate_ReturnsFalse() {
        let task = Task(
            householdId: householdId,
            title: "No Due Date",
            status: .backlog,
            taskType: .oneOff
        )

        XCTAssertFalse(task.isOverdue)
    }

    func testIsOverdue_FutureDueDate_ReturnsFalse() {
        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!

        let task = Task(
            householdId: householdId,
            title: "Future Task",
            status: .next,
            dueDate: futureDate,
            taskType: .oneOff
        )

        XCTAssertFalse(task.isOverdue)
    }

    func testIsOverdue_PastDueDate_ReturnsTrue() {
        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let task = Task(
            householdId: householdId,
            title: "Overdue Task",
            status: .backlog,
            dueDate: pastDate,
            taskType: .oneOff
        )

        XCTAssertTrue(task.isOverdue)
    }

    func testIsOverdue_DoneTask_ReturnsFalse() {
        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let task = Task(
            householdId: householdId,
            title: "Done Overdue Task",
            status: .done,
            dueDate: pastDate,
            completedAt: Date(),
            taskType: .oneOff
        )

        XCTAssertFalse(task.isOverdue, "Completed tasks should not be marked as overdue")
    }

    // MARK: - Status Tests

    func testTaskStatusRawValues() {
        XCTAssertEqual(Task.TaskStatus.backlog.rawValue, "backlog")
        XCTAssertEqual(Task.TaskStatus.next.rawValue, "next")
        XCTAssertEqual(Task.TaskStatus.done.rawValue, "done")
    }

    func testTaskTypeRawValues() {
        XCTAssertEqual(Task.TaskType.oneOff.rawValue, "one-off")
        XCTAssertEqual(Task.TaskType.recurring.rawValue, "recurring")
    }

    // MARK: - Codable Tests

    func testTaskEncodingDecoding() throws {
        let originalTask = Task(
            householdId: householdId,
            title: "Codable Test",
            status: .next,
            dueDate: Date(),
            taskType: .oneOff,
            notes: "Test encoding"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalTask)

        let decoder = JSONDecoder()
        let decodedTask = try decoder.decode(Task.self, from: data)

        XCTAssertEqual(originalTask.id, decodedTask.id)
        XCTAssertEqual(originalTask.title, decodedTask.title)
        XCTAssertEqual(originalTask.status, decodedTask.status)
        XCTAssertEqual(originalTask.notes, decodedTask.notes)
    }
}
