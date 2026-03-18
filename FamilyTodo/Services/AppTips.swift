import Foundation
import SwiftUI

// swiftlint:disable file_length function_parameter_count

enum ShoppingOnboardingTip: Equatable {
    case firstAdd
    case recentPurchases
    case bundlesLocation
    case bundleQuickAdd
}

enum IdeasOnboardingTip: Equatable {
    case createCategory
    case addIdea
    case assignOwner
    case promote
}

enum AppTipProgressKey {
    static let shoppingFirstAddCompleted = "appTips.shopping.firstAddCompleted"
    static let shoppingRecentPurchasesCompleted = "appTips.shopping.recentPurchasesCompleted"
    static let shoppingBundlesLocationCompleted = "appTips.shopping.bundlesLocationCompleted"
    static let shoppingBundleQuickAddCompleted = "appTips.shopping.bundleQuickAddCompleted"
    static let ideasCreateCategoryCompleted = "appTips.ideas.createCategoryCompleted"
    static let ideasAddIdeaCompleted = "appTips.ideas.addIdeaCompleted"
    static let ideasAssignOwnerCompleted = "appTips.ideas.assignOwnerCompleted"
    static let ideasPromoteCompleted = "appTips.ideas.promoteCompleted"
    static let tasksSwipeActionsCompleted = "appTips.tasks.swipeActionsCompleted"

    static let all = [
        shoppingFirstAddCompleted,
        shoppingRecentPurchasesCompleted,
        shoppingBundlesLocationCompleted,
        shoppingBundleQuickAddCompleted,
        ideasCreateCategoryCompleted,
        ideasAddIdeaCompleted,
        ideasAssignOwnerCompleted,
        ideasPromoteCompleted,
        tasksSwipeActionsCompleted,
    ]
}

enum AppTipStorageKey {
    static let contextSignature = "appTips.contextSignature"
    static let runtimeGeneration = "appTips.runtimeGeneration"
    static let pendingHardResetBootstrap = "appTips.pendingHardResetBootstrap"
}

