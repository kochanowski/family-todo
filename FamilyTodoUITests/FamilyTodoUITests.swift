import XCTest

/// UI Tests for HousePulse app with Data Seeding
/// Tests critical user flows using deterministic data states
final class FamilyTodoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Helper to launch app with specific seed arguments
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestMode", "-resetData"] + arguments
        app.launch()
        return app
    }

    /// Verify shopping list flow with seeded data
    func testShoppingCoreFlow() {
        let app = launchApp(arguments: ["-seedShoppingList"])

        // 1. Verify seeded items exist
        XCTAssertTrue(app.staticTexts["Milk"].waitForExistence(timeout: 5.0))
        XCTAssertTrue(app.staticTexts["Bread"].exists)

        // 2. Add new item via Rapid Entry
        let addButton = app.buttons["shoppingAddItemButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 2.0))
        addButton.tap()

        let textField = app.textFields["shoppingRapidEntryField"]
        if textField.waitForExistence(timeout: 2.0) {
            textField.typeText("Cheese")
            textField.typeText("\n")
            XCTAssertTrue(app.staticTexts["Cheese"].waitForExistence(timeout: 2.0))
        }

        // 3. Verify Restock Flow
        let restockButton = app.buttons["shoppingRestockButton"]
        restockButton.tap()

        let sheetTitle = app.staticTexts["Recently Purchased"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 2.0))

        // Find seeded bought item "Eggs"
        XCTAssertTrue(app.staticTexts["Eggs"].exists)

        // Close sheet
        app.buttons["Done"].tap()
    }

    /// Verify tasks flow with seeded data
    func testTasksCoreFlow() {
        let app = launchApp(arguments: ["-seedTasks"])

        // Navigate to Tasks
        app.buttons["tabButton_tasks"].tap()

        // 1. Verify seeded active task
        let payBills = app.staticTexts["Pay bills"]
        XCTAssertTrue(payBills.waitForExistence(timeout: 5.0))

        // 2. Add new task
        let taskInput = app.textFields["taskInputField"]
        if taskInput.exists {
            taskInput.tap()
            taskInput.typeText("Water plants")
            taskInput.typeText("\n")
            XCTAssertTrue(app.staticTexts["Water plants"].waitForExistence(timeout: 2.0))
        }
    }

    /// Verify backlog categories and items
    func testBacklogCoreFlow() {
        let app = launchApp(arguments: ["-seedBacklog"])

        // Navigate to Backlog
        app.buttons["tabButton_backlog"].tap()

        // 1. Verify category exists
        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 5.0))

        // 2. Verify items inside (might need to expand if collapsed by default)
        XCTAssertTrue(app.staticTexts["Olive Oil"].exists)
    }

    /// Verify settings navigation
    func testSettingsFlow() {
        let app = launchApp()

        // Navigate to More
        app.buttons["tabButton_more"].tap()

        // Verify Settings option exists
        let settingsButton = app.buttons["Settings"]
        if settingsButton.exists {
            settingsButton.tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2.0))
        }
    }
}
