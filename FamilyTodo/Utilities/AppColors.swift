import SwiftUI

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
    /// Warm, paper-like background used across the app to match the reference UI.
    static let light = AppColorPalette(
        canvas: Color(hex: "F6F1EC"),
        surface: Color(hex: "FFFFFF"),
        surfaceElevated: Color(hex: "FFF7EE"),
        ink: Color(hex: "1F1B17"),
        inkMuted: Color(hex: "8C8378"),
        borderLight: Color(hex: "E8DFD6"),
        accent: Color(hex: "F7B21A"),
        accentSoft: Color(hex: "FDE5A6"),
        tabBarBackground: Color(hex: "F3EDE6"),
        tabBarActivePill: Color(hex: "E9E1D8"),
        tabBarShadow: Color.black.opacity(0.1),
        cardShadow: Color.black.opacity(0.06)
    )

    /// Dark palette for night theme.
    static let night = AppColorPalette(
        canvas: Color(hex: "0E0C0A"),
        surface: Color(hex: "1B1713"),
        surfaceElevated: Color(hex: "241F1A"),
        ink: Color(hex: "F3EDE5"),
        inkMuted: Color(hex: "C9BFB2"),
        borderLight: Color(hex: "2F2822"),
        accent: Color(hex: "F7B21A"),
        accentSoft: Color(hex: "F2D089"),
        tabBarBackground: Color(hex: "1B1713"),
        tabBarActivePill: Color(hex: "2A241E"),
        tabBarShadow: Color.black.opacity(0.45),
        cardShadow: Color.black.opacity(0.4)
    )

    static let retro = AppColorPalette(
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

    static let chalk = AppColorPalette(
        canvas: Color(hex: "243125"),
        surface: Color(hex: "2C3E2D"),
        surfaceElevated: Color(hex: "3A5240"),
        ink: Color(hex: "F5F5DC"),
        inkMuted: Color(hex: "C8C8A9"),
        borderLight: Color(hex: "4A6B4E"),
        accent: Color(hex: "FFEB99"),
        accentSoft: Color(hex: "FFF5CC"),
        tabBarBackground: Color(hex: "2A3A2A"),
        tabBarActivePill: Color(hex: "3A5240"),
        tabBarShadow: Color.black.opacity(0.4),
        cardShadow: Color.black.opacity(0.3)
    )

    static func palette(for preset: ThemePreset) -> AppColorPalette {
        switch preset {
        case .night:
            night
        case .retro:
            retro
        case .chalk:
            chalk
        case .journal, .pastel, .soft, .paper:
            light
        }
    }
}
