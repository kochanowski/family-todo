@testable import HousePulse
import XCTest

@MainActor
final class OnboardingStateTests: XCTestCase {
    private var defaults: UserDefaults { .standard }

    override func setUp() {
        super.setUp()
        clearOnboardingKeys()
    }

    override func tearDown() {
        clearOnboardingKeys()
        super.tearDown()
    }

    func testSelectSyncMethodMovesToMainApp() {
        let state = OnboardingState()

        state.completeOnboarding()
        state.selectSyncMethod(.iCloud)

        XCTAssertEqual(state.currentState, .mainApp)
        XCTAssertEqual(state.syncMethod, .iCloud)
    }

    func testLocalSyncSelectionIsPersisted() {
        let state = OnboardingState()

        state.completeOnboarding()
        state.selectSyncMethod(.local)

        XCTAssertEqual(state.currentState, .mainApp)
        XCTAssertEqual(state.syncMethod, .local)
    }

    private func clearOnboardingKeys() {
        defaults.removeObject(forKey: "hasCompletedOnboarding")
        defaults.removeObject(forKey: "syncMethod")
        defaults.removeObject(forKey: "householdStatus")
        defaults.removeObject(forKey: "lastLaunchState")
    }
}
