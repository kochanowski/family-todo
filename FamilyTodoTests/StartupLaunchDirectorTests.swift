import Combine
@testable import HousePulse
import XCTest

@MainActor
final class StartupLaunchDirectorTests: XCTestCase {
    private final class TestAuthenticationService: AuthenticationServiceType {
        @Published var authenticationState: AuthenticationService.AuthenticationState = .unauthenticated
        @Published var currentUser: AuthenticationService.AuthenticatedUser?
        @Published var latestDiagnostics: AuthDiagnosticsSnapshot?

        func signInWithApple() {}
        func signOut() {}
        func checkCloudKitStatus() async {}
        func diagnosticsReportJSON() -> String { "{}" }
        func clearDiagnosticsHistory() {}
        func getChangePublisher() -> AnyPublisher<Void, Never> {
            objectWillChange.map { _ in () }.eraseToAnyPublisher()
        }
    }

    private var onboardingDefaults: UserDefaults { .standard }
    private var sessionSuiteName: String?
    private var sessionDefaults: UserDefaults?

    override func setUpWithError() throws {
        try super.setUpWithError()
        clearOnboardingKeys()
        let isolatedDefaults = TestModelContainerFactory.makeUserDefaults(suitePrefix: "StartupLaunchDirectorTests")
        sessionSuiteName = isolatedDefaults.suiteName
        sessionDefaults = isolatedDefaults.defaults
    }

    override func tearDownWithError() throws {
        clearOnboardingKeys()
        TestModelContainerFactory.clearUserDefaults(
            suiteName: sessionSuiteName,
            defaults: sessionDefaults
        )
        sessionSuiteName = nil
        sessionDefaults = nil
        try super.tearDownWithError()
    }

    func testPrimeLocalLaunchRoutePromotesSignedInUserWithCachedHouseholdToMainApp() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer(profile: .household)
        let householdStore = HouseholdStore(modelContext: container.mainContext)
        let onboardingState = OnboardingState()
        onboardingState.completeOnboarding()
        onboardingState.openAuth()

        let authService = TestAuthenticationService()
        authService.currentUser = AuthenticationService.AuthenticatedUser(
            id: "owner-user",
            appleUserID: "apple-owner",
            email: nil,
            displayName: nil,
            givenName: nil,
            familyName: nil
        )

        guard let sessionDefaults else {
            XCTFail("Missing isolated defaults")
            return
        }

        sessionDefaults.set(true, forKey: "signedInSessionEnabled")
        sessionDefaults.set("owner-user", forKey: "lastSignedInUserId")
        sessionDefaults.set(
            ["owner-user": "Owner"],
            forKey: "preferredDisplayNameByUserId"
        )

        let session = UserSession(authService: authService, userDefaults: sessionDefaults)

        let household = Household(
            id: UUID(),
            name: "Startup Home",
            ownerId: "owner-user"
        )
        let owner = Member(
            householdId: household.id,
            userId: "owner-user",
            displayName: "Owner",
            role: .owner
        )

        container.mainContext.insert(CachedHousehold(from: household))
        container.mainContext.insert(CachedMember(from: owner))
        try container.mainContext.save()

        StartupLaunchDirector.primeLocalLaunchRoute(
            userSession: session,
            householdStore: householdStore,
            onboardingState: onboardingState
        )

        XCTAssertEqual(onboardingState.currentState, .mainApp)
        XCTAssertEqual(session.currentHouseholdID, household.id)
        XCTAssertEqual(householdStore.currentHousehold?.id, household.id)
    }

    func testPrimeLocalLaunchRouteKeepsAuthWhenNoCachedHouseholdExists() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer(profile: .household)
        let householdStore = HouseholdStore(modelContext: container.mainContext)
        let onboardingState = OnboardingState()
        onboardingState.completeOnboarding()
        onboardingState.openAuth()

        let authService = TestAuthenticationService()
        authService.currentUser = AuthenticationService.AuthenticatedUser(
            id: "owner-user",
            appleUserID: "apple-owner",
            email: nil,
            displayName: nil,
            givenName: nil,
            familyName: nil
        )

        guard let sessionDefaults else {
            XCTFail("Missing isolated defaults")
            return
        }

        sessionDefaults.set(true, forKey: "signedInSessionEnabled")
        sessionDefaults.set("owner-user", forKey: "lastSignedInUserId")

        let session = UserSession(authService: authService, userDefaults: sessionDefaults)

        StartupLaunchDirector.primeLocalLaunchRoute(
            userSession: session,
            householdStore: householdStore,
            onboardingState: onboardingState
        )

        XCTAssertEqual(onboardingState.currentState, .auth)
        XCTAssertNil(session.currentHouseholdID)
        XCTAssertNil(householdStore.currentHousehold)
    }

    private func clearOnboardingKeys() {
        onboardingDefaults.removeObject(forKey: "hasSeenOnboarding")
        onboardingDefaults.removeObject(forKey: "hasCompletedOnboarding")
        onboardingDefaults.removeObject(forKey: "syncMethod")
        onboardingDefaults.removeObject(forKey: "householdStatus")
        onboardingDefaults.removeObject(forKey: "lastLaunchState")
    }
}
