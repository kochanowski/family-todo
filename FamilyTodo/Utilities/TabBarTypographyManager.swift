import SwiftUI
import UIKit

@MainActor
enum TabBarTypographyManager {
    private struct ResolvedTabBarStyle: Equatable {
        let normalColor: UIColor
        let selectedColor: UIColor
        let font: UIFont
        let selectedIndex: Int
        let interfaceStyle: UIUserInterfaceStyle

        static func == (lhs: ResolvedTabBarStyle, rhs: ResolvedTabBarStyle) -> Bool {
            colorsMatch(lhs.normalColor, rhs.normalColor) &&
                colorsMatch(lhs.selectedColor, rhs.selectedColor) &&
                fontsMatch(lhs.font, rhs.font) &&
                lhs.selectedIndex == rhs.selectedIndex &&
                lhs.interfaceStyle == rhs.interfaceStyle
        }
    }

    static func reconcile(
        themeStore: ThemeStore,
        tabBarController: UITabBarController? = nil,
        selectedIndex: Int? = nil,
        force: Bool = false
    ) {
        guard let tabBarController else { return }

        // Ensure our custom blur view exists before any appearance work.
        insertCustomBlurIfNeeded(in: tabBarController)

        let style = resolvedStyle(
            themeStore: themeStore,
            tabBarController: tabBarController,
            selectedIndex: selectedIndex
        )
        let desiredIndex = style.selectedIndex

        if !force {
            let currentStyle = currentStyle(from: tabBarController)
            let standardAppearanceMatches = appearanceMatches(
                tabBarController.tabBar.standardAppearance,
                style: style
            )
            let scrollEdgeAppearanceMatches: Bool = if #available(iOS 15.0, *) {
                appearanceMatches(tabBarController.tabBar.scrollEdgeAppearance, style: style)
            } else {
                true
            }
            let needsAppearanceRepair = currentStyle != style ||
                !standardAppearanceMatches ||
                !scrollEdgeAppearanceMatches

            guard needsAppearanceRepair || tabBarController.selectedIndex != desiredIndex else {
                return
            }
        }

        // Always create fresh appearance objects so UIKit sees a new assignment
        // and unconditionally refreshes its internal blur/vibrancy state.
        let standardAppearance = makeAppearance(style: style)

