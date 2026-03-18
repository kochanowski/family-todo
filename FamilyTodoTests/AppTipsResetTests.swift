@testable import HousePulse
import XCTest

final class AppTipsResetTests: XCTestCase {
    private func makeUserDefaults() -> (suiteName: String, defaults: UserDefaults) {
        let suiteName = "AppTipsResetTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create UserDefaults suite for tests")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }

    func testResetForHardResetClearsProgressAndContextAndBumpsGeneration() {
        let userDefaults = makeUserDefaults()
        let defaults = userDefaults.defaults
        addTeardownBlock {
            defaults.removePersistentDomain(forName: userDefaults.suiteName)
        }

        defaults.set(true, forKey: AppTipProgressKey.shoppingFirstAddCompleted)
        defaults.set(true, forKey: AppTipProgressKey.ideasPromoteCompleted)
        defaults.set("signedIn|user-1|household-1", forKey: AppTipStorageKey.contextSignature)
        defaults.set(4, forKey: AppTips.runtimeGenerationDefaultsKey)

        AppTips.resetForHardReset(userDefaults: defaults)

        XCTAssertNil(defaults.object(forKey: AppTipProgressKey.shoppingFirstAddCompleted))
        XCTAssertNil(defaults.object(forKey: AppTipProgressKey.ideasPromoteCompleted))
        XCTAssertNil(defaults.object(forKey: AppTipStorageKey.contextSignature))
        XCTAssertEqual(defaults.bool(forKey: AppTipStorageKey.pendingHardResetBootstrap), true)
        XCTAssertEqual(defaults.integer(forKey: AppTips.runtimeGenerationDefaultsKey), 5)
    }
}
