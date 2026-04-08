import SwiftUI
import UIKit

@MainActor
enum TabBarTypographyManager {
    struct ResolvedTabBarStyle: Equatable {
        let normalColor: UIColor
        let selectedColor: UIColor
        let font: UIFont
        let interfaceStyle: UIUserInterfaceStyle

        static func == (lhs: ResolvedTabBarStyle, rhs: ResolvedTabBarStyle) -> Bool {
            colorsMatch(lhs.normalColor, rhs.normalColor) &&
                colorsMatch(lhs.selectedColor, rhs.selectedColor) &&
                fontsMatch(lhs.font, rhs.font) &&
                lhs.interfaceStyle == rhs.interfaceStyle
        }
    }

    static func resolvedStyle(
        themeStore: ThemeStore,
        traitCollection: UITraitCollection? = nil,
        colorScheme: ColorScheme? = nil
    ) -> ResolvedTabBarStyle {
        let interfaceStyle = resolvedInterfaceStyle(
            themeStore: themeStore,
            traitCollection: traitCollection,
            colorScheme: colorScheme
        )

        return ResolvedTabBarStyle(
            normalColor: inactiveItemColor(
                themeStore: themeStore,
                traitCollection: UITraitCollection(userInterfaceStyle: interfaceStyle)
            ),
            selectedColor: UIColor(themeStore.resolvedTabTint),
            font: themeStore.uiFont(for: .tabLabel),
            interfaceStyle: interfaceStyle
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

    private static func resolvedInterfaceStyle(
        themeStore: ThemeStore,
        traitCollection: UITraitCollection?,
        colorScheme: ColorScheme?
    ) -> UIUserInterfaceStyle {
        if let colorScheme {
            return colorScheme == .dark ? .dark : .light
        }

        if let traitCollection {
            return traitCollection.userInterfaceStyle
        }

        if let themeColorScheme = themeStore.colorScheme {
            return themeColorScheme == .dark ? .dark : .light
        }

        return UIScreen.main.traitCollection.userInterfaceStyle
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
}