#if canImport(TipKit)
    import TipKit

    enum AppTips {
        private static var hasConfigured = false
        private static let defaults = UserDefaults.standard

        static var runtimeGenerationDefaultsKey: String {
            AppTipStorageKey.runtimeGeneration
        }

        static func configureIfNeeded(launchArguments: [String] = ProcessInfo.processInfo.arguments) {
            guard !hasConfigured else { return }
            hasConfigured = true

            guard #available(iOS 17, *) else { return }

            do {
                try Tips.configure([
                    .displayFrequency(.immediate),
                ])
                configureTestingOverridesIfNeeded(launchArguments: launchArguments)
            } catch {
                print("TipKit configure failed: \(error.localizedDescription)")
            }
        }

        static func syncContextIfNeeded(
            sessionMode: SessionMode,
            userId: String?,
            householdId: UUID?,
            launchArguments: [String] = ProcessInfo.processInfo.arguments
        ) {
            let newSignature = contextSignature(
                sessionMode: sessionMode,
                userId: userId,
                householdId: householdId
            )
            let previousSignature = defaults.string(forKey: AppTipStorageKey.contextSignature)
            let shouldForceBootstrap = defaults.bool(forKey: AppTipStorageKey.pendingHardResetBootstrap)
            guard shouldForceBootstrap || previousSignature != newSignature else { return }

            guard #available(iOS 17, *) else {
                clearOnboardingProgress()
                defaults.set(newSignature, forKey: AppTipStorageKey.contextSignature)
                defaults.removeObject(forKey: AppTipStorageKey.pendingHardResetBootstrap)
                return
            }

            do {
                try Tips.resetDatastore()
            } catch {
                print("TipKit context reset failed: \(error.localizedDescription)")
            }

            clearOnboardingProgress()
            bumpRuntimeGeneration()
            defaults.set(newSignature, forKey: AppTipStorageKey.contextSignature)
            defaults.removeObject(forKey: AppTipStorageKey.pendingHardResetBootstrap)
            hasConfigured = false
            configureIfNeeded(launchArguments: launchArguments)
            configureTestingOverridesIfNeeded(launchArguments: launchArguments)
        }

        static func resetDatastoreForTestingIfNeeded(
            launchArguments: [String] = ProcessInfo.processInfo.arguments
        ) {
            guard #available(iOS 17, *) else { return }
            guard launchArguments.contains("-uiTestMode"), launchArguments.contains("-resetData") else {
                return
            }

            do {
                try Tips.resetDatastore()
            } catch {
                print("TipKit reset failed: \(error.localizedDescription)")
            }

            clearOnboardingProgress()
            defaults.removeObject(forKey: AppTipStorageKey.contextSignature)
            defaults.removeObject(forKey: AppTipStorageKey.pendingHardResetBootstrap)
            bumpRuntimeGeneration()
            hasConfigured = false
        }

        static func resetForHardReset(userDefaults: UserDefaults = .standard) {
            if #available(iOS 17, *) {
                do {
                    try Tips.resetDatastore()
                } catch {
                    print("TipKit hard reset failed: \(error.localizedDescription)")
                }
            }

            clearOnboardingProgress(userDefaults: userDefaults)
            userDefaults.removeObject(forKey: AppTipStorageKey.contextSignature)
            userDefaults.set(true, forKey: AppTipStorageKey.pendingHardResetBootstrap)
            bumpRuntimeGeneration(userDefaults: userDefaults)
            hasConfigured = false
            configureIfNeeded()
        }

        static func resetForDevelopment() {
            if #available(iOS 17, *) {
                do {
                    try Tips.resetDatastore()
                } catch {
                    print("TipKit development reset failed: \(error.localizedDescription)")
                }
            }

            clearOnboardingProgress()
            defaults.removeObject(forKey: AppTipStorageKey.contextSignature)
            defaults.removeObject(forKey: AppTipStorageKey.pendingHardResetBootstrap)
            bumpRuntimeGeneration()
            hasConfigured = false
            configureIfNeeded()
        }

        static func donateShoppingFirstItemCreated() {
            markProgress(AppTipProgressKey.shoppingFirstAddCompleted)
            guard #available(iOS 17, *) else { return }
            AppTipEvents.shoppingFirstItemCreated.sendDonation()
        }

        static func donateShoppingRecentPurchasesOpened() {
            markProgress(AppTipProgressKey.shoppingRecentPurchasesCompleted)
            guard #available(iOS 17, *) else { return }
            AppTipEvents.shoppingRecentPurchasesOpened.sendDonation()
        }

        static func donateShoppingBundlesVisited() {
            markProgress(AppTipProgressKey.shoppingBundlesLocationCompleted)
            guard #available(iOS 17, *) else { return }
            AppTipEvents.shoppingBundlesVisited.sendDonation()
        }

        static func donateBundleQuickAddUsed() {
            markProgress(AppTipProgressKey.shoppingBundleQuickAddCompleted)
            guard #available(iOS 17, *) else { return }
            AppTipEvents.bundleQuickAddUsed.sendDonation()
        }

        static func donateIdeasCategoryCreated() {
            markProgress(AppTipProgressKey.ideasCreateCategoryCompleted)
            guard #available(iOS 17, *) else { return }
            AppTipEvents.ideasCategoryCreated.sendDonation()
        }

        static func donateIdeasFirstIdeaAdded() {
            markProgress(AppTipProgressKey.ideasAddIdeaCompleted)
            guard #available(iOS 17, *) else { return }
            AppTipEvents.ideasFirstIdeaAdded.sendDonation()
        }

        static func donateIdeasOwnerAssigned() {
            markProgress(AppTipProgressKey.ideasAssignOwnerCompleted)
            guard #available(iOS 17, *) else { return }
            AppTipEvents.ideasOwnerAssigned.sendDonation()
        }

        static func donateIdeaPromoted() {
            markProgress(AppTipProgressKey.ideasPromoteCompleted)
            guard #available(iOS 17, *) else { return }
            AppTipEvents.ideaPromoted.sendDonation()
        }

        static func donateTaskSwipeActionUsed() {
            markProgress(AppTipProgressKey.tasksSwipeActionsCompleted)
            guard #available(iOS 17, *) else { return }
            AppTipEvents.taskSwipeActionUsed.sendDonation()
        }

        static func clearOnboardingProgress(userDefaults: UserDefaults = .standard) {
            for key in AppTipProgressKey.all {
                userDefaults.removeObject(forKey: key)
            }
        }

        private static func contextSignature(
            sessionMode: SessionMode,
            userId: String?,
            householdId: UUID?
        ) -> String {
            [
                sessionMode.rawValue,
                userId ?? "none",
                householdId?.uuidString ?? "none",
            ].joined(separator: "|")
        }

        private static func markProgress(_ key: String) {
            defaults.set(true, forKey: key)
        }

        private static func bumpRuntimeGeneration(userDefaults: UserDefaults = .standard) {
            userDefaults.set(
                userDefaults.integer(forKey: AppTipStorageKey.runtimeGeneration) + 1,
                forKey: AppTipStorageKey.runtimeGeneration
            )
        }

        @available(iOS 17, *)
        private static func configureTestingOverridesIfNeeded(launchArguments: [String]) {
            if let tipTypes = testingTipTypes(for: launchArguments), !tipTypes.isEmpty {
                Tips.showTipsForTesting(tipTypes)
            }
        }

        @available(iOS 17, *)
        private static func testingTipTypes(for launchArguments: [String]) -> [any Tip.Type]? {
            guard let argumentIndex = launchArguments.firstIndex(of: "-showTipForTesting"),
                  argumentIndex + 1 < launchArguments.count
            else {
                return nil
            }

            switch launchArguments[argumentIndex + 1] {
            case "shopping", "shopping_quick_add":
                return [ShoppingBundleQuickAddTip.self]
            case "shopping_first_add":
                return [ShoppingFirstAddTip.self]
            case "shopping_recent":
                return [ShoppingRecentlyPurchasedTip.self]
            case "shopping_bundles":
                return [ShoppingBundlesLocationTip.self]
            case "ideas", "ideas_promote":
                return [IdeaPromotionTip.self]
            case "ideas_category":
                return [IdeasCreateCategoryTip.self]
            case "ideas_add":
                return [IdeasAddIdeaTip.self]
            case "ideas_assign":
                return [IdeasAssignOwnerTip.self]
            case "tasks":
                return [TaskSwipeActionsTip.self]
            default:
                return nil
            }
        }
    }

    @available(iOS 17, *)
    enum AppTipEvents {
        static let shoppingFirstItemCreated = Tips.Event(id: "shopping.firstItemCreated")
        static let shoppingRecentPurchasesOpened = Tips.Event(id: "shopping.recentPurchasesOpened")
        static let shoppingBundlesVisited = Tips.Event(id: "shopping.bundlesVisited")
        static let bundleQuickAddUsed = Tips.Event(id: "shopping.bundleQuickAddUsed")
        static let ideasCategoryCreated = Tips.Event(id: "backlog.categoryCreated")
        static let ideasFirstIdeaAdded = Tips.Event(id: "backlog.firstIdeaAdded")
        static let ideasOwnerAssigned = Tips.Event(id: "backlog.ownerAssigned")
        static let ideaPromoted = Tips.Event(id: "backlog.ideaPromoted")
        static let taskSwipeActionUsed = Tips.Event(id: "tasks.swipeActionUsed")
    }

    enum AppTipVisibility {
        static func shoppingTip(
            hasActiveItems: Bool,
            hasRecentItems: Bool,
            hasBundles: Bool,
            hasQuickAddBundles: Bool,
            isRapidEntryActive: Bool,
            isKeyboardVisible: Bool,
            hasActiveToast: Bool,
            hasPresentedSheet: Bool,
            hasCompletedFirstAdd: Bool,
            hasCompletedRecentPurchases: Bool,
            hasCompletedBundlesLocation: Bool,
            hasCompletedBundleQuickAdd: Bool
        ) -> ShoppingOnboardingTip? {
            guard !isRapidEntryActive,
                  !isKeyboardVisible,
                  !hasActiveToast,
                  !hasPresentedSheet
            else {
                return nil
            }

            if hasQuickAddBundles, !hasCompletedBundleQuickAdd {
                return .bundleQuickAdd
            }

            if !hasActiveItems, !hasRecentItems, !hasCompletedFirstAdd {
                return .firstAdd
            }

            if hasRecentItems, !hasCompletedRecentPurchases {
                return .recentPurchases
            }

            if hasActiveItems || hasRecentItems, !hasBundles, !hasCompletedBundlesLocation {
                return .bundlesLocation
            }

            return nil
        }

        static func ideasTip(
            hasCategories: Bool,
            hasVisibleIdeas: Bool,
            hasVisibleUnassignedIdea: Bool,
            hasVisibleAssignedIdea: Bool,
            hasActiveBanner: Bool,
            hasPresentedSheet: Bool,
            hasPendingDeletionToast: Bool,
            hasCompletedCreateCategory: Bool,
            hasCompletedAddIdea: Bool,
            hasCompletedAssignOwner: Bool,
            hasCompletedPromote: Bool
        ) -> IdeasOnboardingTip? {
            guard !hasActiveBanner,
                  !hasPresentedSheet,
                  !hasPendingDeletionToast
            else {
                return nil
            }

            if !hasCategories, !hasCompletedCreateCategory {
                return .createCategory
            }

            if hasCategories, !hasVisibleIdeas, !hasCompletedAddIdea {
                return .addIdea
            }

            if hasVisibleUnassignedIdea, !hasCompletedAssignOwner {
                return .assignOwner
            }

            if hasVisibleAssignedIdea, !hasCompletedPromote {
                return .promote
            }

            return nil
        }

        static func shouldShowTaskSwipeActionsTip(
            isTasksTabSelected: Bool,
            isShowingActiveFilter: Bool,
            hasVisibleActiveTasks: Bool,
            isReordering: Bool,
            hasInlineBanner: Bool,
            hasPresentedSheet: Bool,
            hasPendingDeleteToast: Bool,
            isTaskCompletionAnimating: Bool,
            hasCompletedSwipeActionsTip: Bool
        ) -> Bool {
            isTasksTabSelected &&
                isShowingActiveFilter &&
                hasVisibleActiveTasks &&
                !isReordering &&
                !hasInlineBanner &&
                !hasPresentedSheet &&
                !hasPendingDeleteToast &&
                !isTaskCompletionAnimating &&
                !hasCompletedSwipeActionsTip
        }
    }

    @available(iOS 17, *)
    struct ShoppingFirstAddTip: Tip {
        var title: Text {
            Text("Start your list")
        }

        var message: Text? {
            Text("Tap Add item to create your first shopping entry. Later, long-press it to quickly add a saved bundle.")
        }

        var image: Image? {
            Image(systemName: "cart.badge.plus")
        }

        var rules: [Rule] {
            [
                #Rule(AppTipEvents.shoppingFirstItemCreated) {
                    $0.donations.count < 1
                },
            ]
        }
    }

    @available(iOS 17, *)
    struct ShoppingRecentlyPurchasedTip: Tip {
        var title: Text {
            Text("Find bought items here")
        }

        var message: Text? {
            Text("Open Recently Purchased to quickly re-add items you already bought.")
        }

        var image: Image? {
            Image(systemName: "clock.badge.checkmark")
        }

        var rules: [Rule] {
            [
                #Rule(AppTipEvents.shoppingRecentPurchasesOpened) {
                    $0.donations.count < 1
                },
            ]
        }
    }

    @available(iOS 17, *)
    struct ShoppingBundlesLocationTip: Tip {
        var title: Text {
            Text("Bundles live here")
        }

        var message: Text? {
            Text("Open Bundles to save reusable shopping sets for faster planning.")
        }

        var image: Image? {
            Image(systemName: ShoppingBundle.featureIcon)
        }

        var rules: [Rule] {
            [
                #Rule(AppTipEvents.shoppingBundlesVisited) {
                    $0.donations.count < 1
                },
            ]
        }
    }

    @available(iOS 17, *)
    struct ShoppingBundleQuickAddTip: Tip {
        var title: Text {
            Text("Quick bundles")
        }

        var message: Text? {
            Text("Long-press Add item to quickly add one of your saved bundles.")
        }

        var image: Image? {
            Image(systemName: ShoppingBundle.featureIcon)
        }

        var rules: [Rule] {
            [
                #Rule(AppTipEvents.bundleQuickAddUsed) {
                    $0.donations.count < 1
                },
            ]
        }
    }

    @available(iOS 17, *)
    struct IdeasCreateCategoryTip: Tip {
        var title: Text {
            Text("Create a category")
        }

        var message: Text? {
            Text("Start here by creating a category for your ideas.")
        }

        var image: Image? {
            Image(systemName: "folder.badge.plus")
        }

        var rules: [Rule] {
            [
                #Rule(AppTipEvents.ideasCategoryCreated) {
                    $0.donations.count < 1
                },
            ]
        }
    }

    @available(iOS 17, *)
    struct IdeasAddIdeaTip: Tip {
        var title: Text {
            Text("Add your first idea")
        }

        var message: Text? {
            Text("Tap Add idea to capture something you want to plan later.")
        }

        var image: Image? {
            Image(systemName: "lightbulb")
        }

        var rules: [Rule] {
            [
                #Rule(AppTipEvents.ideasFirstIdeaAdded) {
                    $0.donations.count < 1
                },
            ]
        }
    }

    @available(iOS 17, *)
    struct IdeasAssignOwnerTip: Tip {
        var title: Text {
            Text("Assign an owner")
        }

        var message: Text? {
            Text("Use this area to assign the idea to a household member.")
        }

        var image: Image? {
            Image(systemName: "person.badge.plus")
        }

        var rules: [Rule] {
            [
                #Rule(AppTipEvents.ideasOwnerAssigned) {
                    $0.donations.count < 1
                },
            ]
        }
    }

    @available(iOS 17, *)
    struct IdeaPromotionTip: Tip {
        var title: Text {
            Text("Promote ready ideas")
        }

        var message: Text? {
            Text("Once an idea has an owner, tap the arrow to move it into Tasks.")
        }

        var image: Image? {
            Image(systemName: "arrow.up.circle.fill")
        }

        var rules: [Rule] {
            [
                #Rule(AppTipEvents.ideaPromoted) {
                    $0.donations.count < 1
                },
            ]
        }
    }

    @available(iOS 17, *)
    struct TaskSwipeActionsTip: Tip {
        var title: Text {
            Text("Swipe for shortcuts")
        }

        var message: Text? {
            Text("Swipe a task row for shortcuts like Poke, Move to Ideas, or Delete.")
        }

        var image: Image? {
            Image(systemName: "hand.draw.fill")
        }

        var rules: [Rule] {
            [
                #Rule(AppTipEvents.taskSwipeActionUsed) {
                    $0.donations.count < 1
                },
            ]
        }
    }

    extension View {
        @ViewBuilder
        func contextualPopoverTip(
            _ isEnabled: Bool,
            _ tip: some Tip,
            arrowEdge: Edge = .top,
            generation: Int = 0
        ) -> some View {
            if #available(iOS 17, *), isEnabled {
                id("app-tip-\(generation)")
                    .popoverTip(tip, arrowEdge: arrowEdge)
            } else {
                self
            }
        }
    }
