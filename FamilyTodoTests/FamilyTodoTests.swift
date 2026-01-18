@testable import FamilyTodo
import XCTest

/// Base test file - specific tests are in dedicated test files:
/// - TaskTests.swift - Task model tests
/// - AreaTests.swift - Area model tests
/// - RecurringChoreTests.swift - RecurringChore model and date calculation tests
/// - TaskStoreTests.swift - TaskStore and WIP limit logic tests
/// - HouseholdTests.swift - Household, Member, and HouseholdStore tests
final class FamilyTodoTests: XCTestCase {
    func testAppImportsCorrectly() {
        // Verify the app module can be imported
        XCTAssertTrue(true, "FamilyTodo module imported successfully")
    }
}
