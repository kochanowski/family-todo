import SwiftUI
import UIKit

@MainActor
enum TabBarTypographyManager {
    static func apply(themeStore: ThemeStore) {
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

        updateExistingTabBars(
            standardAppearance: standard,
            scrollEdgeAppearance: resolvedScrollEdgeAppearance,
            selectedColor: selectedColor,
            normalColor: normalColor
        )
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

    private static func updateExistingTabBars(
        standardAppearance: UITabBarAppearance,
        scrollEdgeAppearance: UITabBarAppearance?,
        selectedColor: UIColor,
        normalColor: UIColor
    ) {
        let tabBars = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .flatMap { window in
                allTabBars(in: window)
            }

        for tabBar in tabBars {
            tabBar.standardAppearance = standardAppearance
            if #available(iOS 15.0, *), let scrollEdgeAppearance {
                tabBar.scrollEdgeAppearance = scrollEdgeAppearance
            }
            tabBar.tintColor = selectedColor
            tabBar.unselectedItemTintColor = normalColor
            tabBar.setNeedsLayout()
            tabBar.layoutIfNeeded()
        }
    }

    private static func allTabBars(in view: UIView) -> [UITabBar] {
        let nestedTabBars = view.subviews.flatMap(allTabBars(in:))
        if let tabBar = view as? UITabBar {
            return [tabBar] + nestedTabBars
        }
        return nestedTabBars
    }
}
