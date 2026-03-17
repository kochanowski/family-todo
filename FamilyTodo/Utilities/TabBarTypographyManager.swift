import SwiftUI
import UIKit

@MainActor
enum TabBarTypographyManager {
    static func apply(
        themeStore: ThemeStore,
        tabBarController: UITabBarController? = nil,
        selectedIndex: Int? = nil
    ) {
        guard let tabBarController else { return }

        let traitCollection = tabBarController.traitCollection
        let normalColor = inactiveItemColor(
            themeStore: themeStore,
            traitCollection: traitCollection
        )
        let normalAttributes = makeAttributes(
            font: themeStore.uiFont(for: .tabLabel),
            color: normalColor
        )
        let selectedColor = UIColor(themeStore.resolvedTabTint)
        let selectedAttributes = makeAttributes(
            font: themeStore.uiFont(for: .tabLabel),
            color: selectedColor
        )
        let standardAppearance = makeAppearance(
            base: tabBarController.tabBar.standardAppearance,
            normalAttributes: normalAttributes,
            selectedAttributes: selectedAttributes
        )

        var resolvedScrollEdgeAppearance: UITabBarAppearance?
        if #available(iOS 15.0, *) {
            resolvedScrollEdgeAppearance = makeAppearance(
                base: tabBarController.tabBar.scrollEdgeAppearance ?? standardAppearance,
                normalAttributes: normalAttributes,
                selectedAttributes: selectedAttributes
            )
        }

        updateLiveTabBar(
            tabBarController: tabBarController,
            standardAppearance: standardAppearance,
            scrollEdgeAppearance: resolvedScrollEdgeAppearance,
            selectedColor: selectedColor,
            normalColor: normalColor,
            selectedIndex: selectedIndex
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

    private static func makeAttributes(
        font: UIFont,
        color: UIColor
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color,
        ]
    }

    private static func makeAppearance(
        base: UITabBarAppearance?,
        normalAttributes: [NSAttributedString.Key: Any],
        selectedAttributes: [NSAttributedString.Key: Any]
    ) -> UITabBarAppearance {
        let appearance = (base?.copy() as? UITabBarAppearance) ?? UITabBarAppearance()
        if base == nil {
            appearance.configureWithDefaultBackground()
        }

        let normalColor = (normalAttributes[.foregroundColor] as? UIColor) ?? UIColor.label
        let selectedColor = (selectedAttributes[.foregroundColor] as? UIColor) ?? UIColor.label

        let stacked = appearance.stackedLayoutAppearance
        stacked.normal.titleTextAttributes = normalAttributes
        stacked.selected.titleTextAttributes = selectedAttributes
        stacked.normal.iconColor = normalColor
        stacked.selected.iconColor = selectedColor

        let inline = appearance.inlineLayoutAppearance
        inline.normal.titleTextAttributes = normalAttributes
        inline.selected.titleTextAttributes = selectedAttributes
        inline.normal.iconColor = normalColor
        inline.selected.iconColor = selectedColor

        let compactInline = appearance.compactInlineLayoutAppearance
        compactInline.normal.titleTextAttributes = normalAttributes
        compactInline.selected.titleTextAttributes = selectedAttributes
        compactInline.normal.iconColor = normalColor
        compactInline.selected.iconColor = selectedColor

        return appearance
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
        tabBarController.selectedViewController = viewControllers[boundedIndex]
        tabBarController.tabBar.selectedItem = items[boundedIndex]
        tabBarController.tabBar.setNeedsLayout()
        tabBarController.tabBar.layoutIfNeeded()
    }
}
