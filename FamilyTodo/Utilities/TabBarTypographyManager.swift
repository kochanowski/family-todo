import SwiftUI
import UIKit

@MainActor
enum TabBarTypographyManager {
    static func apply(themeStore: ThemeStore) {
        let normalAttributes = makeAttributes(
            font: themeStore.uiFont(for: .tabLabel),
            color: .secondaryLabel
        )
        let selectedColor = themeStore.resolvedTabTint.map(UIColor.init) ?? .label
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

        if #available(iOS 15.0, *) {
            var scrollEdge = tabBarAppearance.scrollEdgeAppearance ?? standard
            apply(
                normalAttributes: normalAttributes,
                selectedAttributes: selectedAttributes,
                to: &scrollEdge
            )
            tabBarAppearance.scrollEdgeAppearance = scrollEdge

            var compact = tabBarAppearance.compactAppearance ?? standard
            apply(
                normalAttributes: normalAttributes,
                selectedAttributes: selectedAttributes,
                to: &compact
            )
            tabBarAppearance.compactAppearance = compact
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
        let stacked = appearance.stackedLayoutAppearance
        stacked.normal.titleTextAttributes = normalAttributes
        stacked.selected.titleTextAttributes = selectedAttributes

        let inline = appearance.inlineLayoutAppearance
        inline.normal.titleTextAttributes = normalAttributes
        inline.selected.titleTextAttributes = selectedAttributes

        let compactInline = appearance.compactInlineLayoutAppearance
        compactInline.normal.titleTextAttributes = normalAttributes
        compactInline.selected.titleTextAttributes = selectedAttributes
    }
}