#else
    enum AppTips {
        private static let defaults = UserDefaults.standard

        static var runtimeGenerationDefaultsKey: String {
            AppTipStorageKey.runtimeGeneration
        }

        static func configureIfNeeded(launchArguments _: [String] = ProcessInfo.processInfo.arguments) {}

        static func syncContextIfNeeded(
            sessionMode: SessionMode,
            userId: String?,
            householdId: UUID?,
            launchArguments _: [String] = ProcessInfo.processInfo.arguments
        ) {
            let newSignature = [
                sessionMode.rawValue,
                userId ?? "none",
                householdId?.uuidString ?? "none",
            ].joined(separator: "|")
            let previousSignature = defaults.string(forKey: AppTipStorageKey.contextSignature)
            let shouldForceBootstrap = defaults.bool(forKey: AppTipStorageKey.pendingHardResetBootstrap)
            guard shouldForceBootstrap || previousSignature != newSignature else { return }

            clearOnboardingProgress()
            bumpRuntimeGeneration()
            defaults.set(newSignature, forKey: AppTipStorageKey.contextSignature)
            defaults.removeObject(forKey: AppTipStorageKey.pendingHardResetBootstrap)
        }

        static func resetDatastoreForTestingIfNeeded(
            launchArguments _: [String] = ProcessInfo.processInfo.arguments
        ) {
            clearOnboardingProgress()
            defaults.removeObject(forKey: AppTipStorageKey.contextSignature)
            defaults.removeObject(forKey: AppTipStorageKey.pendingHardResetBootstrap)
            bumpRuntimeGeneration()
        }

        static func resetForHardReset(userDefaults: UserDefaults = .standard) {
            clearOnboardingProgress(userDefaults: userDefaults)
            userDefaults.removeObject(forKey: AppTipStorageKey.contextSignature)
            userDefaults.set(true, forKey: AppTipStorageKey.pendingHardResetBootstrap)
            bumpRuntimeGeneration(userDefaults: userDefaults)
        }

        static func resetForDevelopment() {
            clearOnboardingProgress()
            defaults.removeObject(forKey: AppTipStorageKey.contextSignature)
            defaults.removeObject(forKey: AppTipStorageKey.pendingHardResetBootstrap)
            bumpRuntimeGeneration()
        }

        static func donateShoppingFirstItemCreated() {
            defaults.set(true, forKey: AppTipProgressKey.shoppingFirstAddCompleted)
        }

        static func donateShoppingRecentPurchasesOpened() {
            defaults.set(true, forKey: AppTipProgressKey.shoppingRecentPurchasesCompleted)
        }

        static func donateShoppingBundlesVisited() {
            defaults.set(true, forKey: AppTipProgressKey.shoppingBundlesLocationCompleted)
        }

        static func donateBundleQuickAddUsed() {
            defaults.set(true, forKey: AppTipProgressKey.shoppingBundleQuickAddCompleted)
        }

        static func donateIdeasCategoryCreated() {
            defaults.set(true, forKey: AppTipProgressKey.ideasCreateCategoryCompleted)
        }

        static func donateIdeasFirstIdeaAdded() {
            defaults.set(true, forKey: AppTipProgressKey.ideasAddIdeaCompleted)
        }

        static func donateIdeasOwnerAssigned() {
            defaults.set(true, forKey: AppTipProgressKey.ideasAssignOwnerCompleted)
        }

        static func donateIdeaPromoted() {
            defaults.set(true, forKey: AppTipProgressKey.ideasPromoteCompleted)
        }

        static func donateTaskSwipeActionUsed() {
            defaults.set(true, forKey: AppTipProgressKey.tasksSwipeActionsCompleted)
        }

        static func clearOnboardingProgress(userDefaults: UserDefaults = .standard) {
            for key in AppTipProgressKey.all {
                userDefaults.removeObject(forKey: key)
            }
        }

        private static func bumpRuntimeGeneration(userDefaults: UserDefaults = .standard) {
            userDefaults.set(
                userDefaults.integer(forKey: AppTipStorageKey.runtimeGeneration) + 1,
                forKey: AppTipStorageKey.runtimeGeneration
            )
        }
    }

    enum AppTipVisibility {
        static func shoppingTip(
            hasActiveItems: Bool,
            hasRecentItems: Bool,
            hasBundles: Bool,
            hasQuickAddBundles: Bool,
            isRapidEntryActive: Bool,
            isKeyboardVisible: Bool,
            hasActiveToast: Bool,
            hasPresentedSheet: Bool,
            hasCompletedFirstAdd: Bool,
            hasCompletedRecentPurchases: Bool,
            hasCompletedBundlesLocation: Bool,
            hasCompletedBundleQuickAdd: Bool
        ) -> ShoppingOnboardingTip? {
            guard !isRapidEntryActive,
                  !isKeyboardVisible,
                  !hasActiveToast,
                  !hasPresentedSheet
            else {
                return nil
            }

            if hasQuickAddBundles, !hasCompletedBundleQuickAdd {
                return .bundleQuickAdd
            }

            if !hasActiveItems, !hasRecentItems, !hasCompletedFirstAdd {
                return .firstAdd
            }

            if hasRecentItems, !hasCompletedRecentPurchases {
                return .recentPurchases
            }

            if hasActiveItems || hasRecentItems, !hasBundles, !hasCompletedBundlesLocation {
                return .bundlesLocation
            }

            return nil
        }

        static func ideasTip(
            hasCategories: Bool,
            hasVisibleIdeas: Bool,
            hasVisibleUnassignedIdea: Bool,
            hasVisibleAssignedIdea: Bool,
            hasActiveBanner: Bool,
            hasPresentedSheet: Bool,
            hasPendingDeletionToast: Bool,
            hasCompletedCreateCategory: Bool,
            hasCompletedAddIdea: Bool,
            hasCompletedAssignOwner: Bool,
            hasCompletedPromote: Bool
        ) -> IdeasOnboardingTip? {
            guard !hasActiveBanner,
                  !hasPresentedSheet,
                  !hasPendingDeletionToast
            else {
                return nil
            }

            if !hasCategories, !hasCompletedCreateCategory {
                return .createCategory
            }

            if hasCategories, !hasVisibleIdeas, !hasCompletedAddIdea {
                return .addIdea
            }

            if hasVisibleUnassignedIdea, !hasCompletedAssignOwner {
                return .assignOwner
            }

            if hasVisibleAssignedIdea, !hasCompletedPromote {
                return .promote
            }

            return nil
        }

        static func shouldShowTaskSwipeActionsTip(
            isTasksTabSelected: Bool,
            isShowingActiveFilter: Bool,
            hasVisibleActiveTasks: Bool,
            isReordering: Bool,
            hasInlineBanner: Bool,
            hasPresentedSheet: Bool,
            hasPendingDeleteToast: Bool,
            isTaskCompletionAnimating: Bool,
            hasCompletedSwipeActionsTip: Bool
        ) -> Bool {
            isTasksTabSelected &&
                isShowingActiveFilter &&
                hasVisibleActiveTasks &&
                !isReordering &&
                !hasInlineBanner &&
                !hasPresentedSheet &&
                !hasPendingDeleteToast &&
                !isTaskCompletionAnimating &&
                !hasCompletedSwipeActionsTip
        }
    }
#endif

// swiftlint:enable file_length function_parameter_count