        var resolvedScrollEdgeAppearance: UITabBarAppearance?
        if #available(iOS 15.0, *) {
            resolvedScrollEdgeAppearance = makeAppearance(style: style)
        }

        updateLiveTabBar(
            tabBarController: tabBarController,
            standardAppearance: standardAppearance,
            scrollEdgeAppearance: resolvedScrollEdgeAppearance,
            selectedColor: style.selectedColor,
            normalColor: style.normalColor,
            selectedIndex: desiredIndex
        )
    }

    static func inactiveItemColor(
        themeStore: ThemeStore,
        traitCollection: UITraitCollection? = nil
    ) -> UIColor {
        switch themeStore.unifiedTheme {
        case .light:
            return .black
        case .dark:
            return .white
        case .auto:
            let interfaceStyle = traitCollection?.userInterfaceStyle ?? UIScreen.main.traitCollection.userInterfaceStyle
            return interfaceStyle == .dark ? .white : .black
        case .retroDark, .retroLight, .paper:
            return UIColor(themeStore.contentPrimaryColor)
        }
    }

    static func apply(
        themeStore: ThemeStore,
        tabBarController: UITabBarController? = nil,
        selectedIndex: Int? = nil
    ) {
        reconcile(
            themeStore: themeStore,
            tabBarController: tabBarController,
            selectedIndex: selectedIndex
        )
    }

    /// Inserts a custom UIVisualEffectView as the tab bar's blur background.
    /// This replaces UIKit's internal _UIBackdropLayer-based blur so we own the
    /// view and can force it to re-sample at any time without UIKit's caching issues.
    static func insertCustomBlurIfNeeded(in tabBarController: UITabBarController) {
        let tabBar = tabBarController.tabBar
        guard tabBar.viewWithTag(customBlurViewTag) == nil else { return }

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        blur.tag = customBlurViewTag
        blur.translatesAutoresizingMaskIntoConstraints = false
        tabBar.insertSubview(blur, at: 0)

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: tabBar.topAnchor),
            blur.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),
        ])
    }

    /// Forces the custom blur view to re-sample compositor content.
    /// Splits nil and restore into two separate async dispatches so CoreAnimation
    /// cannot batch them into one no-op commit — each dispatch is a distinct render pass.
    static func forceBlurRefresh(tabBarController: UITabBarController?) {
        guard let tabBar = tabBarController?.tabBar,
              let blur = tabBar.viewWithTag(customBlurViewTag) as? UIVisualEffectView
        else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blur.effect = nil
        CATransaction.commit()

        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            blur.effect = UIBlurEffect(style: .systemChromeMaterial)
            CATransaction.commit()
        }
    }

    private static let customBlurViewTag = 0x5442_4152 // 'TBAR'

    private static func resolvedStyle(
        themeStore: ThemeStore,
        tabBarController: UITabBarController,
        selectedIndex: Int?
    ) -> ResolvedTabBarStyle {
        let traitCollection = tabBarController.traitCollection
        let normalColor = inactiveItemColor(
            themeStore: themeStore,
            traitCollection: traitCollection
        )
        let selectedColor = UIColor(themeStore.resolvedTabTint)
        let font = themeStore.uiFont(for: .tabLabel)
        let resolvedIndex = selectedIndex ?? tabBarController.selectedIndex

        return ResolvedTabBarStyle(
            normalColor: normalColor,
            selectedColor: selectedColor,
            font: font,
            selectedIndex: resolvedIndex,
            interfaceStyle: traitCollection.userInterfaceStyle
        )
    }

    private static func currentStyle(from tabBarController: UITabBarController) -> ResolvedTabBarStyle? {
        let tabBar = tabBarController.tabBar
        guard let normalColor = tabBar.unselectedItemTintColor,
              let selectedColor = tabBar.tintColor,
              let font = font(
                  from: tabBar.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes
              )
        else {
            return nil
        }

        return ResolvedTabBarStyle(
            normalColor: normalColor,
            selectedColor: selectedColor,
            font: font,
            selectedIndex: tabBarController.selectedIndex,
            interfaceStyle: tabBarController.traitCollection.userInterfaceStyle
        )
    }

    private static func makeAttributes(font: UIFont, color: UIColor) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color,
        ]
    }

    private static func makeAppearance(style: ResolvedTabBarStyle) -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        // Transparent background — our custom UIVisualEffectView (inserted by
        // insertCustomBlurIfNeeded) provides the glass blur instead of UIKit's
        // internal _UIBackdropLayer, which cannot be reliably refreshed after
        // sheet presentation/dismissal.
        appearance.configureWithTransparentBackground()
        // Restore the standard top separator that configureWithDefaultBackground()
        // would normally provide.
        appearance.shadowColor = .separator
        let normalAttributes = makeAttributes(font: style.font, color: style.normalColor)
        let selectedAttributes = makeAttributes(font: style.font, color: style.selectedColor)

        let stacked = appearance.stackedLayoutAppearance
        stacked.normal.titleTextAttributes = normalAttributes
        stacked.selected.titleTextAttributes = selectedAttributes
        stacked.normal.iconColor = style.normalColor
        stacked.selected.iconColor = style.selectedColor

        let inline = appearance.inlineLayoutAppearance
        inline.normal.titleTextAttributes = normalAttributes
        inline.selected.titleTextAttributes = selectedAttributes
        inline.normal.iconColor = style.normalColor
        inline.selected.iconColor = style.selectedColor

        let compactInline = appearance.compactInlineLayoutAppearance
        compactInline.normal.titleTextAttributes = normalAttributes
        compactInline.selected.titleTextAttributes = selectedAttributes
        compactInline.normal.iconColor = style.normalColor
        compactInline.selected.iconColor = style.selectedColor

        return appearance
    }

    private static func appearanceMatches(
        _ appearance: UITabBarAppearance?,
        style: ResolvedTabBarStyle
    ) -> Bool {
        guard let appearance else { return false }

        return layoutAppearanceMatches(appearance.stackedLayoutAppearance, style: style) &&
            layoutAppearanceMatches(appearance.inlineLayoutAppearance, style: style) &&
            layoutAppearanceMatches(appearance.compactInlineLayoutAppearance, style: style)
    }

    private static func layoutAppearanceMatches(
        _ layoutAppearance: UITabBarItemAppearance,
        style: ResolvedTabBarStyle
    ) -> Bool {
        titleAttributesMatch(
            layoutAppearance.normal.titleTextAttributes,
            expectedColor: style.normalColor,
            expectedFont: style.font
        ) &&
            titleAttributesMatch(
                layoutAppearance.selected.titleTextAttributes,
                expectedColor: style.selectedColor,
                expectedFont: style.font
            ) &&
            colorsMatch(layoutAppearance.normal.iconColor, style.normalColor) &&
            colorsMatch(layoutAppearance.selected.iconColor, style.selectedColor)
    }

    private static func titleAttributesMatch(
        _ attributes: [NSAttributedString.Key: Any],
        expectedColor: UIColor,
        expectedFont: UIFont
    ) -> Bool {
        guard let color = attributes[.foregroundColor] as? UIColor,
              let font = font(from: attributes)
        else {
            return false
        }

        return colorsMatch(color, expectedColor) && fontsMatch(font, expectedFont)
    }

    private static func font(from attributes: [NSAttributedString.Key: Any]) -> UIFont? {
        attributes[.font] as? UIFont
    }

    private nonisolated static func fontsMatch(_ lhs: UIFont, _ rhs: UIFont) -> Bool {
        lhs.fontName == rhs.fontName && abs(lhs.pointSize - rhs.pointSize) < 0.01
    }

    private nonisolated static func colorsMatch(_ lhs: UIColor?, _ rhs: UIColor?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }

        var lhsRed = CGFloat.zero
        var lhsGreen = CGFloat.zero
        var lhsBlue = CGFloat.zero
        var lhsAlpha = CGFloat.zero
        var rhsRed = CGFloat.zero
        var rhsGreen = CGFloat.zero
        var rhsBlue = CGFloat.zero
        var rhsAlpha = CGFloat.zero

        guard lhs.getRed(&lhsRed, green: &lhsGreen, blue: &lhsBlue, alpha: &lhsAlpha),
              rhs.getRed(&rhsRed, green: &rhsGreen, blue: &rhsBlue, alpha: &rhsAlpha)
        else {
            return lhs.isEqual(rhs)
        }

        return abs(lhsRed - rhsRed) < 0.01 &&
            abs(lhsGreen - rhsGreen) < 0.01 &&
            abs(lhsBlue - rhsBlue) < 0.01 &&
            abs(lhsAlpha - rhsAlpha) < 0.01
    }

    private static func updateLiveTabBar(
        tabBarController: UITabBarController,
        standardAppearance: UITabBarAppearance,
        scrollEdgeAppearance: UITabBarAppearance?,
        selectedColor: UIColor,
        normalColor: UIColor,
        selectedIndex: Int?
    ) {
        let tabBar = tabBarController.tabBar

        tabBar.standardAppearance = standardAppearance
        if #available(iOS 15.0, *), let scrollEdgeAppearance {
            tabBar.scrollEdgeAppearance = scrollEdgeAppearance
        }
        tabBar.tintColor = selectedColor
        tabBar.unselectedItemTintColor = normalColor

        repairSelection(
            on: tabBarController,
            selectedIndex: selectedIndex ?? tabBarController.selectedIndex
        )

        DispatchQueue.main.async {
            repairSelection(
                on: tabBarController,
                selectedIndex: selectedIndex ?? tabBarController.selectedIndex
            )
        }
    }

    private static func repairSelection(
        on tabBarController: UITabBarController,
        selectedIndex: Int
    ) {
        guard let viewControllers = tabBarController.viewControllers,
              let items = tabBarController.tabBar.items,
              !viewControllers.isEmpty,
              !items.isEmpty
        else {
            return
        }

        let boundedIndex = min(max(selectedIndex, 0), min(viewControllers.count, items.count) - 1)
        tabBarController.selectedIndex = boundedIndex
        tabBarController.tabBar.setNeedsLayout()
        tabBarController.tabBar.layoutIfNeeded()
    }
}
