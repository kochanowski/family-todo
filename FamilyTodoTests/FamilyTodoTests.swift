import Combine
import CloudKit
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
        @Published var latestDiagnostics: AuthDiagnosticsSnapshot?

        func signInWithApple() {
            authenticationState = .authenticating
        }

        func signOut() {
            authenticationState = .unauthenticated
            currentUser = nil
        }

        func checkCloudKitStatus() async {}

        func diagnosticsReportJSON() -> String {
            "{}"
        }

        func clearDiagnosticsHistory() {
            latestDiagnostics = nil
        }

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
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(session.sessionMode, .signedIn)
        XCTAssertEqual(session.userId, user.id)
        XCTAssertEqual(session.displayName, "Test User")
    }
}

@MainActor
final class AuthenticationServiceDiagnosticsTests: XCTestCase {
    func testDiagnosticsSnapshotContainsExpectedFieldsWithoutPII() {
        #if !CI
        let service = AuthenticationService(cloudKitContainer: nil)
        #else
        let service = AuthenticationService()
        #endif

        service.signInWithApple()

        guard let snapshot = service.latestDiagnostics else {
            XCTFail("Expected diagnostics snapshot to be available")
            return
        }

        XCTAssertFalse(snapshot.containerIdentifier.isEmpty)
        XCTAssertFalse(snapshot.bundleIdentifier.isEmpty)
        XCTAssertFalse(snapshot.osVersion.isEmpty)
        XCTAssertFalse(snapshot.recentEntries.isEmpty)
        XCTAssertNotNil(snapshot.mappedErrorCategory)
        XCTAssertFalse(snapshot.cloudKitAvailabilityReason.isEmpty)
        XCTAssertNotNil(snapshot.recentEntries.first(where: { $0.stage == .cloudKitContainerInit }))
        if snapshot.cloudKitAvailabilityReason != CloudKitAvailabilityReason.missingKey.rawValue {
            XCTAssertNotNil(snapshot.hpCloudKitEnabledRawType)
            XCTAssertNotNil(snapshot.hpCloudKitEnabledRawValue)
        }

        let report = service.diagnosticsReportJSON()
        XCTAssertFalse(report.contains("appleUserID"))
        XCTAssertFalse(report.contains("recordName"))
        XCTAssertFalse(report.contains("email"))
    }

    func testMappedErrorCategoryClassifiesCommonCloudKitErrors() {
        XCTAssertEqual(
            AuthenticationService.mappedErrorCategory(for: CKError(.notAuthenticated)),
            .notAuthenticated
        )
        XCTAssertEqual(
            AuthenticationService.mappedErrorCategory(for: CKError(.missingEntitlement)),
            .missingEntitlement
        )
        XCTAssertEqual(
            AuthenticationService.mappedErrorCategory(for: CKError(.badContainer)),
            .badContainer
        )
        XCTAssertEqual(
            AuthenticationService.mappedErrorCategory(for: CKError(.permissionFailure)),
            .permissionFailure
        )
    }

    func testDiagnosticsReportJSONIsValidJSON() throws {
        #if !CI
        let service = AuthenticationService(cloudKitContainer: nil)
        #else
        let service = AuthenticationService()
        #endif
        service.signInWithApple()

        let json = service.diagnosticsReportJSON()
        let data = try XCTUnwrap(json.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)

        XCTAssertNotNil(object)
    }

    func testParseCloudKitEnabledFlagForBoolValues() {
        let enabledResult = AuthenticationService.parseCloudKitEnabledFlag(true)
        XCTAssertTrue(enabledResult.enabled)
        XCTAssertEqual(enabledResult.reason, .enabled)
        XCTAssertEqual(enabledResult.rawType, "Bool")

        let disabledResult = AuthenticationService.parseCloudKitEnabledFlag(false)
        XCTAssertFalse(disabledResult.enabled)
        XCTAssertEqual(disabledResult.reason, .disabledByFlag)
        XCTAssertEqual(disabledResult.rawType, "Bool")
    }

    func testParseCloudKitEnabledFlagForNSNumberValues() {
        let enabledResult = AuthenticationService.parseCloudKitEnabledFlag(NSNumber(value: 1))
        XCTAssertTrue(enabledResult.enabled)
        XCTAssertEqual(enabledResult.reason, .enabled)
        XCTAssertEqual(enabledResult.rawType, "NSNumber")

        let disabledResult = AuthenticationService.parseCloudKitEnabledFlag(NSNumber(value: 0))
        XCTAssertFalse(disabledResult.enabled)
        XCTAssertEqual(disabledResult.reason, .disabledByFlag)
        XCTAssertEqual(disabledResult.rawType, "NSNumber")
    }

    func testParseCloudKitEnabledFlagForStringValues() {
        let enabledValues = ["YES", "true", "1"]
        for value in enabledValues {
            let result = AuthenticationService.parseCloudKitEnabledFlag(value)
            XCTAssertTrue(result.enabled, "Expected \(value) to parse as enabled")
            XCTAssertEqual(result.reason, .enabled)
            XCTAssertEqual(result.rawType, "String")
        }

        let disabledValues = ["NO", "false", "0"]
        for value in disabledValues {
            let result = AuthenticationService.parseCloudKitEnabledFlag(value)
            XCTAssertFalse(result.enabled, "Expected \(value) to parse as disabled")
            XCTAssertEqual(result.reason, .disabledByFlag)
            XCTAssertEqual(result.rawType, "String")
        }
    }

    func testParseCloudKitEnabledFlagForMissingAndInvalidValues() {
        let missingResult = AuthenticationService.parseCloudKitEnabledFlag(nil)
        XCTAssertFalse(missingResult.enabled)
        XCTAssertEqual(missingResult.reason, .missingKey)
        XCTAssertNil(missingResult.rawType)

        let invalidStringResult = AuthenticationService.parseCloudKitEnabledFlag("enabled")
        XCTAssertFalse(invalidStringResult.enabled)
        XCTAssertEqual(invalidStringResult.reason, .parseFailure)
        XCTAssertEqual(invalidStringResult.rawType, "String")
    }
}
