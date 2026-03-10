import SwiftUI
import UIKit

struct AppColorPalette {
    let canvas: Color
    let surface: Color
    let surfaceElevated: Color
    let ink: Color
    let inkMuted: Color
    let borderLight: Color
    let accent: Color
    let accentSoft: Color
    let tabBarBackground: Color
    let tabBarActivePill: Color
    let tabBarShadow: Color
    let cardShadow: Color
}

enum AppColors {
    static let system = AppColorPalette(
        canvas: dynamicColor(lightHex: "F6F1EC", darkHex: "0E0C0A"),
        surface: dynamicColor(lightHex: "FFFFFF", darkHex: "1B1713"),
        surfaceElevated: dynamicColor(lightHex: "FFF7EE", darkHex: "241F1A"),
        ink: dynamicColor(lightHex: "1F1B17", darkHex: "F3EDE5"),
        inkMuted: dynamicColor(lightHex: "8C8378", darkHex: "C9BFB2"),
        borderLight: dynamicColor(lightHex: "E8DFD6", darkHex: "2F2822"),
        accent: dynamicColor(lightHex: "F7B21A", darkHex: "F2D089"),
        accentSoft: dynamicColor(lightHex: "FDE5A6", darkHex: "6E5628"),
        tabBarBackground: dynamicColor(lightHex: "F3EDE6", darkHex: "1B1713"),
        tabBarActivePill: dynamicColor(lightHex: "E9E1D8", darkHex: "2A241E"),
        tabBarShadow: Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(0.45)
                : UIColor.black.withAlphaComponent(0.1)
        }),
        cardShadow: Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(0.4)
                : UIColor.black.withAlphaComponent(0.06)
        })
    )

    static let retroDark = AppColorPalette(
        canvas: Color(hex: "0A0A1A"),
        surface: Color(hex: "1A1A2E"),
        surfaceElevated: Color(hex: "232345"),
        ink: Color(hex: "00FF41"),
        inkMuted: Color(hex: "00AA2A"),
        borderLight: Color(hex: "333366"),
        accent: Color(hex: "FFDD57"),
        accentSoft: Color(hex: "FFE88A"),
        tabBarBackground: Color(hex: "0F0F23"),
        tabBarActivePill: Color(hex: "1A1A3E"),
        tabBarShadow: Color.black.opacity(0.6),
        cardShadow: Color.black.opacity(0.5)
    )

    static let retroLight = AppColorPalette(
        canvas: Color(hex: "E7DFC9"),
        surface: Color(hex: "F4EBD7"),
        surfaceElevated: Color(hex: "FFF6E5"),
        ink: Color(hex: "141414"),
        inkMuted: Color(hex: "4B4338"),
        borderLight: Color(hex: "2E2A24"),
        accent: Color(hex: "57E35F"),
        accentSoft: Color(hex: "CDEFA8"),
        tabBarBackground: Color(hex: "DDD4BE"),
        tabBarActivePill: Color(hex: "F0E6D1"),
        tabBarShadow: Color.black.opacity(0.12),
        cardShadow: Color.black.opacity(0.07)
    )

    static let paper = AppColorPalette(
        canvas: Color(hex: "F7F0E3"),
        surface: Color(hex: "FFF9EE"),
        surfaceElevated: Color(hex: "F3E8D5"),
        ink: Color(hex: "2F241C"),
        inkMuted: Color(hex: "6D5B4C"),
        borderLight: Color(hex: "E2D2BD"),
        accent: Color(hex: "8B4513"),
        accentSoft: Color(hex: "DDB892"),
        tabBarBackground: Color(hex: "F1E6D4"),
        tabBarActivePill: Color(hex: "E8D8BF"),
        tabBarShadow: Color.black.opacity(0.12),
        cardShadow: Color.black.opacity(0.08)
    )

    static func palette(for preset: ThemePreset) -> AppColorPalette {
        switch preset {
        case .retroDark:
            retroDark
        case .retroLight:
            retroLight
        case .paper:
            paper
        case .system:
            system
        }
    }

    private static func dynamicColor(lightHex: String, darkHex: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
        })
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }
}
