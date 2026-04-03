import CloudKit
import Combine
@testable import HousePulse
import SwiftUI
import UIKit
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

    func testShoppingTabTitleIsShortenedToShop() {
        XCTAssertEqual(AppTab.shopping.title, "Shop")
    }
}

@MainActor
final class ThemeStoreTests: XCTestCase {
    private let managedKeys = [
        "themePreset",
        "appearanceMode",
        "tabTintColor",
        "retroFontScale",
        "paperFontScale",
        "systemFontScale",
    ]

    private var storedDefaults: [String: Any] = [:]

    override func setUp() {
        super.setUp()

        let defaults = UserDefaults.standard
        storedDefaults = [:]

        for key in managedKeys {
            if let value = defaults.object(forKey: key) {
                storedDefaults[key] = value
            } else {
                defaults.removeObject(forKey: key)
            }
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in managedKeys {
            if let value = storedDefaults[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        storedDefaults = [:]
        super.tearDown()
    }

    func testLegacyRetroRawValueMapsToRetroDark() {
        XCTAssertEqual(ThemePreset(rawValue: "retro"), .retroDark)
    }

    func testRetroLightRawValueMapsToRetroLight() {
        XCTAssertEqual(ThemePreset(rawValue: "retroLight"), .retroLight)
    }

    func testRetroThemesShareTypographyAndForceExpectedColorSchemes() {
        let store = ThemeStore()
        store.retroFontScale = .large

        store.preset = .retroDark
        let darkFont = store.uiFont(for: .buttonLabel)

        XCTAssertTrue(store.isRetroFamily)
        XCTAssertEqual(store.colorScheme, .dark)

        store.preset = .retroLight
        let lightFont = store.uiFont(for: .buttonLabel)

        XCTAssertTrue(store.isRetroFamily)
        XCTAssertEqual(store.colorScheme, .light)
        XCTAssertEqual(lightFont.fontName, darkFont.fontName)
        XCTAssertEqual(lightFont.pointSize, darkFont.pointSize, accuracy: 0.01)
    }

    func testRetroThemesUseBuiltInAccentInsteadOfSelectedTabTint() {
        let store = ThemeStore()
        store.tabTintColor = .pink

        store.preset = .retroDark
        assertColor(
            UIColor(store.resolvedTabTint),
            matches: UIColor(AppColors.palette(for: .retroDark).accent)
        )

        store.preset = .retroLight
        assertColor(
            UIColor(store.resolvedTabTint),
            matches: UIColor(AppColors.palette(for: .retroLight).accent)
        )

        let foreground = UIColor(
            store.foregroundOnAccent(
                for: store.resolvedTabTint,
                colorScheme: store.colorScheme
            )
        )
        assertColor(foreground, matches: .black)
    }

    func testInactiveTabBarColorUsesBlackForLightTheme() {
        let store = ThemeStore()
        store.unifiedTheme = .light

        let inactiveColor = TabBarTypographyManager.inactiveItemColor(
            themeStore: store,
            traitCollection: UITraitCollection(userInterfaceStyle: .light)
        )

        assertColor(inactiveColor, matches: .black)
    }

    func testInactiveTabBarColorUsesWhiteForDarkTheme() {
        let store = ThemeStore()
        store.unifiedTheme = .dark

        let inactiveColor = TabBarTypographyManager.inactiveItemColor(
            themeStore: store,
            traitCollection: UITraitCollection(userInterfaceStyle: .dark)
        )

        assertColor(inactiveColor, matches: .white)
    }

    func testInactiveTabBarColorUsesTraitCollectionForAutoTheme() {
        let store = ThemeStore()
        store.unifiedTheme = .auto

        let lightInactiveColor = TabBarTypographyManager.inactiveItemColor(
            themeStore: store,
            traitCollection: UITraitCollection(userInterfaceStyle: .light)
        )
        let darkInactiveColor = TabBarTypographyManager.inactiveItemColor(
            themeStore: store,
            traitCollection: UITraitCollection(userInterfaceStyle: .dark)
        )

        assertColor(lightInactiveColor, matches: .black)
        assertColor(darkInactiveColor, matches: .white)
    }

    func testInactiveTabBarColorUsesPaperInkColorForPaperTheme() {
        let store = ThemeStore()
        store.unifiedTheme = .paper

        let inactiveColor = TabBarTypographyManager.inactiveItemColor(
            themeStore: store,
            traitCollection: UITraitCollection(userInterfaceStyle: .light)
        )

        assertColor(inactiveColor, matches: UIColor(store.contentPrimaryColor))
    }

    func testReconcileRepairsCorruptedInactiveTintOnSameTabBarController() {
        let store = ThemeStore()
        store.unifiedTheme = .light

        let controller = makeTabBarController()

        TabBarTypographyManager.reconcile(
            themeStore: store,
            tabBarController: controller,
            selectedIndex: 1
        )

        controller.tabBar.unselectedItemTintColor = .gray
        controller.tabBar.standardAppearance.stackedLayoutAppearance.normal.iconColor = .gray
        var corruptedTitleAttributes =
            controller.tabBar.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes
        corruptedTitleAttributes[.foregroundColor] = UIColor.gray
        controller.tabBar.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes =
            corruptedTitleAttributes

        TabBarTypographyManager.reconcile(
            themeStore: store,
            tabBarController: controller,
            selectedIndex: 1
        )

        assertColor(controller.tabBar.unselectedItemTintColor ?? .clear, matches: .black)
        XCTAssertEqual(controller.selectedIndex, 1)
        assertColor(
            controller.tabBar.standardAppearance.stackedLayoutAppearance.normal.iconColor ?? .clear,
            matches: .black
        )
    }

    func testReconcileIsStableAcrossRepeatedCalls() {
        let store = ThemeStore()
        store.unifiedTheme = .dark

        let controller = makeTabBarController()

        TabBarTypographyManager.reconcile(
            themeStore: store,
            tabBarController: controller,
            selectedIndex: 2
        )
        let firstNormalColor = controller.tabBar.unselectedItemTintColor
        let firstSelectedColor = controller.tabBar.tintColor

        TabBarTypographyManager.reconcile(
            themeStore: store,
            tabBarController: controller,
            selectedIndex: 2
        )

        assertColor(firstNormalColor ?? .clear, matches: controller.tabBar.unselectedItemTintColor ?? .clear)
        assertColor(firstSelectedColor ?? .clear, matches: controller.tabBar.tintColor ?? .clear)
        XCTAssertEqual(controller.selectedIndex, 2)
    }

    private func makeTabBarController() -> UITabBarController {
        let controller = UITabBarController()
        let viewControllers = AppTab.allCases.map { tab -> UIViewController in
            let viewController = UIViewController()
            viewController.tabBarItem = UITabBarItem(
                title: tab.title,
                image: UIImage(systemName: tab.icon),
                selectedImage: UIImage(systemName: tab.activeIcon)
            )
            return viewController
        }
        controller.setViewControllers(viewControllers, animated: false)
        controller.loadViewIfNeeded()
        return controller
    }

    private func assertColor(
        _ actual: UIColor,
        matches expected: UIColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualComponents = rgbaComponents(for: actual)
        let expectedComponents = rgbaComponents(for: expected)

        XCTAssertEqual(actualComponents.red, expectedComponents.red, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actualComponents.green, expectedComponents.green, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actualComponents.blue, expectedComponents.blue, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actualComponents.alpha, expectedComponents.alpha, accuracy: 0.01, file: file, line: line)
    }

    private struct RGBAComponents {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private func rgbaComponents(for color: UIColor) -> RGBAComponents {
        var red = CGFloat.zero
        var green = CGFloat.zero
        var blue = CGFloat.zero
        var alpha = CGFloat.zero
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGBAComponents(red: red, green: green, blue: blue, alpha: alpha)
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

    func testAuthenticatedSessionNeedsDisplayNameConfirmationUntilConfirmed() async {
        let authService = TestAuthenticationService()
        let session = UserSession(authService: authService, userDefaults: makeUserDefaults())

        let user = AuthenticationService.AuthenticatedUser(
            id: "cloudkit-user-2",
            appleUserID: "apple-user-2",
            email: nil,
            displayName: nil,
            givenName: nil,
            familyName: nil
        )
        authService.currentUser = user
        authService.authenticationState = .authenticated(userID: user.id)
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(session.needsDisplayNamePrompt)
        XCTAssertNil(session.confirmedMembershipDisplayName)

        session.confirmDisplayName("Tester")

        XCTAssertFalse(session.needsDisplayNamePrompt)
        XCTAssertEqual(session.displayName, "Tester")
        XCTAssertEqual(session.confirmedMembershipDisplayName, "Tester")
    }

    func testSuggestedDisplayNameForPromptUsesAvailableAuthNameWithoutAutoConfirming() async {
        let authService = TestAuthenticationService()
        let session = UserSession(authService: authService, userDefaults: makeUserDefaults())

        let user = AuthenticationService.AuthenticatedUser(
            id: "cloudkit-user-3",
            appleUserID: "apple-user-3",
            email: nil,
            displayName: "Taylor",
            givenName: "Taylor",
            familyName: "Swift"
        )
        authService.currentUser = user
        authService.authenticationState = .authenticated(userID: user.id)
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(session.needsDisplayNamePrompt)
        XCTAssertEqual(session.suggestedDisplayNameForPrompt, "Taylor")
        XCTAssertNil(session.confirmedMembershipDisplayName)
    }

    func testLocalAppResetClearsPersistedDisplayNameAndHouseholdSelection() {
        let defaults = makeUserDefaults()
        defaults.set("household-id", forKey: "currentHouseholdID")
        defaults.set(true, forKey: "signedInSessionEnabled")
        defaults.set("cloud-user", forKey: "lastSignedInUserId")
        defaults.set(
            ["cloud-user": "Wojtek"],
            forKey: "preferredDisplayNameByUserId"
        )

        LocalAppReset.clearUserDefaults(defaults)

        XCTAssertNil(defaults.object(forKey: "currentHouseholdID"))
        XCTAssertNil(defaults.object(forKey: "signedInSessionEnabled"))
        XCTAssertNil(defaults.object(forKey: "lastSignedInUserId"))
        XCTAssertNil(defaults.object(forKey: "preferredDisplayNameByUserId"))
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
        } else {
            XCTAssertTrue(snapshot.cloudKitEnabledFallbackApplied)
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

@MainActor
final class CloudKitDiagnosticsStateTests: XCTestCase {
    private var diagnosticsDefaults: UserDefaults!
    private var diagnosticsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        diagnosticsSuiteName = "CloudKitDiagnosticsStateTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: diagnosticsSuiteName) else {
            XCTFail("Failed to create diagnostics defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: diagnosticsSuiteName)
        diagnosticsDefaults = defaults
        CloudKitDiagnosticsState.shared.clear()
    }

    override func tearDown() async throws {
        diagnosticsDefaults?.removePersistentDomain(forName: diagnosticsSuiteName)
        diagnosticsDefaults = nil
        diagnosticsSuiteName = nil
        try await super.tearDown()
    }

    func testRecordFormatsFullCloudKitPayload() {
        let error = NSError(domain: "CKErrorDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Failed to save record.",
        ])

        CloudKitDiagnosticsState.shared.record(error: error, operation: "createShare")

        let payload = CloudKitDiagnosticsState.shared.lastCloudKitError
        XCTAssertNotNil(payload)
        XCTAssertTrue(payload?.contains("operation=createShare") == true)
        XCTAssertTrue(payload?.contains("domain=CKErrorDomain") == true)
        XCTAssertTrue(payload?.contains("code=42") == true)
        XCTAssertTrue(payload?.contains("description=Failed to save record.") == true)
        XCTAssertTrue(payload?.contains("reflecting=Error Domain=CKErrorDomain Code=42") == true)
        XCTAssertEqual(CloudKitDiagnosticsState.shared.lastCloudKitOperation, "createShare")
        XCTAssertNotNil(CloudKitDiagnosticsState.shared.lastCloudKitErrorTimestampISO8601)
    }

    func testClearRemovesDiagnosticsPayload() {
        let error = NSError(domain: "CKErrorDomain", code: 1, userInfo: nil)
        CloudKitDiagnosticsState.shared.record(error: error, operation: "saveHousehold")
        CloudKitDiagnosticsState.shared.recordProgress(operation: "remotePush type=recordZone")

        CloudKitDiagnosticsState.shared.clear()

        XCTAssertNil(CloudKitDiagnosticsState.shared.lastCloudKitError)
        XCTAssertNil(CloudKitDiagnosticsState.shared.lastCloudKitOperation)
        XCTAssertNil(CloudKitDiagnosticsState.shared.lastCloudKitErrorTimestampISO8601)
        XCTAssertNil(CloudKitDiagnosticsState.shared.lastCloudKitProgressOperation)
        XCTAssertNil(CloudKitDiagnosticsState.shared.lastCloudKitProgressTimestampISO8601)
        XCTAssertTrue(CloudKitDiagnosticsState.shared.entries.isEmpty)
    }

    func testRecordKeepsCreateShareStageOperationName() {
        CloudKitDiagnosticsState.shared.record(
            error: CloudKitManager.CloudKitManagerError.shareNotCreated,
            operation: "createShare.final"
        )

        let payload = CloudKitDiagnosticsState.shared.lastCloudKitError
        XCTAssertNotNil(payload)
        XCTAssertTrue(payload?.contains("operation=createShare.final") == true)
        XCTAssertTrue(payload?.contains("Failed to create share") == true)
        XCTAssertEqual(CloudKitDiagnosticsState.shared.lastCloudKitOperation, "createShare.final")
    }

    func testRecordProgressAppendsDiagnosticsHistoryEntry() {
        CloudKitDiagnosticsState.shared.recordProgress(
            operation: "remoteSync stage=followUpPlan direction=participantToOwner"
        )

        XCTAssertEqual(
            CloudKitDiagnosticsState.shared.lastCloudKitProgressOperation,
            "remoteSync stage=followUpPlan direction=participantToOwner"
        )
        XCTAssertEqual(CloudKitDiagnosticsState.shared.entries.count, 1)
        XCTAssertEqual(CloudKitDiagnosticsState.shared.entries.first?.kind, .progress)
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.diagnosticsReport.contains(
                "remoteSync stage=followUpPlan direction=participantToOwner"
            )
        )
    }

    func testRecordErrorAppendsErrorHistoryEntry() {
        let error = NSError(domain: "CKErrorDomain", code: 13, userInfo: [
            NSLocalizedDescriptionKey: "Permission denied.",
        ])

        CloudKitDiagnosticsState.shared.record(error: error, operation: "createZoneSubscription")

        XCTAssertEqual(CloudKitDiagnosticsState.shared.entries.count, 1)
        XCTAssertEqual(CloudKitDiagnosticsState.shared.entries.first?.kind, .error)
        XCTAssertTrue(
            CloudKitDiagnosticsState.shared.diagnosticsReport.contains(
                "operation=createZoneSubscription"
            )
        )
    }

    func testDiagnosticsEntriesPersistAcrossFreshStateInitialization() {
        let firstState = CloudKitDiagnosticsState(userDefaults: diagnosticsDefaults)
        firstState.recordProgress(operation: "push.received type=recordZone")
        firstState.record(error: NSError(domain: "CKErrorDomain", code: 7), operation: "saveRecord")

        let restoredState = CloudKitDiagnosticsState(userDefaults: diagnosticsDefaults)

        XCTAssertEqual(restoredState.entries.count, 2)
        XCTAssertEqual(restoredState.entries.first?.kind, .progress)
        XCTAssertEqual(restoredState.entries.last?.kind, .error)
        XCTAssertTrue(restoredState.hasVisibleDiagnostics)
        XCTAssertTrue(restoredState.diagnosticsReport.contains("push.received type=recordZone"))
        XCTAssertTrue(restoredState.diagnosticsReport.contains("operation=saveRecord"))
    }

    func testClearRemovesPersistedDiagnosticsEntries() {
        let firstState = CloudKitDiagnosticsState(userDefaults: diagnosticsDefaults)
        firstState.recordProgress(operation: "snapshot.load.started")
        XCTAssertEqual(firstState.entries.count, 1)

        firstState.clear()

        let restoredState = CloudKitDiagnosticsState(userDefaults: diagnosticsDefaults)
        XCTAssertTrue(restoredState.entries.isEmpty)
        XCTAssertFalse(restoredState.hasVisibleDiagnostics)
    }

    func testTriggerSummaryTracksSubscriptionAndPushHealth() {
        let diagnostics = CloudKitDiagnosticsState(userDefaults: diagnosticsDefaults)

        diagnostics.recordProgress(
            operation: "subscription.configure.request source=taskKey role=owner scope=ownerPrivate householdId=household-1"
        )
        diagnostics.recordProgress(
            operation: "subscription.plan householdId=household-1 scope=ownerPrivate databaseIds=private-database-changes zoneId=household-zone-ownerPrivate-household-1"
        )
        diagnostics.recordProgress(operation: "push.registration.succeeded tokenLength=64")
        diagnostics.recordProgress(operation: "push.received type=database")
        diagnostics.recordProgress(
            operation: "remotePush type=4 declaredScope=private effectiveScope=private currentSyncContextAvailable=true inferredFromSyncContext=false handlerInstalled=true queuedBehindActiveRefresh=false willInvokeHandler=true role=owner householdId=household-1 appState=active scopeResolution=declared"
        )
        diagnostics.recordProgress(
            operation: "sync.scheduler.started reason=appBecameActive ownerFallback=true intervalNs=15000000000 maxPasses=40"
        )
        diagnostics.recordProgress(
            operation: "sync.pass.completed reason=foregroundRepairWindow triggerSource=foregroundRepair fetchResult=newData direction=unknown eventCount=1"
        )

        XCTAssertEqual(diagnostics.triggerSummary.syncRole, "owner")
        XCTAssertEqual(diagnostics.triggerSummary.syncScope, "ownerPrivate")
        XCTAssertEqual(diagnostics.triggerSummary.subscriptionRequestSource, "taskKey")
        XCTAssertEqual(diagnostics.triggerSummary.subscriptionConfigurationStatus, "requested")
        XCTAssertEqual(
            diagnostics.triggerSummary.subscriptionPlanDatabaseIDs,
            ["private-database-changes"]
        )
        XCTAssertEqual(
            diagnostics.triggerSummary.subscriptionPlanZoneID,
            "household-zone-ownerPrivate-household-1"
        )
        XCTAssertEqual(diagnostics.triggerSummary.pushRegistrationStatus, "succeeded")
        XCTAssertEqual(diagnostics.triggerSummary.pushReceivedCount, 1)
        XCTAssertEqual(diagnostics.triggerSummary.remotePushCount, 1)
        XCTAssertEqual(diagnostics.triggerSummary.remoteHandlerInvocationCount, 1)
        XCTAssertEqual(diagnostics.triggerSummary.lastOwnerFallbackReason, "appBecameActive")
        XCTAssertEqual(diagnostics.triggerSummary.lastFetchResult, "newData")
    }

    func testTriggerSummaryRestoresFromPersistedEntries() {
        let firstState = CloudKitDiagnosticsState(userDefaults: diagnosticsDefaults)
        firstState.recordProgress(
            operation: "subscription.configure.completed source=taskKey role=participant scope=participantShared householdId=household-2"
        )
        firstState.recordProgress(operation: "push.registration.failed description=network_error")
        firstState.recordProgress(
            operation: "sync.scheduler.ownerFallbackDecision eligible=false role=participant scope=participantShared direction=unknown reason=appBecameActive activeMembers=2 appState=active"
        )
        firstState.recordProgress(
            operation: "sync.pass.completed reason=appBecameActive triggerSource=foregroundRepair fetchResult=noData direction=unknown eventCount=0"
        )

        let restoredState = CloudKitDiagnosticsState(userDefaults: diagnosticsDefaults)

        XCTAssertEqual(restoredState.triggerSummary.syncRole, "participant")
        XCTAssertEqual(restoredState.triggerSummary.syncScope, "participantShared")
        XCTAssertEqual(restoredState.triggerSummary.subscriptionConfigurationStatus, "configured")
        XCTAssertEqual(restoredState.triggerSummary.pushRegistrationStatus, "failed")
        XCTAssertEqual(restoredState.triggerSummary.lastFetchResult, "noData")
    }

    func testNotificationDiagnosticsReportFiltersOutSyncNoise() {
        let diagnostics = CloudKitDiagnosticsState(userDefaults: diagnosticsDefaults)
        diagnostics.recordProgress(
            operation: "sync.pass.completed reason=foregroundRepairWindow triggerSource=foregroundRepair fetchResult=newData direction=unknown eventCount=1"
        )
        diagnostics.recordProgress(
            operation: "notification.sharedActivity.suppressed householdId=household-1 domain=shopping reason=foregroundActive"
        )

        XCTAssertEqual(diagnostics.notificationEntries.count, 1)
        XCTAssertTrue(
            diagnostics.notificationDiagnosticsReport.contains(
                "notification.sharedActivity.suppressed householdId=household-1"
            )
        )
        XCTAssertFalse(
            diagnostics.notificationDiagnosticsReport.contains(
                "sync.pass.completed"
            )
        )
    }

    func testNotificationDiagnosticsFilterEmptyMessageIsSpecific() {
        let diagnostics = CloudKitDiagnosticsState(userDefaults: diagnosticsDefaults)

        XCTAssertEqual(
            diagnostics.diagnosticsReport(for: .notifications),
            "No notification diagnostics recorded."
        )
        XCTAssertFalse(diagnostics.hasNotificationDiagnostics)
    }
}

@MainActor
final class ShareAcceptanceCoordinatorTests: XCTestCase {
    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "ShareAcceptanceCoordinatorTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return .standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testEnqueueInviteURLPersistsAndRestoresPendingInvite() throws {
        let defaults = makeUserDefaults()
        let coordinator = ShareAcceptanceCoordinator(userDefaults: defaults)
        let inviteURL = try XCTUnwrap(URL(string: "https://www.icloud.com/share/AbCdEf123"))

        coordinator.enqueue(inviteURL: inviteURL)

        XCTAssertEqual(coordinator.pendingInviteCode, inviteURL.absoluteString)
        XCTAssertEqual(coordinator.pendingSource, .onOpenURL)
        XCTAssertNotNil(coordinator.pendingTimestampISO8601)

        let restored = ShareAcceptanceCoordinator(userDefaults: defaults)
        XCTAssertEqual(restored.pendingInviteCode, inviteURL.absoluteString)
        XCTAssertEqual(restored.pendingSource, .onOpenURL)
        XCTAssertNotNil(restored.pendingTimestampISO8601)
    }

    func testClearPendingPersistentRemovesStoredInvite() {
        let defaults = makeUserDefaults()
        let coordinator = ShareAcceptanceCoordinator(userDefaults: defaults)

        coordinator.enqueue(rawInviteCode: "ABCD1234")
        XCTAssertNotNil(defaults.string(forKey: "ShareAcceptanceCoordinator.pendingInviteCode"))

        coordinator.clearPendingPersistent()
        let restored = ShareAcceptanceCoordinator(userDefaults: defaults)
        XCTAssertNil(restored.pendingInviteCode)
    }
}

@MainActor
final class CelebrationManagerTests: XCTestCase {
    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "CelebrationManagerTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return .standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    func testDecideTaskCompletionUsesMilestonePriorityAtFive() {
        let defaults = makeUserDefaults()
        let now = Date(timeIntervalSince1970: 1_736_900_000)
        let manager = CelebrationManager(
            userDefaults: defaults,
            nowProvider: { now },
            randomInt: { _ in 1 }
        )

        let decision = manager.decideTaskCompletion(
            taskTitle: "Kitchen wipe-down",
            weeklyCompletedCount: 5,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(decision.tier, .milestone)
        XCTAssertEqual(decision.celebration.style, .milestone)
        XCTAssertNil(defaults.object(forKey: "celebrations.lastSurpriseAt"))
    }

    func testDecideTaskCompletionUsesMilestonePriorityAtTen() {
        let defaults = makeUserDefaults()
        let now = Date(timeIntervalSince1970: 1_736_910_000)
        let manager = CelebrationManager(
            userDefaults: defaults,
            nowProvider: { now },
            randomInt: { _ in 1 }
        )

        let decision = manager.decideTaskCompletion(
            taskTitle: "Laundry folded",
            weeklyCompletedCount: 10,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(decision.tier, .milestone)
        XCTAssertEqual(decision.celebration.style, .milestone)
    }

    func testDecideTaskCompletionUsesSurpriseWhenEligibleAndRandomHits() {
        let defaults = makeUserDefaults()
        let now = Date(timeIntervalSince1970: 1_736_920_000)
        let manager = CelebrationManager(
            userDefaults: defaults,
            nowProvider: { now },
            randomInt: { _ in 1 }
        )

        let decision = manager.decideTaskCompletion(
            taskTitle: "Trash out",
            weeklyCompletedCount: 2,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(decision.tier, .surprise)
        XCTAssertEqual(decision.celebration.style, .normal)
        XCTAssertEqual(
            defaults.object(forKey: "celebrations.lastSurpriseAt") as? Date,
            now
        )
    }

    func testDecideTaskCompletionSkipsSurpriseWhenInsideWeeklyCap() {
        let defaults = makeUserDefaults()
        let now = Date(timeIntervalSince1970: 1_736_930_000)
        let recentSurpriseDate = now.addingTimeInterval(-3 * 86400)
        defaults.set(recentSurpriseDate, forKey: "celebrations.lastSurpriseAt")
        let manager = CelebrationManager(
            userDefaults: defaults,
            nowProvider: { now },
            randomInt: { _ in 1 }
        )

        let decision = manager.decideTaskCompletion(
            taskTitle: "Vacuum room",
            weeklyCompletedCount: 2,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(decision.tier, .fallback)
        XCTAssertEqual(decision.celebration.style, .normal)
        XCTAssertEqual(
            defaults.object(forKey: "celebrations.lastSurpriseAt") as? Date,
            recentSurpriseDate
        )
    }

    func testDecideTaskCompletionUsesFallbackWhenRandomMisses() {
        let defaults = makeUserDefaults()
        let now = Date(timeIntervalSince1970: 1_736_940_000)
        let manager = CelebrationManager(
            userDefaults: defaults,
            nowProvider: { now },
            randomInt: { _ in 7 }
        )

        let decision = manager.decideTaskCompletion(
            taskTitle: "Water plants",
            weeklyCompletedCount: 3,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(decision.tier, .fallback)
        XCTAssertEqual(decision.celebration.style, .normal)
        XCTAssertNil(defaults.object(forKey: "celebrations.lastSurpriseAt"))
    }

    func testResetForDevelopmentClearsActiveCelebrationConfettiAndCadence() {
        let defaults = makeUserDefaults()
        defaults.set(Date(timeIntervalSince1970: 1_736_950_000), forKey: "celebrations.lastSurpriseAt")
        let manager = CelebrationManager(userDefaults: defaults)

        manager.triggerConfetti()
        manager.celebrateAllTasksComplete()

        XCTAssertNotNil(manager.activeCelebration)
        XCTAssertGreaterThan(manager.confettiTrigger, 0)

        manager.resetForDevelopment()

        XCTAssertNil(manager.activeCelebration)
        XCTAssertEqual(manager.confettiTrigger, 0)
        XCTAssertNil(defaults.object(forKey: "celebrations.lastSurpriseAt"))
    }
}
