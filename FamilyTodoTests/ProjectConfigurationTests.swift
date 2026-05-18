import XCTest

final class ProjectConfigurationTests: XCTestCase {
    func testHousePulseTargetSupportsIPhoneAndIPad() throws {
        let projectContents = try loadProjectFile()

        XCTAssertTrue(
            projectContents.contains("TARGETED_DEVICE_FAMILY = \"1,2\";"),
            "Expected HousePulse target to be configured as a universal iPhone+iPad app."
        )
    }

    func testHousePulseTargetDoesNotForceFullScreen() throws {
        let projectContents = try loadProjectFile()

        XCTAssertFalse(
            projectContents.contains("INFOPLIST_KEY_UIRequiresFullScreen = YES;"),
            "Expected HousePulse target to allow native iPad window sizing."
        )
    }

    func testHousePulseTargetDefinesSupportedInterfaceOrientations() throws {
        let projectContents = try loadProjectFile()

        XCTAssertTrue(
            projectContents.contains(
                "INFOPLIST_KEY_UISupportedInterfaceOrientations = \"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";"
            ),
            "Expected explicit iPhone interface orientations for the universal target."
        )
        XCTAssertTrue(
            projectContents.contains(
                "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = \"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";"
            ),
            "Expected explicit iPad multitasking orientations for the universal target."
        )
    }

    func testMarketingVersionIsReadyForTestFlight14() throws {
        let projectContents = try loadProjectFile()

        XCTAssertTrue(projectContents.contains("MARKETING_VERSION = 1.4;"))
        XCTAssertFalse(projectContents.contains("MARKETING_VERSION = 1.3;"))
    }

    func testVisiblePremiumCopyUsesDwelloProBranding() throws {
        let repoRootURL = repoRootURL()
        let visibleSourceFiles = [
            "FamilyTodo/Views/MoreView.swift",
            "FamilyTodo/Views/SettingsView.swift",
            "FamilyTodo/Views/BacklogView.swift",
            "FamilyTodo/Views/BundlesManagementView.swift",
            "FamilyTodo/Views/ShoppingListView.swift",
            "FamilyTodo/Views/HouseholdSettingsView.swift",
            "FamilyTodo/Views/Components/PremiumUpsellSheet.swift",
            "FamilyTodo/Views/Components/ProBadgeView.swift",
        ]

        let combinedCopy = try visibleSourceFiles
            .map { path in
                try String(contentsOf: repoRootURL.appendingPathComponent(path), encoding: .utf8)
            }
            .joined(separator: "\n")

        XCTAssertTrue(combinedCopy.contains("Dwello Pro"))
        XCTAssertFalse(combinedCopy.contains("Dwello Plus"))
        XCTAssertFalse(combinedCopy.contains("HousePulse"))
    }

    func testPremiumLimitUIUsesContextualUpsellInsteadOfNativeAlertHelper() throws {
        let repoRootURL = repoRootURL()
        let sourceFiles = [
            "FamilyTodo/Services/SubscriptionManager.swift",
            "FamilyTodo/Views/MoreView.swift",
            "FamilyTodo/Views/SettingsView.swift",
            "FamilyTodo/Views/BacklogView.swift",
            "FamilyTodo/Views/BundlesManagementView.swift",
            "FamilyTodo/Views/ShoppingListView.swift",
            "FamilyTodo/Views/HouseholdSettingsView.swift",
        ]

        let combinedSource = try sourceFiles
            .map { path in
                try String(contentsOf: repoRootURL.appendingPathComponent(path), encoding: .utf8)
            }
            .joined(separator: "\n")

        XCTAssertTrue(combinedSource.contains("presentUpsell"))
        XCTAssertFalse(combinedSource.contains("premiumFeaturePrompt"))
        XCTAssertFalse(combinedSource.contains("premiumFeaturePromptAlert"))
    }

    private func loadProjectFile() throws -> String {
        let projectURL = repoRootURL()
            .appendingPathComponent("FamilyTodo.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        return try String(contentsOf: projectURL, encoding: .utf8)
    }

    private func repoRootURL() -> URL {
        let testsDirectoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        return testsDirectoryURL.deletingLastPathComponent()
    }
}
