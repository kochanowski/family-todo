import Foundation
import SwiftUI

#if canImport(TipKit)
    import TipKit

    enum AppTips {
        private static var hasConfigured = false

        static func configureIfNeeded(launchArguments: [String] = ProcessInfo.processInfo.arguments) {
            guard !hasConfigured else { return }
            hasConfigured = true

            guard #available(iOS 17, *) else { return }

            do {
                try Tips.configure([
                    .displayFrequency(.daily),
                ])
                configureTestingOverridesIfNeeded(launchArguments: launchArguments)
            } catch {
                print("TipKit configure failed: \(error.localizedDescription)")
            }
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
        }

        static func donateBundleQuickAddUsed() {
            guard #available(iOS 17, *) else { return }
            AppTipEvents.bundleQuickAddUsed.sendDonation()
        }

        static func donateIdeaPromoted() {
            guard #available(iOS 17, *) else { return }
            AppTipEvents.ideaPromoted.sendDonation()
        }

        static func donateTaskSwipeActionUsed() {
            guard #available(iOS 17, *) else { return }
            AppTipEvents.taskSwipeActionUsed.sendDonation()
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
            case "shopping":
                [ShoppingBundleQuickAddTip.self]
            case "ideas":
                [IdeaPromotionTip.self]
            case "tasks":
                [TaskSwipeActionsTip.self]
            default:
                nil
            }
        }
    }

    @available(iOS 17, *)
    enum AppTipEvents {
        static let bundleQuickAddUsed = Tips.Event(id: "shopping.bundleQuickAddUsed")
        static let ideaPromoted = Tips.Event(id: "backlog.ideaPromoted")
        static let taskSwipeActionUsed = Tips.Event(id: "tasks.swipeActionUsed")
    }

    enum AppTipVisibility {
        static func shouldShowShoppingBundleQuickAddTip(
            hasQuickAddBundles: Bool,
            isRapidEntryActive: Bool,
            isKeyboardVisible: Bool,
            hasActiveToast: Bool
        ) -> Bool {
            hasQuickAddBundles &&
                !isRapidEntryActive &&
                !isKeyboardVisible &&
                !hasActiveToast
        }

        static func shouldShowIdeaPromotionTip(
            hasPromotableVisibleItem: Bool,
            hasActiveBanner: Bool,
            hasPresentedSheet: Bool,
            hasPendingDeletionToast: Bool
        ) -> Bool {
            hasPromotableVisibleItem &&
                !hasActiveBanner &&
                !hasPresentedSheet &&
                !hasPendingDeletionToast
        }

        static func shouldShowTaskSwipeActionsTip(
            isTasksTabSelected: Bool,
            isShowingActiveFilter: Bool,
            hasVisibleActiveTasks: Bool,
            isReordering: Bool,
            hasInlineBanner: Bool,
            hasPresentedSheet: Bool,
            hasPendingDeleteToast: Bool,
            isTaskCompletionAnimating: Bool
        ) -> Bool {
            isTasksTabSelected &&
                isShowingActiveFilter &&
                hasVisibleActiveTasks &&
                !isReordering &&
                !hasInlineBanner &&
                !hasPresentedSheet &&
                !hasPendingDeleteToast &&
                !isTaskCompletionAnimating
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
            Image(systemName: ShoppingBundle.defaultIcon)
        }

        var options: [Option] {
            [
                .maxDisplayCount(1),
                .ignoresDisplayFrequency(true),
            ]
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

        var options: [Option] {
            [
                .maxDisplayCount(1),
                .ignoresDisplayFrequency(true),
            ]
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

        var options: [Option] {
            [
                .maxDisplayCount(1),
                .ignoresDisplayFrequency(true),
            ]
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
            arrowEdge: Edge = .top
        ) -> some View {
            if #available(iOS 17, *), isEnabled {
                popoverTip(tip, arrowEdge: arrowEdge)
            } else {
                self
            }
        }
    }
#else
    enum AppTips {
        static func configureIfNeeded(launchArguments _: [String] = ProcessInfo.processInfo.arguments) {}
        static func resetDatastoreForTestingIfNeeded(
            launchArguments _: [String] = ProcessInfo.processInfo.arguments
        ) {}
        static func donateBundleQuickAddUsed() {}
        static func donateIdeaPromoted() {}
        static func donateTaskSwipeActionUsed() {}
    }

    enum AppTipVisibility {
        static func shouldShowShoppingBundleQuickAddTip(
            hasQuickAddBundles: Bool,
            isRapidEntryActive: Bool,
            isKeyboardVisible: Bool,
            hasActiveToast: Bool
        ) -> Bool {
            hasQuickAddBundles &&
                !isRapidEntryActive &&
                !isKeyboardVisible &&
                !hasActiveToast
        }

        static func shouldShowIdeaPromotionTip(
            hasPromotableVisibleItem: Bool,
            hasActiveBanner: Bool,
            hasPresentedSheet: Bool,
            hasPendingDeletionToast: Bool
        ) -> Bool {
            hasPromotableVisibleItem &&
                !hasActiveBanner &&
                !hasPresentedSheet &&
                !hasPendingDeletionToast
        }

        static func shouldShowTaskSwipeActionsTip(
            isTasksTabSelected: Bool,
            isShowingActiveFilter: Bool,
            hasVisibleActiveTasks: Bool,
            isReordering: Bool,
            hasInlineBanner: Bool,
            hasPresentedSheet: Bool,
            hasPendingDeleteToast: Bool,
            isTaskCompletionAnimating: Bool
        ) -> Bool {
            isTasksTabSelected &&
                isShowingActiveFilter &&
                hasVisibleActiveTasks &&
                !isReordering &&
                !hasInlineBanner &&
                !hasPresentedSheet &&
                !hasPendingDeleteToast &&
                !isTaskCompletionAnimating
        }
    }
#endif
