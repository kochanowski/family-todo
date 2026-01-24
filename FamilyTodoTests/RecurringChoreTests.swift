@testable import HousePulse
import XCTest

final class RecurringChoreTests: XCTestCase {
    private let householdId = UUID()
    private let calendar = Calendar.current

    // MARK: - Initialization Tests

    func testRecurringChoreInitialization() {
        let chore = RecurringChore(
            householdId: householdId,
            title: "Weekly Cleaning",
            recurrenceType: .weekly,
            recurrenceDay: 2 // Monday
        )

        XCTAssertEqual(chore.title, "Weekly Cleaning")
        XCTAssertEqual(chore.recurrenceType, .weekly)
        XCTAssertEqual(chore.recurrenceDay, 2)
        XCTAssertTrue(chore.isActive)
        XCTAssertNil(chore.lastGeneratedDate)
    }

    func testRecurringChoreWithAllFields() {
        let assigneeId = UUID()
        let areaId = UUID()

        let chore = RecurringChore(
            householdId: householdId,
            title: "Monthly Bills",
            recurrenceType: .monthly,
            recurrenceDayOfMonth: 15,
            defaultAssigneeIds: [assigneeId],
            areaId: areaId,
            isActive: false,
            notes: "Pay all bills"
        )

        XCTAssertEqual(chore.recurrenceDayOfMonth, 15)
        XCTAssertEqual(chore.defaultAssigneeIds, [assigneeId])
        XCTAssertEqual(chore.areaId, areaId)
        XCTAssertFalse(chore.isActive)
        XCTAssertEqual(chore.notes, "Pay all bills")
    }

    // MARK: - Recurrence Type Tests

    func testRecurrenceTypeRawValues() {
        XCTAssertEqual(RecurringChore.RecurrenceType.daily.rawValue, "daily")
        XCTAssertEqual(RecurringChore.RecurrenceType.weekly.rawValue, "weekly")
        XCTAssertEqual(RecurringChore.RecurrenceType.biweekly.rawValue, "biweekly")
        XCTAssertEqual(RecurringChore.RecurrenceType.monthly.rawValue, "monthly")
        XCTAssertEqual(RecurringChore.RecurrenceType.everyNDays.rawValue, "every-n-days")
        XCTAssertEqual(RecurringChore.RecurrenceType.everyNWeeks.rawValue, "every-n-weeks")
        XCTAssertEqual(RecurringChore.RecurrenceType.everyNMonths.rawValue, "every-n-months")
    }

    // MARK: - Daily Recurrence Tests

