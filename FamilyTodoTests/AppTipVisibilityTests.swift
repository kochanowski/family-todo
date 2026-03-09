@testable import HousePulse
import XCTest

final class AppTipVisibilityTests: XCTestCase {
    func testShoppingBundleQuickAddTipRequiresRelevantQuickAddState() {
        XCTAssertTrue(
            AppTipVisibility.shouldShowShoppingBundleQuickAddTip(
                hasQuickAddBundles: true,
                isRapidEntryActive: false,
                isKeyboardVisible: false,
                hasActiveToast: false
            )
        )

        XCTAssertFalse(
            AppTipVisibility.shouldShowShoppingBundleQuickAddTip(
                hasQuickAddBundles: false,
                isRapidEntryActive: false,
                isKeyboardVisible: false,
                hasActiveToast: false
            )
        )

        XCTAssertFalse(
            AppTipVisibility.shouldShowShoppingBundleQuickAddTip(
                hasQuickAddBundles: true,
                isRapidEntryActive: true,
                isKeyboardVisible: false,
                hasActiveToast: false
            )
        )
    }

    func testIdeaPromotionTipWaitsForPromotableItemAndClearUI() {
        XCTAssertTrue(
            AppTipVisibility.shouldShowIdeaPromotionTip(
                hasPromotableVisibleItem: true,
                hasActiveBanner: false,
                hasPresentedSheet: false,
                hasPendingDeletionToast: false
            )
        )

        XCTAssertFalse(
            AppTipVisibility.shouldShowIdeaPromotionTip(
                hasPromotableVisibleItem: false,
                hasActiveBanner: false,
                hasPresentedSheet: false,
                hasPendingDeletionToast: false
            )
        )

        XCTAssertFalse(
            AppTipVisibility.shouldShowIdeaPromotionTip(
                hasPromotableVisibleItem: true,
                hasActiveBanner: false,
                hasPresentedSheet: true,
                hasPendingDeletionToast: false
            )
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
                isTaskCompletionAnimating: false
            )
        )

        XCTAssertFalse(
            AppTipVisibility.shouldShowTaskSwipeActionsTip(
                isTasksTabSelected: false,
                isShowingActiveFilter: true,
                hasVisibleActiveTasks: true,
                isReordering: false,
                hasInlineBanner: false,
                hasPresentedSheet: false,
                hasPendingDeleteToast: false,
                isTaskCompletionAnimating: false
            )
        )

        XCTAssertFalse(
            AppTipVisibility.shouldShowTaskSwipeActionsTip(
                isTasksTabSelected: true,
                isShowingActiveFilter: true,
                hasVisibleActiveTasks: true,
                isReordering: true,
                hasInlineBanner: false,
                hasPresentedSheet: false,
                hasPendingDeleteToast: false,
                isTaskCompletionAnimating: false
            )
        )
    }
}
