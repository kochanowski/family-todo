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
                hasCompletedAddIdea: false,
                hasCompletedAssignOwner: false,
                hasCompletedPromote: false,
                hasRecurringChores: true,
                hasCompletedRecurringChoresTip: true
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
                hasCompletedAddIdea: false,
                hasCompletedAssignOwner: false,
                hasCompletedPromote: false,
                hasRecurringChores: true,
                hasCompletedRecurringChoresTip: true
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
                hasCompletedAddIdea: true,
                hasCompletedAssignOwner: false,
                hasCompletedPromote: false,
                hasRecurringChores: true,
                hasCompletedRecurringChoresTip: true
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
                hasCompletedAddIdea: true,
                hasCompletedAssignOwner: true,
                hasCompletedPromote: false,
                hasRecurringChores: true,
                hasCompletedRecurringChoresTip: true
            ),
            .promote
        )
    }

    func testIdeasTipShowsRecurringDiscoveryAfterCategoryBeforeIdeas() {
        let tip = AppTipVisibility.ideasTip(
            hasCategories: true,
            hasVisibleIdeas: false,
            hasVisibleUnassignedIdea: false,
            hasVisibleAssignedIdea: false,
            hasActiveBanner: false,
            hasPresentedSheet: false,
            hasPendingDeletionToast: false,
            hasCompletedAddIdea: false,
            hasCompletedAssignOwner: false,
            hasCompletedPromote: false,
            hasRecurringChores: false,
            hasCompletedRecurringChoresTip: false
        )

        XCTAssertEqual(tip, .recurringChoresDiscover)
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

    func testBundleQuickAddTipAppearsWhenQuickAddBundlesAvailableRegardlessOfBundlesLocationCompletion() {
        let tip = AppTipVisibility.shoppingTip(
            hasActiveItems: true,
            hasRecentItems: false,
            hasBundles: true,
            hasQuickAddBundles: true,
            isRapidEntryActive: false,
            isKeyboardVisible: false,
            hasActiveToast: false,
            hasPresentedSheet: false,
            hasCompletedFirstAdd: false, // NOT completed
            hasCompletedRecentPurchases: false,
            hasCompletedBundlesLocation: false, // NOT completed either
            hasCompletedBundleQuickAdd: false
        )
        XCTAssertEqual(tip, .bundleQuickAdd)
    }

    func testBundleQuickAddTipSuppressedWhenBlockersActive() {
        // Active toast suppresses
        XCTAssertNil(AppTipVisibility.shoppingTip(
            hasActiveItems: true, hasRecentItems: false, hasBundles: true,
            hasQuickAddBundles: true, isRapidEntryActive: false,
            isKeyboardVisible: false, hasActiveToast: true, // BLOCKER
            hasPresentedSheet: false, hasCompletedFirstAdd: true,
            hasCompletedRecentPurchases: true, hasCompletedBundlesLocation: true,
            hasCompletedBundleQuickAdd: false
        ))

        // Presented sheet suppresses
        XCTAssertNil(AppTipVisibility.shoppingTip(
            hasActiveItems: true, hasRecentItems: false, hasBundles: true,
            hasQuickAddBundles: true, isRapidEntryActive: false,
            isKeyboardVisible: false, hasActiveToast: false,
            hasPresentedSheet: true, // BLOCKER
            hasCompletedFirstAdd: true, hasCompletedRecentPurchases: true,
            hasCompletedBundlesLocation: true, hasCompletedBundleQuickAdd: false
        ))

        // Rapid entry suppresses
        XCTAssertNil(AppTipVisibility.shoppingTip(
            hasActiveItems: true, hasRecentItems: false, hasBundles: true,
            hasQuickAddBundles: true, isRapidEntryActive: true, // BLOCKER
            isKeyboardVisible: false, hasActiveToast: false,
            hasPresentedSheet: false, hasCompletedFirstAdd: true,
            hasCompletedRecentPurchases: true, hasCompletedBundlesLocation: true,
            hasCompletedBundleQuickAdd: false
        ))
    }

    func testPromoteTipEligibleImmediatelyAfterAssignmentWithNoSuppression() {
        let tip = AppTipVisibility.ideasTip(
            hasCategories: true,
            hasVisibleIdeas: true,
            hasVisibleUnassignedIdea: false,
            hasVisibleAssignedIdea: true, // idea just got an assignee
            hasActiveBanner: false,
            hasPresentedSheet: false,
            hasPendingDeletionToast: false,
            hasCompletedAddIdea: true,
            hasCompletedAssignOwner: true, // assignment step done
            hasCompletedPromote: false,
            hasRecurringChores: true,
            hasCompletedRecurringChoresTip: true // not yet promoted
        )
        XCTAssertEqual(tip, .promote)
    }
}