    func testCalculateNextScheduledDate_Daily() {
        let chore = RecurringChore(
            householdId: householdId,
            title: "Daily Task",
            recurrenceType: .daily
        )

        let today = Date()
        let nextDate = chore.calculateNextScheduledDate(after: today)

        guard let nextDate else {
            XCTFail("Expected next scheduled date")
            return
        }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) else {
            XCTFail("Failed to create tomorrow date")
            return
        }
        XCTAssertEqual(nextDate, tomorrow)
    }

    // MARK: - Weekly Recurrence Tests

    func testCalculateNextScheduledDate_Weekly_FutureThisWeek() {
        // Create a chore that recurs on Sunday (weekday = 1)
        let chore = RecurringChore(
            householdId: householdId,
            title: "Weekly Sunday Task",
            recurrenceType: .weekly,
            recurrenceDay: 1 // Sunday
        )

        // Get Monday of this week
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        components.weekday = 2 // Monday
        guard let monday = calendar.date(from: components) else {
            XCTFail("Failed to create Monday date")
            return
        }

        let nextDate = chore.calculateNextScheduledDate(after: monday)

        guard let nextDate else {
            XCTFail("Expected next scheduled date")
            return
        }

        // Should be next Sunday
        let expectedComponents = calendar.dateComponents([.weekday], from: nextDate)
        XCTAssertEqual(expectedComponents.weekday, 1) // Sunday
    }

    func testCalculateNextScheduledDate_Weekly_NoRecurrenceDay_ReturnsNil() {
        let chore = RecurringChore(
            householdId: householdId,
            title: "Weekly No Day",
            recurrenceType: .weekly
            // recurrenceDay is nil
        )

        let nextDate = chore.calculateNextScheduledDate()

        XCTAssertNil(nextDate, "Should return nil when recurrenceDay is not set")
    }

    // MARK: - Biweekly Recurrence Tests

    func testCalculateNextScheduledDate_Biweekly_NoLastGenerated() {
        let chore = RecurringChore(
            householdId: householdId,
            title: "Biweekly Task",
            recurrenceType: .biweekly
        )

        let today = Date()
        let nextDate = chore.calculateNextScheduledDate(after: today)

        // When no lastGeneratedDate, should return the input date
        XCTAssertEqual(nextDate, today)
    }

    func testCalculateNextScheduledDate_Biweekly_WithLastGenerated() {
        guard let lastGenerated = calendar.date(byAdding: .day, value: -7, to: Date()) else {
            XCTFail("Failed to create last generated date")
            return
        }

        let chore = RecurringChore(
            householdId: householdId,
            title: "Biweekly Task",
            recurrenceType: .biweekly,
            lastGeneratedDate: lastGenerated
        )

        let nextDate = chore.calculateNextScheduledDate()

        guard let nextDate else {
            XCTFail("Expected next scheduled date")
            return
        }

        // Should be 14 days after last generated
        guard let expected = calendar.date(byAdding: .day, value: 14, to: lastGenerated) else {
            XCTFail("Failed to create expected date")
            return
        }
        XCTAssertEqual(nextDate, expected)
    }

    // MARK: - Monthly Recurrence Tests

    func testCalculateNextScheduledDate_Monthly_FutureThisMonth() {
        // Create a chore that recurs on the 28th
        let chore = RecurringChore(
            householdId: householdId,
            title: "Monthly Task",
            recurrenceType: .monthly,
            recurrenceDayOfMonth: 28
        )

        // Test from the 1st of the month
        var components = calendar.dateComponents([.year, .month], from: Date())
        components.day = 1
        guard let firstOfMonth = calendar.date(from: components) else {
            XCTFail("Failed to create first of month date")
            return
        }

        let nextDate = chore.calculateNextScheduledDate(after: firstOfMonth)

        guard let nextDate else {
            XCTFail("Expected next scheduled date")
            return
        }

        let nextDateComponents = calendar.dateComponents([.day], from: nextDate)
        XCTAssertEqual(nextDateComponents.day, 28)
    }

    func testCalculateNextScheduledDate_Monthly_PastThisMonth() {
        // Create a chore that recurs on the 1st
        let chore = RecurringChore(
            householdId: householdId,
            title: "Monthly Task",
            recurrenceType: .monthly,
            recurrenceDayOfMonth: 1
        )

        // Test from the 15th of the month
        var components = calendar.dateComponents([.year, .month], from: Date())
        components.day = 15
        guard let midMonth = calendar.date(from: components) else {
            XCTFail("Failed to create mid-month date")
            return
        }

        let nextDate = chore.calculateNextScheduledDate(after: midMonth)

        guard let nextDate else {
            XCTFail("Expected next scheduled date")
            return
        }

        // Should be next month
        let currentMonth = calendar.component(.month, from: midMonth)
        let nextMonth = calendar.component(.month, from: nextDate)

        // Handle December -> January wrap
        if currentMonth == 12 {
            XCTAssertEqual(nextMonth, 1)
        } else {
            XCTAssertEqual(nextMonth, currentMonth + 1)
        }
    }

    func testCalculateNextScheduledDate_Monthly_NoRecurrenceDay_ReturnsNil() {
        let chore = RecurringChore(
            householdId: householdId,
            title: "Monthly No Day",
            recurrenceType: .monthly
            // recurrenceDayOfMonth is nil
        )

        let nextDate = chore.calculateNextScheduledDate()

        XCTAssertNil(nextDate, "Should return nil when recurrenceDayOfMonth is not set")
    }

    // MARK: - Codable Tests

    func testRecurringChoreEncodingDecoding() throws {
        let originalChore = RecurringChore(
            householdId: householdId,
            title: "Test Chore",
            recurrenceType: .weekly,
            recurrenceDay: 3,
            isActive: true,
            notes: "Test notes"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalChore)

        let decoder = JSONDecoder()
        let decodedChore = try decoder.decode(RecurringChore.self, from: data)

        XCTAssertEqual(originalChore.id, decodedChore.id)
        XCTAssertEqual(originalChore.title, decodedChore.title)
        XCTAssertEqual(originalChore.recurrenceType, decodedChore.recurrenceType)
        XCTAssertEqual(originalChore.recurrenceDay, decodedChore.recurrenceDay)
        XCTAssertEqual(originalChore.notes, decodedChore.notes)
    }
}
