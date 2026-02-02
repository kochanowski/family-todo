import Combine
@testable import HousePulse
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
        XCTAssertTrue(true, "HousePulse module imported successfully")
    }
}

@MainActor
final class UserSessionTests: XCTestCase {
    @MainActor
    private final class TestAuthenticationService: AuthenticationServiceType {
        @Published var authenticationState: AuthenticationService.AuthenticationState = .unauthenticated
        @Published var currentUser: AuthenticationService.AuthenticatedUser?

        func signInWithApple() {
            authenticationState = .authenticating
        }

        func signOut() {
            authenticationState = .unauthenticated
            currentUser = nil
        }

        func checkCloudKitStatus() async {}

        func getChangePublisher() -> AnyPublisher<Void, Never> {
            objectWillChange.map { _ in () }.eraseToAnyPublisher()
        }
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "UserSessionTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return .standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testStartGuestSessionSetsAccessAndUserId() {
        let authService = TestAuthenticationService()
        let session = UserSession(authService: authService, userDefaults: makeUserDefaults())

        session.startGuestSession()

        XCTAssertEqual(session.sessionMode, .guest)
        XCTAssertTrue(session.hasActiveSession)
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertNotNil(session.userId)
        XCTAssertEqual(session.displayName, "Guest")
    }

    func testEndGuestSessionClearsAccess() {
        let authService = TestAuthenticationService()
        let session = UserSession(authService: authService, userDefaults: makeUserDefaults())

        session.startGuestSession()
        session.endGuestSession()

        XCTAssertEqual(session.sessionMode, .signedOut)
        XCTAssertFalse(session.hasActiveSession)
        XCTAssertNil(session.userId)
    }

    func testAuthenticatedOverridesGuest() async {
        let authService = TestAuthenticationService()
        let session = UserSession(authService: authService, userDefaults: makeUserDefaults())

        session.startGuestSession()
        XCTAssertEqual(session.sessionMode, .guest)

        let user = AuthenticationService.AuthenticatedUser(
            id: "cloudkit-user",
            appleUserID: "apple-user",
            email: nil,
            displayName: "Test User",
            givenName: "Test",
            familyName: "User"
        )
        authService.currentUser = user
        authService.authenticationState = .authenticated(userID: user.id)

        // Give time for async state change to propagate
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(session.sessionMode, .signedIn)
        XCTAssertEqual(session.userId, user.id)
        XCTAssertEqual(session.displayName, "Test User")
    }
}
