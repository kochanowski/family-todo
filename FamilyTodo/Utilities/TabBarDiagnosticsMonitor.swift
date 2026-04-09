import UIKit

@MainActor
final class TabBarDiagnosticsMonitor {
    static let shared = TabBarDiagnosticsMonitor()

    private weak var tabBarController: UITabBarController?
    private var selectedTab: AppTab = .shopping

    #if DEBUG
        private weak var observedPresentedViewController: UIViewController?
        private weak var dismissalTrackingViewController: UIViewController?
        private var displayLink: CADisplayLink?
        private var remainingPostDismissFrames = 0
        private var postDismissFrameIndex = 0
    #endif

    private init() {}

    func attach(to controller: UITabBarController, selectedTab: AppTab) {
        self.selectedTab = selectedTab

        let isNewController = tabBarController !== controller
        tabBarController = controller

        if isNewController {
            recordSnapshot(event: "tabbar.attach", on: controller)
            #if DEBUG
                startDisplayLinkIfNeeded()
            #endif
        }
    }

    func updateSelectedTab(_ selectedTab: AppTab) {
        self.selectedTab = selectedTab
    }

    func recordSnapshot(
        event: String,
        on controller: UITabBarController? = nil,
        extra: [String: String] = [:]
    ) {
        #if DEBUG
            guard let controller = controller ?? tabBarController else { return }
            CloudKitDiagnosticsState.shared.recordTabBarEvent(
                operation: event,
                payload: snapshotPayload(for: controller, extra: extra)
            )
        #else
            _ = event
            _ = controller
            _ = extra
        #endif
    }

    #if DEBUG
        @objc private func handleDisplayLinkTick() {
            guard let controller = tabBarController else {
                displayLink?.invalidate()
                displayLink = nil
                return
            }

            inspectPresentedViewController(for: controller)
            emitPostDismissSnapshots(for: controller)
        }

        private func startDisplayLinkIfNeeded() {
            guard displayLink == nil else { return }
            let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLinkTick))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }

        private func inspectPresentedViewController(for controller: UITabBarController) {
            let presentedViewController = topPresentedViewController(from: controller)

            if presentedViewController !== observedPresentedViewController {
                if let presentedViewController {
                    observedPresentedViewController = presentedViewController
                    dismissalTrackingViewController = nil
                    recordSnapshot(
                        event: "tabbar.sheet.presented",
                        on: controller,
                        extra: ["viewController": className(of: presentedViewController)]
                    )
                } else if observedPresentedViewController != nil {
                    observedPresentedViewController = nil
                    dismissalTrackingViewController = nil
                    recordSnapshot(event: "tabbar.sheet.cleared", on: controller)
                }
            }

            guard let presentedViewController else { return }

            if presentedViewController.isBeingDismissed, dismissalTrackingViewController !== presentedViewController {
                dismissalTrackingViewController = presentedViewController
                let dismissedClassName = className(of: presentedViewController)
                recordSnapshot(
                    event: "tabbar.sheet.dismiss.start",
                    on: controller,
                    extra: ["viewController": dismissedClassName]
                )

                presentedViewController.transitionCoordinator?.animate(alongsideTransition: nil) { [weak self, weak controller] _ in
                    guard let self, let controller else { return }
                    self.recordSnapshot(
                        event: "tabbar.sheet.dismiss.complete",
                        on: controller,
                        extra: ["viewController": dismissedClassName]
                    )
                    self.remainingPostDismissFrames = 12
                    self.postDismissFrameIndex = 0
                }
            }
        }

        private func emitPostDismissSnapshots(for controller: UITabBarController) {
            guard remainingPostDismissFrames > 0 else { return }

            postDismissFrameIndex += 1
            remainingPostDismissFrames -= 1
            recordSnapshot(
                event: "tabbar.sheet.dismiss.postFrame",
                on: controller,
                extra: ["frame": "\(postDismissFrameIndex)"]
            )
        }
    #endif

    private func snapshotPayload(
        for controller: UITabBarController,
        extra: [String: String]
    ) -> String {
        let tabBar = controller.tabBar
        let subviewLines = tabBar.subviews.enumerated().map { index, view in
            let role = view is UIControl ? "control" : "decoration"
            return """
            [\(index)] \(className(of: view)) role=\(role) frame=\(describe(view.frame)) alpha=\(describe(view.alpha)) hidden=\(view.isHidden) background=\(describe(view.backgroundColor))
            """
        }

        let topPresented = topPresentedViewController(from: controller).map { className(of: $0) } ?? "nil"
        let extraLines = extra
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }

        return (
            [
                "selectedTab=\(selectedTab.rawValue)",
                "selectedIndex=\(controller.selectedIndex)",
                "presented=\(topPresented)",
                "tabBar.isTranslucent=\(tabBar.isTranslucent)",
                "tabBar.backgroundColor=\(describe(tabBar.backgroundColor))",
                "tabBar.barTintColor=\(describe(tabBar.barTintColor))",
                "tabBar.frame=\(describe(tabBar.frame))",
            ] + extraLines + ["subviews:"] + subviewLines
        )
            .joined(separator: "\n")
    }

    private func topPresentedViewController(from controller: UITabBarController) -> UIViewController? {
        var current = controller.presentedViewController ?? controller.selectedViewController?.presentedViewController

        while let next = current?.presentedViewController {
            current = next
        }

        return current
    }

    private func className(of object: AnyObject) -> String {
        String(describing: type(of: object))
    }

    private func describe(_ rect: CGRect) -> String {
        let x = String(format: "%.1f", rect.origin.x)
        let y = String(format: "%.1f", rect.origin.y)
        let width = String(format: "%.1f", rect.size.width)
        let height = String(format: "%.1f", rect.size.height)
        return "{{\(x), \(y)}, {\(width), \(height)}}"
    }

    private func describe(_ color: UIColor?) -> String {
        guard let color else { return "nil" }

        var red = CGFloat.zero
        var green = CGFloat.zero
        var blue = CGFloat.zero
        var alpha = CGFloat.zero

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return String(describing: color)
        }

        let redString = String(format: "%.3f", red)
        let greenString = String(format: "%.3f", green)
        let blueString = String(format: "%.3f", blue)
        let alphaString = String(format: "%.3f", alpha)
        return "rgba(\(redString),\(greenString),\(blueString),\(alphaString))"
    }

    private func describe(_ value: CGFloat) -> String {
        String(format: "%.3f", value)
    }
}
