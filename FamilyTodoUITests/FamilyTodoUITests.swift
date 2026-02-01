import XCTest

/// UI Tests for HousePulse app
/// Tests critical user flows and app stability
final class FamilyTodoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Verify app launches and reaches foreground state
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()

        let reachedForeground = app.wait(for: .runningForeground, timeout: 5.0)
        XCTAssertTrue(reachedForeground, "App should launch and reach foreground state")

        // Assert initial tab is visible (Shopping)
        XCTAssertTrue(app.buttons["tabButton_shopping"].exists, "Shopping tab should be visible on launch")
    }

    /// Verify navigation between all main tabs
    func testTabNavigation() {
        let app = XCUIApplication()
        app.launch()

        // Wait for tab bar
        let shoppingTab = app.buttons["tabButton_shopping"]
        XCTAssertTrue(shoppingTab.waitForExistence(timeout: 5.0))

        // Navigate to Tasks
        let tasksTab = app.buttons["tabButton_tasks"]
        tasksTab.tap()
        XCTAssertTrue(app.staticTexts["Tasks"].exists)

        // Navigate to Backlog
        let backlogTab = app.buttons["tabButton_backlog"]
        backlogTab.tap()
        XCTAssertTrue(app.staticTexts["Backlog"].exists)

        // Navigate to More
        let moreTab = app.buttons["tabButton_more"]
        moreTab.tap()
        // Check for specific element in More view or title
        XCTAssertTrue(app.navigationBars["More"].exists || app.staticTexts["More"].exists)

        // Return to Shopping
        shoppingTab.tap()
        XCTAssertTrue(app.staticTexts["Shopping"].exists)
    }

    /// Verify rapid entry flow in Shopping list
    func testShoppingRapidEntry() {
        let app = XCUIApplication()
        app.launch()

        // Ensure we are on Shopping tab
        let shoppingTab = app.buttons["tabButton_shopping"]
        if !shoppingTab.isSelected {
            shoppingTab.tap()
        }

        // Tap Add Item button
        let addButton = app.buttons["shoppingAddItemButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3.0))
        addButton.tap()

        // Type first item
        let textField = app.textFields["shoppingRapidEntryField"]
        XCTAssertTrue(textField.waitForExistence(timeout: 2.0))

        textField.typeText("Milk")
        textField.typeText("\n") // Submit

        // Type second item
        textField.typeText("Eggs")
        textField.typeText("\n") // Submit

        // Verify items appear in list
        XCTAssertTrue(app.staticTexts["Milk"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.staticTexts["Eggs"].exists)
    }

    /// Verify restock panel opens
    func testRestockPanelOpens() {
        let app = XCUIApplication()
        app.launch()

        let restockButton = app.buttons["shoppingRestockButton"]
        XCTAssertTrue(restockButton.waitForExistence(timeout: 3.0))

        restockButton.tap()

        // Verify sheet title
        let sheetTitle = app.staticTexts["Recently Purchased"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 2.0))

        // Close sheet
        app.buttons["Done"].tap()
        XCTAssertFalse(sheetTitle.exists)
    }
}
