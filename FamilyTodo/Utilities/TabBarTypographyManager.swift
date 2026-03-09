import SwiftUI
import UIKit

@MainActor
enum TabBarTypographyManager {
    static func apply(
        themeStore: ThemeStore,
        tabBarController: UITabBarController? = nil,
        selectedIndex: Int? = nil
    ) {
        let normalColor = UIColor.secondaryLabel
        let normalAttributes = makeAttributes(
            font: themeStore.uiFont(for: .tabLabel),
            color: normalColor
        )
        let selectedColor = UIColor(themeStore.resolvedTabTint)
        let selectedAttributes = makeAttributes(
            font: themeStore.uiFont(for: .tabLabel),
            color: selectedColor
        )

        let tabBarAppearance = UITabBar.appearance()

        var standard = tabBarAppearance.standardAppearance
        apply(
            normalAttributes: normalAttributes,
            selectedAttributes: selectedAttributes,
            to: &standard
        )
        tabBarAppearance.standardAppearance = standard
        tabBarAppearance.tintColor = selectedColor
        tabBarAppearance.unselectedItemTintColor = normalColor

        var resolvedScrollEdgeAppearance: UITabBarAppearance?
        if #available(iOS 15.0, *) {
            var scrollEdge = tabBarAppearance.scrollEdgeAppearance ?? standard
            apply(
                normalAttributes: normalAttributes,
                selectedAttributes: selectedAttributes,
                to: &scrollEdge
            )
            tabBarAppearance.scrollEdgeAppearance = scrollEdge
            resolvedScrollEdgeAppearance = scrollEdge
        }

        if let tabBarController {
            updateLiveTabBar(
                tabBarController: tabBarController,
                standardAppearance: standard,
                scrollEdgeAppearance: resolvedScrollEdgeAppearance,
                selectedColor: selectedColor,
                normalColor: normalColor,
                selectedIndex: selectedIndex
            )
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

    private static func apply(
        normalAttributes: [NSAttributedString.Key: Any],
        selectedAttributes: [NSAttributedString.Key: Any],
        to appearance: inout UITabBarAppearance
    ) {
        let normalColor = UIColor.secondaryLabel
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
