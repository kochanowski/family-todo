@testable import HousePulse
import XCTest

final class AppTipVisibilityTests: XCTestCase {
    func testShoppingTipPriorityPrefersFirstAddOnFreshHousehold() {
        let tip = AppTipVisibility.shoppingTip(
            hasActiveItems: false,
            hasRecentItems: false,
            hasBundles: false,
            hasQuickAddBundles: false,
            isRapidEntryActive: false,
            isKeyboardVisible: false,
            hasActiveToast: false,
            hasPresentedSheet: false,
            hasCompletedFirstAdd: false,
            hasCompletedRecentPurchases: false,
            hasCompletedBundlesLocation: false,
            hasCompletedBundleQuickAdd: false
        )

        XCTAssertEqual(tip, .firstAdd)
    }

    func testShoppingTipMovesToRecentPurchasesAfterFirstBoughtItem() {
        let tip = AppTipVisibility.shoppingTip(
            hasActiveItems: true,
            hasRecentItems: true,
            hasBundles: false,
            hasQuickAddBundles: false,
            isRapidEntryActive: false,
            isKeyboardVisible: false,
            hasActiveToast: false,
            hasPresentedSheet: false,
            hasCompletedFirstAdd: true,
            hasCompletedRecentPurchases: false,
            hasCompletedBundlesLocation: false,
            hasCompletedBundleQuickAdd: false
        )

        XCTAssertEqual(tip, .recentPurchases)
    }

    func testShoppingTipFallsBackToBundlesAndQuickAddInOrder() {
        let bundlesTip = AppTipVisibility.shoppingTip(
            hasActiveItems: true,
            hasRecentItems: false,
            hasBundles: false,
            hasQuickAddBundles: false,
            isRapidEntryActive: false,
            isKeyboardVisible: false,
            hasActiveToast: false,
            hasPresentedSheet: false,
            hasCompletedFirstAdd: true,
            hasCompletedRecentPurchases: true,
            hasCompletedBundlesLocation: false,
            hasCompletedBundleQuickAdd: false
        )

        XCTAssertEqual(bundlesTip, .bundlesLocation)

        let quickAddTip = AppTipVisibility.shoppingTip(
            hasActiveItems: true,
            hasRecentItems: false,
            hasBundles: true,
            hasQuickAddBundles: true,
            isRapidEntryActive: false,
            isKeyboardVisible: false,
            hasActiveToast: false,
            hasPresentedSheet: false,
            hasCompletedFirstAdd: true,
            hasCompletedRecentPurchases: true,
            hasCompletedBundlesLocation: true,
            hasCompletedBundleQuickAdd: false
        )

        XCTAssertEqual(quickAddTip, .bundleQuickAdd)
    }

    func testShoppingTipPrefersQuickAddWhenBundlesExist() {
        let tip = AppTipVisibility.shoppingTip(
            hasActiveItems: false,
            hasRecentItems: false,
            hasBundles: true,
            hasQuickAddBundles: true,
            isRapidEntryActive: false,
            isKeyboardVisible: false,
            hasActiveToast: false,
            hasPresentedSheet: false,
            hasCompletedFirstAdd: false,
            hasCompletedRecentPurchases: false,
            hasCompletedBundlesLocation: false,
            hasCompletedBundleQuickAdd: false
        )

        XCTAssertEqual(tip, .bundleQuickAdd)
    }

    func testIdeasTipPriorityIsSequential() {
        XCTAssertEqual(
            AppTipVisibility.ideasTip(
                hasCategories: false,
                hasVisibleIdeas: false,
                hasVisibleUnassignedIdea: false,
                hasVisibleAssignedIdea: false,
                hasActiveBanner: false,
                hasPresentedSheet: false,
                hasPendingDeletionToast: false,
                hasCompletedCreateCategory: false,
                hasCompletedAddIdea: false,
                hasCompletedAssignOwner: false,
                hasCompletedPromote: false
            ),
            .createCategory
        )

        XCTAssertEqual(
            AppTipVisibility.ideasTip(
                hasCategories: true,
                hasVisibleIdeas: false,
                hasVisibleUnassignedIdea: false,
                hasVisibleAssignedIdea: false,
                hasActiveBanner: false,
                hasPresentedSheet: false,
                hasPendingDeletionToast: false,
                hasCompletedCreateCategory: true,
                hasCompletedAddIdea: false,
                hasCompletedAssignOwner: false,
                hasCompletedPromote: false
            ),
            .addIdea
        )

        XCTAssertEqual(
            AppTipVisibility.ideasTip(
                hasCategories: true,
                hasVisibleIdeas: true,
                hasVisibleUnassignedIdea: true,
                hasVisibleAssignedIdea: false,
                hasActiveBanner: false,
                hasPresentedSheet: false,
                hasPendingDeletionToast: false,
                hasCompletedCreateCategory: true,
                hasCompletedAddIdea: true,
                hasCompletedAssignOwner: false,
                hasCompletedPromote: false
            ),
            .assignOwner
        )

        XCTAssertEqual(
            AppTipVisibility.ideasTip(
                hasCategories: true,
                hasVisibleIdeas: true,
                hasVisibleUnassignedIdea: false,
                hasVisibleAssignedIdea: true,
                hasActiveBanner: false,
                hasPresentedSheet: false,
                hasPendingDeletionToast: false,
                hasCompletedCreateCategory: true,
                hasCompletedAddIdea: true,
                hasCompletedAssignOwner: true,
                hasCompletedPromote: false
            ),
            .promote
        )
    }

    func testTaskSwipeActionsTipRequiresVisibleActiveBoardWithoutTransientState() {
        XCTAssertTrue(
            AppTipVisibility.shouldShowTaskSwipeActionsTip(
                isTasksTabSelected: true,
                isShowingActiveFilter: true,
                hasVisibleActiveTasks: true,
                isReordering: false,
                hasInlineBanner: false,
                hasPresentedSheet: false,
                hasPendingDeleteToast: false,
                isTaskCompletionAnimating: false,
                hasCompletedSwipeActionsTip: false
            )
        )

        XCTAssertFalse(
            AppTipVisibility.shouldShowTaskSwipeActionsTip(
                isTasksTabSelected: true,
                isShowingActiveFilter: true,
                hasVisibleActiveTasks: true,
                isReordering: false,
                hasInlineBanner: false,
                hasPresentedSheet: false,
                hasPendingDeleteToast: false,
                isTaskCompletionAnimating: false,
                hasCompletedSwipeActionsTip: true
            )
        )
    }
}
