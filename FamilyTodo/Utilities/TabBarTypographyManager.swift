import SwiftUI
import UIKit

@MainActor
enum TabBarTypographyManager {
    private static let promotionHighlightTag = 91204

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
        selectedIndex: Int? = nil
    ) {
        guard let tabBarController else { return }

        let style = resolvedStyle(
            themeStore: themeStore,
            tabBarController: tabBarController,
            selectedIndex: selectedIndex
        )
        let desiredIndex = style.selectedIndex
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

    static func flashPromotionCue(
        themeStore: ThemeStore,
        tabBarController: UITabBarController?,
        tab: AppTab,
        colorHex: String?
    ) {
        guard let tabBarController,
              let tabIndex = AppTab.allCases.firstIndex(of: tab),
              let button = tabBarButton(in: tabBarController.tabBar, at: tabIndex)
        else {
            return
        }

        let highlightView: UIView
        if let existing = button.viewWithTag(promotionHighlightTag) {
            existing.layer.removeAllAnimations()
            existing.removeFromSuperview()
        }

        let highlightColor = resolvedHighlightColor(themeStore: themeStore, colorHex: colorHex)
        let frame = button.bounds.insetBy(dx: 10, dy: 6)
        let view = UIView(frame: frame)
        view.tag = promotionHighlightTag
        view.isUserInteractionEnabled = false
        view.backgroundColor = highlightColor.withAlphaComponent(0.16)
        view.layer.cornerRadius = min(frame.height / 2, 18)
        view.layer.borderWidth = 1
        view.layer.borderColor = highlightColor.withAlphaComponent(0.24).cgColor
        view.layer.shadowColor = highlightColor.withAlphaComponent(0.28).cgColor
        view.layer.shadowOpacity = 1
        view.layer.shadowOffset = .zero
        view.layer.shadowRadius = 10
        view.alpha = 0
        view.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        button.insertSubview(view, at: 0)
        highlightView = view

        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            highlightView.alpha = 1
            highlightView.transform = .identity
        } completion: { _ in
            UIView.animate(
                withDuration: 0.55,
                delay: 0.5,
                options: [.curveEaseIn, .beginFromCurrentState]
            ) {
                highlightView.alpha = 0
                highlightView.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            } completion: { _ in
                highlightView.removeFromSuperview()
            }
        }
    }

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
        appearance.configureWithDefaultBackground()
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

    private static func tabBarButton(in tabBar: UITabBar, at index: Int) -> UIControl? {
        let buttons = tabBar.subviews
            .compactMap { $0 as? UIControl }
            .filter { !$0.isHidden && $0.bounds.width > 0 }
            .sorted { $0.frame.minX < $1.frame.minX }

        guard buttons.indices.contains(index) else { return nil }
        return buttons[index]
    }

    private static func resolvedHighlightColor(
        themeStore: ThemeStore,
        colorHex: String?
    ) -> UIColor {
        guard let normalized = MemberColorToken.normalize(hex: colorHex) else {
            return UIColor(themeStore.resolvedTabTint)
        }

        let hexValue = String(normalized.dropFirst())
        let intValue = UInt64(hexValue, radix: 16) ?? 0
        let red = CGFloat((intValue >> 16) & 0xFF) / 255
        let green = CGFloat((intValue >> 8) & 0xFF) / 255
        let blue = CGFloat(intValue & 0xFF) / 255

        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}
