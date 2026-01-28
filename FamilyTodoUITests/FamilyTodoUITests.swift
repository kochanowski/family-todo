import XCTest

/// UI Tests for HousePulse app
/// Tests that the app can launch successfully without crashing
final class FamilyTodoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Verify app launches and reaches foreground state
    /// This catches crashes that occur during app initialization
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()

        // Wait for app to stabilize in foreground state
        let reachedForeground = app.wait(for: .runningForeground, timeout: 5.0)
        XCTAssertTrue(reachedForeground, "App should launch and reach foreground state")
    }

    /// Verify app doesn't crash when backgrounded and foregrounded
    func testAppSurvivesBackgroundForegroundCycle() {
        let app = XCUIApplication()
        app.launch()

        // Wait for initial launch
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0))

        // Simulate home button press
        XCUIDevice.shared.press(.home)

        // Brief pause in background
        Thread.sleep(forTimeInterval: 0.5)

        // Bring app back to foreground
        app.activate()

        // Verify app is still running
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 3.0), "App should return to foreground"
        )
    }
}
