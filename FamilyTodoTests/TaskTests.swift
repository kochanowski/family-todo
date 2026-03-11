@testable import HousePulse
import XCTest

final class TaskTests: XCTestCase {
    private let householdId = UUID()

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

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
        XCTAssertNil(task.lastPokedAt)
        XCTAssertNil(task.completedAt)
    }

    func testTaskWithAllFields() {
        let assigneeId = UUID()
        let areaId = UUID()
        let dueDate = Date()
        let lastPokedAt = Date().addingTimeInterval(-300)

        let task = Task(
            householdId: householdId,
            title: "Complete Task",
            status: .next,
            assigneeId: assigneeId,
            assigneeIds: [assigneeId],
            areaId: areaId,
            dueDate: dueDate,
            lastPokedAt: lastPokedAt,
            taskType: .recurring,
            notes: "Test notes"
        )

        XCTAssertEqual(task.assigneeId, assigneeId)
        XCTAssertEqual(task.assigneeIds, [assigneeId])
        XCTAssertEqual(task.areaId, areaId)
        XCTAssertEqual(task.dueDate, dueDate)
        XCTAssertEqual(task.lastPokedAt, lastPokedAt)
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
        guard let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) else {
            XCTFail("Failed to create future date")
            return
        }

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
        guard let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else {
            XCTFail("Failed to create past date")
            return
        }

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
        guard let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else {
            XCTFail("Failed to create past date")
            return
        }

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
        let pokeDate = Date(timeIntervalSince1970: 1_736_000_000)
        let originalTask = Task(
            householdId: householdId,
            title: "Codable Test",
            status: .next,
            dueDate: Date(),
            lastPokedAt: pokeDate,
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
        XCTAssertEqual(originalTask.lastPokedAt, decodedTask.lastPokedAt)
    }

    func testCachedTaskRoundTripPreservesLastPokedAt() {
        let pokeDate = Date(timeIntervalSince1970: 1_736_111_000)
        let originalTask = Task(
            householdId: householdId,
            title: "Cache Roundtrip",
            status: .next,
            lastPokedAt: pokeDate,
            taskType: .oneOff
        )

        let cached = CachedTask(from: originalTask)
        let roundTrip = cached.toTask()

        XCTAssertEqual(roundTrip.lastPokedAt, pokeDate)
    }

    func testCloudKitMappingRoundTripPreservesLastPokedAt() async throws {
        let pokeDate = Date(timeIntervalSince1970: 1_736_222_000)
        let originalTask = Task(
            householdId: householdId,
            title: "Cloud Roundtrip",
            status: .next,
            lastPokedAt: pokeDate,
            taskType: .oneOff
        )

        let manager = CloudKitManager.shared
        let record = await manager.taskRecord(from: originalTask)
        let roundTrip = try await manager.task(from: record)

        XCTAssertEqual(roundTrip.lastPokedAt, pokeDate)
    }

    func testCloudKitMappingKeepsLastPokedAtNilWhenMissing() async throws {
        let originalTask = Task(
            householdId: householdId,
            title: "Cloud Nil",
            status: .next,
            lastPokedAt: nil,
            taskType: .oneOff
        )

        let manager = CloudKitManager.shared
        let record = await manager.taskRecord(from: originalTask)
        let roundTrip = try await manager.task(from: record)

        XCTAssertNil(record["lastPokedAt"])
        XCTAssertNil(roundTrip.lastPokedAt)
    }

    func testDueDateHasExplicitTimeTreatsMidnightAsAllDay() {
        let calendar = utcCalendar
        let dueDate = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 11, hour: 0, minute: 0)
        ) ?? Date()

        XCTAssertFalse(Task.dueDateHasExplicitTime(dueDate, calendar: calendar))
    }

    func testDueDateHasExplicitTimeDetectsClockTime() {
        let calendar = utcCalendar
        let dueDate = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 11, hour: 14, minute: 30)
        ) ?? Date()

        XCTAssertTrue(Task.dueDateHasExplicitTime(dueDate, calendar: calendar))
    }

    func testTaskReminderDateUsesDefaultTimeForAllDayTasks() {
        let calendar = utcCalendar
        let dueDate = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 13, hour: 0, minute: 0)
        ) ?? Date()
        let defaultReminderTime = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 1, hour: 8, minute: 45)
        ) ?? Date()

        let reminderDate = NotificationSchedulePlanner.taskReminderDate(
            for: dueDate,
            defaultReminderTime: defaultReminderTime,
            calendar: calendar
        )

        XCTAssertEqual(
            reminderDate,
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 13, hour: 8, minute: 45))
        )
    }

    func testDailyDigestPlanSkipsWhenNoTasksAreDue() {
        let calendar = utcCalendar
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 11, hour: 7, minute: 0)
        ) ?? Date()
        let reminderTime = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 1, hour: 8, minute: 0)
        ) ?? Date()

        let plan = NotificationSchedulePlanner.dailyDigestPlan(
            tasks: [],
            now: now,
            reminderTime: reminderTime,
            calendar: calendar
        )

        XCTAssertNil(plan)
    }

    func testDailyDigestPlanCountsTasksForNextDigestDayOnly() {
        let calendar = utcCalendar
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 11, hour: 21, minute: 0)
        ) ?? Date()
        let reminderTime = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 1, hour: 8, minute: 0)
        ) ?? Date()
        let tomorrowDueDate = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 12, hour: 0, minute: 0)
        ) ?? Date()
        let todayDueDate = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 11, hour: 0, minute: 0)
        ) ?? Date()

        let tomorrowTask = Task(
            householdId: householdId,
            title: "Tomorrow",
            status: .next,
            dueDate: tomorrowDueDate,
            taskType: .oneOff
        )
        let completedTomorrowTask = Task(
            householdId: householdId,
            title: "Done Tomorrow",
            status: .done,
            dueDate: tomorrowDueDate,
            completedAt: now,
            taskType: .oneOff
        )
        let todayTask = Task(
            householdId: householdId,
            title: "Today",
            status: .next,
            dueDate: todayDueDate,
            taskType: .oneOff
        )

        let plan = NotificationSchedulePlanner.dailyDigestPlan(
            tasks: [tomorrowTask, completedTomorrowTask, todayTask],
            now: now,
            reminderTime: reminderTime,
            calendar: calendar
        )

        XCTAssertEqual(plan?.dueCount, 1)
        XCTAssertEqual(
            plan?.fireDate,
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 8, minute: 0))
        )
        XCTAssertEqual(plan?.body, "You have 1 task due today.")
    }
}
