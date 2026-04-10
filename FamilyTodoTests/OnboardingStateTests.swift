@testable import HousePulse
import XCTest

@MainActor
final class OnboardingStateTests: XCTestCase {
    private var defaults: UserDefaults {
        .standard
    }

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

        XCTAssertEqual(state.currentState, .householdSetup)
        XCTAssertEqual(state.syncMethod, .iCloud)
    }

    func testLocalSyncSelectionIsPersisted() {
        let state = OnboardingState()

        state.completeOnboarding()
        state.selectSyncMethod(.local)

        XCTAssertEqual(state.currentState, .mainApp)
        XCTAssertEqual(state.syncMethod, .local)
    }

    func testCompleteAuthCloudWithoutHouseholdRoutesToSetup() {
        let state = OnboardingState()
        state.completeOnboarding()

        state.completeAuth(syncMethod: .iCloud, isGuest: false, hasHousehold: false)

        XCTAssertEqual(state.currentState, .householdSetup)
    }

    func testCloudHouseholdSetupDoesNotPersistAsColdLaunchDestination() {
        let state = OnboardingState()
        state.completeOnboarding()
        state.completeAuth(syncMethod: .iCloud, isGuest: false, hasHousehold: false)

        let relaunchedState = OnboardingState()

        XCTAssertEqual(relaunchedState.currentState, .auth)
    }

    func testLocalHouseholdSetupStillPersistsForColdLaunch() {
        let state = OnboardingState()
        state.completeOnboarding()
        state.syncMethod = .local
        state.openHouseholdSetup()

        let relaunchedState = OnboardingState()

        XCTAssertEqual(relaunchedState.currentState, .householdSetup)
    }

    func testCompleteAuthCloudWithHouseholdRoutesToMainApp() {
        let state = OnboardingState()
        state.completeOnboarding()

        state.completeAuth(syncMethod: .iCloud, isGuest: false, hasHousehold: true)

        XCTAssertEqual(state.currentState, .mainApp)
    }

    func testCompleteAuthGuestRoutesToMainApp() {
        let state = OnboardingState()
        state.completeOnboarding()

        state.completeAuth(syncMethod: .local, isGuest: true, hasHousehold: false)

        XCTAssertEqual(state.currentState, .mainApp)
    }

    func testRestoreMainAppForRecoveredSessionSkipsAuthFlow() {
        let state = OnboardingState()
        state.completeOnboarding()

        state.restoreMainAppForRecoveredSession(syncMethod: .iCloud)

        XCTAssertEqual(state.currentState, .mainApp)
        XCTAssertEqual(state.syncMethod, .iCloud)
        XCTAssertEqual(state.householdStatus, .active)
    }

    private func clearOnboardingKeys() {
        defaults.removeObject(forKey: "hasSeenOnboarding")
        defaults.removeObject(forKey: "hasCompletedOnboarding")
        defaults.removeObject(forKey: "syncMethod")
        defaults.removeObject(forKey: "householdStatus")
        defaults.removeObject(forKey: "lastLaunchState")
    }
}
