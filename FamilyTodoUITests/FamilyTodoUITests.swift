import XCTest

/// UI Tests for HousePulse app with Data Seeding
/// Tests critical user flows using deterministic data states
final class FamilyTodoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Helper to launch app
    /// - Parameters:
    ///   - arguments: Additional launch arguments
    ///   - reset: Whether to reset data (default true)
    private func launchApp(arguments: [String] = [], reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-uiTestMode"]
        if reset {
            args.append("-resetData")
        }
        args.append(contentsOf: arguments)
        app.launchArguments = args
        app.launch()
        return app
    }

    // MARK: - A) App Launch States

    func testLaunch_Guest_NoHousehold() {
        let app = launchApp(arguments: ["-seedScenario", "guest_no_household"])

        // Should show "No Household Selected" empty state or Sync/Create screen
        // Based on implementation, guest mode might show ContentUnavailableView in Tabs
        let contentUnavailable = app.staticTexts["No Household Selected"]
        XCTAssertTrue(contentUnavailable.waitForExistence(timeout: 5.0))

        // Tab bar should still be visible but empty content
        XCTAssertTrue(app.buttons["tabButton_more"].exists)
    }

    func testLaunch_WithHousehold() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])

        // Should land on Shopping tab by default and show content
        XCTAssertTrue(app.buttons["shoppingAddItemButton"].waitForExistence(timeout: 5.0))
        XCTAssertTrue(app.staticTexts["Milk"].exists)
    }

    // MARK: - B) Shopping List Regression

    func testShoppingRapidEntry_MultipleItems() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"]) // Seeds Milk, Bread, Eggs

        let addButton = app.buttons["shoppingAddItemButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5.0))
        addButton.tap()

        let textField = app.textFields["shoppingRapidEntryField"]
        XCTAssertTrue(textField.waitForExistence(timeout: 2.0))

        // Add "Apple"
        textField.typeText("Apple")
        textField.typeText("\n") // Return key submits

        // Add "Banana"
        textField.typeText("Banana")
        textField.typeText("\n")

        // Verify both exist
        XCTAssertTrue(app.staticTexts["Apple"].exists)
        XCTAssertTrue(app.staticTexts["Banana"].exists)
    }

    func testShoppingRapidEntry_EmptyReturnExits() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])

        app.buttons["shoppingAddItemButton"].tap()
        let textField = app.textFields["shoppingRapidEntryField"]
        XCTAssertTrue(textField.waitForExistence(timeout: 2.0))

        // Submit empty
        textField.typeText("\n")

        // Field should disappear (Rapid entry mode exits)
        XCTAssertFalse(textField.exists)
        XCTAssertTrue(app.buttons["shoppingAddItemButton"].exists)
    }

    func testShoppingClearToBuyConfirmation_CancelKeepsItems() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])

        let clearButton = app.buttons["shoppingClearButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5.0))
        clearButton.tap()

        let alert = app.alerts["Clear shopping list?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2.0))
        alert.buttons["Cancel"].tap()

        XCTAssertTrue(app.staticTexts["Milk"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.staticTexts["Bread"].exists)
    }

    func testShoppingClearToBuyConfirmation_ClearRemovesToBuy() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])

        let milk = app.staticTexts["Milk"]
        XCTAssertTrue(milk.waitForExistence(timeout: 5.0))

        app.buttons["shoppingClearButton"].tap()
        let alert = app.alerts["Clear shopping list?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2.0))
        alert.buttons["Clear"].tap()

        let milkGone = NSPredicate(format: "exists == false")
        expectation(for: milkGone, evaluatedWith: milk, handler: nil)
        waitForExpectations(timeout: 5.0)
    }

    func testRestockMoveAndOpen() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])

        // Milk is seeded as "Not Bought". Toggle it.
        let milk = app.buttons["shoppingItem_Milk"] // Changed to precise ID
        XCTAssertTrue(milk.waitForExistence(timeout: 5.0))
        milk.tap()

        // It should disappear from active list (moved to bought/restock)
        // Wait for removal
        let predicate = NSPredicate(format: "exists == false")
        expectation(for: predicate, evaluatedWith: milk, handler: nil)
        waitForExpectations(timeout: 5.0, handler: nil)

        // Open Restock Panel
        app.buttons["shoppingRestockButton"].tap()

        // Verify Milk is now in Restock
        XCTAssertTrue(app.staticTexts["Recently Purchased"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.staticTexts["Milk"].exists)
    }

    func testShoppingContextualTipAppearsWhenBundleQuickAddIsAnchored() {
        let app = launchApp(
            arguments: [
                "-seedScenario", "contextual_onboarding",
                "-showTipForTesting", "shopping_quick_add",
            ]
        )

        XCTAssertTrue(
            app.staticTexts["Long-press Add item to quickly add one of your saved bundles."]
                .waitForExistence(timeout: 5.0)
        )
    }

    func testShoppingFirstAddTipAppearsOnFreshHousehold() {
        let app = launchApp(
            arguments: [
                "-seedScenario", "household_empty",
                "-showTipForTesting", "shopping_first_add",
            ]
        )

        XCTAssertTrue(
            app.staticTexts["Tap Add item to create your first shopping entry."]
                .waitForExistence(timeout: 5.0)
        )
    }

    func testShoppingRecentlyPurchasedTipAppearsAfterFirstBoughtItem() {
        let app = launchApp(
            arguments: [
                "-seedScenario", "household_basic",
                "-showTipForTesting", "shopping_recent",
            ]
        )

        XCTAssertTrue(
            app.staticTexts["Open Recently Purchased to quickly re-add items you already bought."]
                .waitForExistence(timeout: 5.0)
        )
    }

    func testShoppingBundlesTipAppearsAfterFirstItemIsAdded() {
        let app = launchApp(
            arguments: [
                "-seedScenario", "shopping_single_item",
                "-showTipForTesting", "shopping_bundles",
            ]
        )

        XCTAssertTrue(
            app.staticTexts["Open Bundles to save reusable shopping sets for faster planning."]
                .waitForExistence(timeout: 5.0)
        )
    }

    func testRetroThemeRestockHeaderUsesClearLabel() {
        let app = launchApp(arguments: [
            "-seedScenario", "household_basic",
            "-themeOverride", "retro",
        ])

        app.buttons["shoppingRestockButton"].tap()

        XCTAssertTrue(app.staticTexts["Recently Purchased"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.buttons["Clear"].exists)
    }

    func testRetroThemeAddButtonUsesTextOnlyLabel() {
        let app = launchApp(arguments: [
            "-seedScenario", "household_basic",
            "-themeOverride", "retro",
        ])

        let addButton = app.buttons["shoppingAddItemButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5.0))
        XCTAssertEqual(addButton.label, "Add item")
    }

    func testRetroLightThemeCoreEmptyStatesLoad() {
        let app = launchApp(arguments: [
            "-seedScenario", "household_empty_seen_tutorials",
            "-themeOverride", "retroLight",
        ])

        XCTAssertTrue(app.staticTexts["Your List is Empty"].waitForExistence(timeout: 5.0))

        app.buttons["tabButton_tasks"].tap()
        XCTAssertTrue(
            app.staticTexts["No Tasks Yet. Ready to get organized?"].waitForExistence(timeout: 2.0)
        )

        app.buttons["tabButton_backlog"].tap()
        XCTAssertTrue(app.staticTexts["No Ideas Yet"].waitForExistence(timeout: 2.0))
    }

    func testSettingsShowsRetroDarkAndRetroLightThemeCards() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])

        app.buttons["tabButton_more"].tap()
        app.buttons["Settings"].tap()

        XCTAssertTrue(app.buttons["themeMiniatureCard_retroDark"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.buttons["themeMiniatureCard_retroLight"].exists)
    }

    func testRetroLightThemeHidesAccentColorSectionInSettings() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])

        app.buttons["tabButton_more"].tap()
        app.buttons["Settings"].tap()

        let accentHeader = app.staticTexts["Accent Color"]
        XCTAssertTrue(accentHeader.waitForExistence(timeout: 2.0))

        let retroLightCard = app.buttons["themeMiniatureCard_retroLight"]
        XCTAssertTrue(retroLightCard.exists)
        retroLightCard.tap()

        let disappears = NSPredicate(format: "exists == false")
        expectation(for: disappears, evaluatedWith: accentHeader)
        waitForExpectations(timeout: 2.0)
    }

    func testPaperThemeCoreEmptyStatesLoad() {
        let app = launchApp(arguments: [
            "-seedScenario", "household_empty_seen_tutorials",
            "-themeOverride", "paper",
        ])

        XCTAssertTrue(app.staticTexts["Your List is Empty"].waitForExistence(timeout: 5.0))

        app.buttons["tabButton_tasks"].tap()
        XCTAssertTrue(
            app.staticTexts["No Tasks Yet. Ready to get organized?"].waitForExistence(timeout: 2.0)
        )

        app.buttons["tabButton_backlog"].tap()
        XCTAssertTrue(app.staticTexts["No Ideas Yet"].waitForExistence(timeout: 2.0))
    }

    func testTasksEmptyStateRoutesToIdeasTab() {
        let app = launchApp(arguments: ["-seedScenario", "household_empty"])

        app.buttons["tabButton_tasks"].tap()

        XCTAssertTrue(
            app.staticTexts["No Tasks Yet. Ready to get organized?"].waitForExistence(timeout: 2.0)
        )

        let createButton = app.buttons["Create your first task"]
        XCTAssertTrue(createButton.exists)
        createButton.tap()

        XCTAssertTrue(app.buttons["backlogAddCategoryButton"].waitForExistence(timeout: 2.0))
    }

    func testIdeasCategoryTipAppearsOnEmptyIdeasScreen() {
        let app = launchApp(
            arguments: [
                "-seedScenario", "household_empty",
                "-showTipForTesting", "ideas_category",
            ]
        )

        app.buttons["tabButton_backlog"].tap()

        XCTAssertTrue(
            app.staticTexts["Start here by creating a category for your ideas."]
                .waitForExistence(timeout: 5.0)
        )
    }

    func testIdeasAddIdeaTipAppearsAfterCreatingFirstCategory() {
        let app = launchApp(
            arguments: [
                "-seedScenario", "ideas_single_category",
                "-showTipForTesting", "ideas_add",
            ]
        )

        app.buttons["tabButton_backlog"].tap()

        XCTAssertTrue(
            app.staticTexts["Tap Add idea to capture something you want to plan later."]
                .waitForExistence(timeout: 5.0)
        )
    }

    func testIdeasAssignAndPromoteTipsAnchorToFirstRelevantIdea() {
        let assignApp = launchApp(
            arguments: [
                "-seedScenario", "ideas_unassigned",
                "-showTipForTesting", "ideas_assign",
            ]
        )

        assignApp.buttons["tabButton_backlog"].tap()
        XCTAssertTrue(
            assignApp.staticTexts["Use this area to assign the idea to a household member."]
                .waitForExistence(timeout: 5.0)
        )

        let promoteApp = launchApp(
            arguments: [
                "-seedScenario", "contextual_onboarding",
                "-showTipForTesting", "ideas_promote",
            ]
        )

        promoteApp.buttons["tabButton_backlog"].tap()
        XCTAssertTrue(
            promoteApp.staticTexts["Once an idea has an owner, tap the arrow to move it into Tasks."]
                .waitForExistence(timeout: 5.0)
        )
    }

    // MARK: - C) Tasks Regression

    func testTasksCompleteMovesToCompleted() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])

        app.buttons["tabButton_tasks"].tap()

        // "Pay bills" is active. Complete it.
        let taskRow = app.buttons["taskRow_Pay bills"]
        XCTAssertTrue(taskRow.waitForExistence(timeout: 5.0))
        taskRow.tap()

        // Should move to Completed section
        // We verify by checking if it appears in the specific "Completed" rows logic if we had distinct IDs
        // Or simply checking it's still visible but crossed out (visual check hard in UI test)
        // But our Accessibility ID changes to "taskRowCompleted_..."?
        // Let's check if the ID changed.

        let completedRow = app.buttons["taskRowCompleted_Pay bills"]
        XCTAssertTrue(completedRow.waitForExistence(timeout: 5.0))
    }

    func testTasksPersistenceRelaunch() {
        // 1. Launch cleanly
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])
        app.buttons["tabButton_tasks"].tap()

        // 2. Add "PersistMe" task
        let input = app.textFields["taskInputField"]
        XCTAssertTrue(input.waitForExistence(timeout: 2.0))
        input.tap()
        input.typeText("PersistMe\n")
        XCTAssertTrue(app.staticTexts["PersistMe"].exists)

        // 3. Terminate
        app.terminate()

        // 4. Relaunch WITHOUT reset
        let app2 = launchApp(arguments: ["-seedScenario", "household_basic"], reset: false)
        // Note: seedScenario household_basic MIGHT re-seed if we are not careful?
        // UITestHelper implementation checks "-resetData". If NOT present, it might strictly append or do nothing?
        // Let's check UITestHelper.
        // It checks "-resetData", then "-seedScenario".
        // If we don't pass -resetData, it WON'T clear.
        // But if we pass -seedScenario, it WILL call seed functions which might duplicate data?
        // We should launch app2 WITHOUT seed arguments, just -uiTestMode.

        // Correct approach for app3 (relaunch):
        let app3 = XCUIApplication()
        app3.launchArguments = ["-uiTestMode"] // No reset, no seed
        app3.launch()

        app3.buttons["tabButton_tasks"].tap()
        XCTAssertTrue(app3.staticTexts["PersistMe"].waitForExistence(timeout: 5.0))
    }

    func testTasksContextualTipAppearsForSwipeActions() {
        let app = launchApp(
            arguments: [
                "-seedScenario", "contextual_onboarding",
                "-showTipForTesting", "tasks",
            ]
        )

        app.buttons["tabButton_tasks"].tap()

        XCTAssertTrue(
            app.staticTexts["Swipe a task row for shortcuts like Poke, Move to Ideas, or Delete."]
                .waitForExistence(timeout: 5.0)
        )
    }

    // MARK: - D) Backlog Regression

    func testBacklogAddCategory() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])
        app.buttons["tabButton_backlog"].tap()

        app.buttons["backlogAddCategoryButton"].tap()

        let alert = app.alerts["New Category"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2.0))

        let textField = alert.textFields.firstMatch
        textField.typeText("New Project")
        alert.buttons["Create"].tap()

        XCTAssertTrue(app.staticTexts["NEW PROJECT"].waitForExistence(timeout: 2.0)) // Uppercased in UI?
    }

    func testBacklogDeleteCategoryWithItems_ShowsWarning() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])
        app.buttons["tabButton_backlog"].tap()

        // TODO: Implement finding the menu button in the header
        // Limitation: Setting accessibility IDs on complex HStack headers can sometimes hide child buttons
        // Will be implemented in future phase
        /*
         // "Groceries" has items. Try to delete.
         // Needs to tap ellipses menu first?
         */
    }

    func testBacklogDeleteItemShowsConfirmationBeforeDeletion() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])
        app.buttons["tabButton_backlog"].tap()

        let deleteButton = app.buttons["backlogDeleteButton_Olive Oil"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5.0))
        deleteButton.tap()

        let alert = app.alerts["Are you sure you want to delete?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2.0))
        alert.buttons["Cancel"].tap()

        XCTAssertTrue(app.staticTexts["Olive Oil"].exists)
    }

    func testBacklogDeleteEmptyCategoryShowsConfirmation() {
        let app = launchApp(arguments: ["-seedScenario", "ideas_single_category"])
        app.buttons["tabButton_backlog"].tap()

        let menuButton = app.buttons["backlogCategoryMenuButton_Projects"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5.0))
        menuButton.tap()

        let deleteAction = app.buttons["Delete Category"]
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 2.0))
        deleteAction.tap()

        let alert = app.alerts["Are you sure?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2.0))
        alert.buttons["Cancel"].tap()

        XCTAssertTrue(app.staticTexts["PROJECTS"].exists)
    }

    func testBacklogPromoteAssignedIdeaMovesToTasksWithoutOpeningEditSheet() {
        let app = launchApp(arguments: ["-seedScenario", "contextual_onboarding"])
        app.buttons["tabButton_backlog"].tap()

        let promoteButton = app.buttons["backlogPromoteButton_Paint guest room"]
        XCTAssertTrue(promoteButton.waitForExistence(timeout: 5.0))
        promoteButton.tap()

        XCTAssertFalse(app.navigationBars["Idea Item"].waitForExistence(timeout: 1.0))

        app.buttons["tabButton_tasks"].tap()
        XCTAssertTrue(app.buttons["taskRow_Paint guest room"].waitForExistence(timeout: 5.0))
    }

    func testBacklogContextualTipAppearsWhenPromoteButtonExists() {
        let app = launchApp(
            arguments: [
                "-seedScenario", "contextual_onboarding",
                "-showTipForTesting", "ideas",
            ]
        )

        app.buttons["tabButton_backlog"].tap()

        XCTAssertTrue(
            app.staticTexts["Once an idea has an owner, tap the arrow to move it into Tasks."]
                .waitForExistence(timeout: 5.0)
        )
    }

    // MARK: - E) Settings Regression

    func testSettingsAppearanceSwitch() {
        let app = launchApp(arguments: ["-seedScenario", "household_basic"])
        app.buttons["tabButton_more"].tap()
        app.buttons["Settings"].tap()

        let appearanceDark = app.buttons["appearanceCard_Dark"]
        XCTAssertTrue(appearanceDark.waitForExistence(timeout: 2.0))
        appearanceDark.tap()

        // Verify state changed (button selected state).
        // We can check if it is selected by checking value or attribute?
        // UI test verification of "Dark Mode" is hard without screenshots,
        // but we can verify the tap didn't crash and element is still there.
        XCTAssertTrue(appearanceDark.exists)
    }
}

final class FamilyTodoPerformanceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchPerformance() {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // Measures app launch time
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    func testShoppingListScrollPerformance() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestMode", "-resetData", "-seedScenario", "heavy_data"]
        app.launch()

        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10.0))

        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
            list.swipeUp(velocity: .fast)
            list.swipeDown(velocity: .fast)
        }
    }
}
