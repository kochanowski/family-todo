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

    private func loadProjectFile() throws -> String {
        let testsDirectoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let repoRootURL = testsDirectoryURL.deletingLastPathComponent()
        let projectURL = repoRootURL
            .appendingPathComponent("FamilyTodo.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        return try String(contentsOf: projectURL, encoding: .utf8)
    }
}
