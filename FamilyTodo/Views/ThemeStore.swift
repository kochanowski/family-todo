import SwiftUI
import UIKit

enum ThemeFontRole {
    case display
    case title
    case body
    case chip
}

enum ThemeFontToken {
    case screenHeader
    case filterLabel
    case listRowTitle
    case profileName
    case celebrationMessage
    case chip

    var size: CGFloat {
        switch self {
        case .screenHeader:
            28
        case .filterLabel:
            14
        case .listRowTitle:
            15
        case .profileName:
            17
        case .celebrationMessage:
            15
        case .chip:
            11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .screenHeader:
            .bold
        case .filterLabel:
            .semibold
        case .profileName, .celebrationMessage:
            .semibold
        case .chip:
            .medium
        case .listRowTitle:
            .regular
        }
    }

    var role: ThemeFontRole {
        switch self {
        case .screenHeader:
            .display
        case .profileName:
            .title
        case .chip:
            .chip
        case .filterLabel, .listRowTitle, .celebrationMessage:
            .body
        }
    }
}

enum ThemePreset: String, CaseIterable, Identifiable {
    case system
    case retro
    case paper

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .system:
            "Default"
        case .retro:
            "Retro"
        case .paper:
            "Paper"
        }
    }

    var iconName: String {
        switch self {
        case .system:
            "iphone"
        case .retro:
            "gamecontroller.fill"
        case .paper:
            "newspaper.fill"
        }
    }

    /// Custom bundled font names.
    /// Use `uiFontName` for built-in fonts like Georgia.
    var fontName: String? {
        switch self {
        case .retro:
            "PressStart2P-Regular"
        case .paper, .system:
            nil
        }
    }

    /// UIFont names (system or bundled).
    var uiFontName: String? {
        switch self {
        case .paper:
            "Georgia"
        case .retro:
            "PressStart2P-Regular"
        case .system:
            nil
        }
    }

    var palette: ThemePalette {
        switch self {
        case .system:
            ThemePalette(cardThemes: [
                .shoppingList: CardTheme(
                    gradientColors: [Color(hex: "FDF7F1"), Color(hex: "F5E9DE")],
                    accentColor: Color(hex: "D9A259"),
                    primaryTextColor: Color(hex: "5C4631"),
                    secondaryTextColor: Color(hex: "8C6B4A")
                ),
                .todo: CardTheme(
                    gradientColors: [Color(hex: "F6F5EF"), Color(hex: "E8E3DA")],
                    accentColor: Color(hex: "8FB18A"),
                    primaryTextColor: Color(hex: "39533C"),
                    secondaryTextColor: Color(hex: "5B7A60")
                ),
                .backlog: CardTheme(
                    gradientColors: [Color(hex: "FFF5E1"), Color(hex: "F9E2B9")],
                    accentColor: Color(hex: "E0A84F"),
                    primaryTextColor: Color(hex: "6B4B1C"),
                    secondaryTextColor: Color(hex: "9B6C2B")
                ),
                .recurring: CardTheme(
                    gradientColors: [Color(hex: "FDF0E6"), Color(hex: "F5D7C3")],
                    accentColor: Color(hex: "D18A6E"),
                    primaryTextColor: Color(hex: "6D3F2D"),
                    secondaryTextColor: Color(hex: "9C634A")
                ),
                .household: CardTheme(
                    gradientColors: [Color(hex: "F2F4F8"), Color(hex: "E1E7F1")],
                    accentColor: Color(hex: "8FA3C9"),
                    primaryTextColor: Color(hex: "364560"),
                    secondaryTextColor: Color(hex: "5A6B89")
                ),
                .areas: CardTheme(
                    gradientColors: [Color(hex: "F1F6F4"), Color(hex: "DCEBE5")],
                    accentColor: Color(hex: "7BAA9B"),
                    primaryTextColor: Color(hex: "2F5B52"),
                    secondaryTextColor: Color(hex: "4C7B70")
                ),
                .settings: CardTheme(
                    gradientColors: [Color(hex: "F6F2ED"), Color(hex: "E9E1D9")],
                    accentColor: Color(hex: "9A8F86"),
                    primaryTextColor: Color(hex: "4E4741"),
                    secondaryTextColor: Color(hex: "6E655E")
                ),
            ])
        case .retro:
            ThemePalette(cardThemes: [
                .shoppingList: CardTheme(
                    gradientColors: [Color(hex: "1A1A2E"), Color(hex: "16213E")],
                    accentColor: Color(hex: "E94560"),
                    primaryTextColor: Color(hex: "00FF41"),
                    secondaryTextColor: Color(hex: "00CC33")
                ),
                .todo: CardTheme(
                    gradientColors: [Color(hex: "0F0F23"), Color(hex: "1A1A3E")],
                    accentColor: Color(hex: "FFDD57"),
                    primaryTextColor: Color(hex: "00FF41"),
                    secondaryTextColor: Color(hex: "FFD700")
                ),
                .backlog: CardTheme(
                    gradientColors: [Color(hex: "1A0A2E"), Color(hex: "2D1B69")],
                    accentColor: Color(hex: "FF6B9D"),
                    primaryTextColor: Color(hex: "C084FC"),
                    secondaryTextColor: Color(hex: "A855F7")
                ),
                .recurring: CardTheme(
                    gradientColors: [Color(hex: "0A1628"), Color(hex: "172554")],
                    accentColor: Color(hex: "00D4FF"),
                    primaryTextColor: Color(hex: "7DD3FC"),
                    secondaryTextColor: Color(hex: "38BDF8")
                ),
                .household: CardTheme(
                    gradientColors: [Color(hex: "1E1E1E"), Color(hex: "2D2D2D")],
                    accentColor: Color(hex: "FF4500"),
                    primaryTextColor: Color(hex: "FFFFFF"),
                    secondaryTextColor: Color(hex: "BBBBBB")
                ),
                .areas: CardTheme(
                    gradientColors: [Color(hex: "0D1117"), Color(hex: "161B22")],
                    accentColor: Color(hex: "58A6FF"),
                    primaryTextColor: Color(hex: "C9D1D9"),
                    secondaryTextColor: Color(hex: "8B949E")
                ),
                .settings: CardTheme(
                    gradientColors: [Color(hex: "21262D"), Color(hex: "30363D")],
                    accentColor: Color(hex: "F78166"),
                    primaryTextColor: Color(hex: "E6EDF3"),
                    secondaryTextColor: Color(hex: "8B949E")
                ),
            ])
        case .paper:
            ThemePalette(cardThemes: [
                .shoppingList: CardTheme(
                    gradientColors: [Color(hex: "F5E6D3"), Color(hex: "E8D5B7")],
                    accentColor: Color(hex: "8B4513"),
                    primaryTextColor: Color(hex: "3E2723"),
                    secondaryTextColor: Color(hex: "5D4037")
                ),
                .todo: CardTheme(
                    gradientColors: [Color(hex: "FFF8E7"), Color(hex: "F0E6CE")],
                    accentColor: Color(hex: "6D4C41"),
                    primaryTextColor: Color(hex: "3E2723"),
                    secondaryTextColor: Color(hex: "795548")
                ),
                .backlog: CardTheme(
                    gradientColors: [Color(hex: "F2E8D5"), Color(hex: "E5D7C0")],
                    accentColor: Color(hex: "A1887F"),
                    primaryTextColor: Color(hex: "4E342E"),
                    secondaryTextColor: Color(hex: "6D4C41")
                ),
                .recurring: CardTheme(
                    gradientColors: [Color(hex: "EDE0C8"), Color(hex: "D7C9A8")],
                    accentColor: Color(hex: "8D6E63"),
                    primaryTextColor: Color(hex: "3E2723"),
                    secondaryTextColor: Color(hex: "5D4037")
                ),
                .household: CardTheme(
                    gradientColors: [Color(hex: "FAF3E6"), Color(hex: "F0E4CA")],
                    accentColor: Color(hex: "7B5B3A"),
                    primaryTextColor: Color(hex: "2C1810"),
                    secondaryTextColor: Color(hex: "5D4037")
                ),
                .areas: CardTheme(
                    gradientColors: [Color(hex: "F5EFE0"), Color(hex: "E8DCC8")],
                    accentColor: Color(hex: "9E8B76"),
                    primaryTextColor: Color(hex: "3E2723"),
                    secondaryTextColor: Color(hex: "6D4C41")
                ),
                .settings: CardTheme(
                    gradientColors: [Color(hex: "EDE4D3"), Color(hex: "DDD1BA")],
                    accentColor: Color(hex: "8D6E63"),
                    primaryTextColor: Color(hex: "3E2723"),
                    secondaryTextColor: Color(hex: "5D4037")
                ),
            ])
        }
    }
}

struct CardTheme {
    let gradientColors: [Color]
    let accentColor: Color
    let primaryTextColor: Color
    let secondaryTextColor: Color
}

struct ThemePalette {
    let cardThemes: [CardKind: CardTheme]

    func theme(for kind: CardKind) -> CardTheme {
        cardThemes[kind]
            ?? CardTheme(
                gradientColors: [Color(.systemGray5), Color(.systemGray4)],
                accentColor: Color(.systemGray),
                primaryTextColor: Color.primary,
                secondaryTextColor: Color.secondary
            )
    }
}

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    var iconName: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        case .system: "iphone"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

enum TabTintColor: String, CaseIterable, Identifiable {
    case system
    case green
    case red
    case blue

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .system:
            "Default"
        case .green:
            "Green"
        case .red:
            "Red"
        case .blue:
            "Blue"
        }
    }

    var color: Color? {
        switch self {
        case .system:
            nil
        case .green:
            .green
        case .red:
            .red
        case .blue:
            .blue
        }
    }

    var iconName: String {
        switch self {
        case .system:
            "circle.lefthalf.filled"
        case .green, .red, .blue:
            "circle.fill"
        }
    }
}

// MARK: - Unified Theme (Settings UI)

enum UnifiedTheme: String, CaseIterable, Identifiable {
    case light, dark, auto, retro, paper

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .auto: "Auto"
        case .retro: "Retro"
        case .paper: "Paper"
        }
    }

    var iconName: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        case .auto: "circle.lefthalf.filled"
        case .retro: "gamecontroller.fill"
        case .paper: "newspaper.fill"
        }
    }
}

// MARK: - Theme Store

@MainActor
final class ThemeStore: ObservableObject {
    @AppStorage("themePreset") private var presetRawValue = ThemePreset.system.rawValue
    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @AppStorage("celebrationsEnabled") var celebrationsEnabled = true
    @AppStorage("tabTintColor") private var tabTintColorRawValue = TabTintColor.system.rawValue

    init() {
        _ = verifyBundledFonts()
    }

    var preset: ThemePreset {
        get { ThemePreset(rawValue: presetRawValue) ?? .system }
        set {
            presetRawValue = newValue.rawValue
            objectWillChange.send()
        }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRawValue) ?? .system }
        set {
            appearanceModeRawValue = newValue.rawValue
            objectWillChange.send()
        }
    }

    var tabTintColor: TabTintColor {
        get { TabTintColor(rawValue: tabTintColorRawValue) ?? .system }
        set {
            tabTintColorRawValue = newValue.rawValue
            objectWillChange.send()
        }
    }

    var unifiedTheme: UnifiedTheme {
        get {
            switch preset {
            case .retro: .retro
            case .paper: .paper
            case .system:
                switch appearanceMode {
                case .light: .light
                case .dark: .dark
                case .system: .auto
                }
            }
        }
        set {
            switch newValue {
            case .light:
                preset = .system
                appearanceMode = .light
            case .dark:
                preset = .system
                appearanceMode = .dark
            case .auto:
                preset = .system
                appearanceMode = .system
            case .retro:
                preset = .retro
            case .paper:
                preset = .paper
            }
        }
    }

    var resolvedTabTint: Color? {
        tabTintColor.color
    }

    /// Retro always stays dark. Paper stays light.
    var colorScheme: ColorScheme? {
        switch preset {
        case .retro:
            .dark
        case .paper:
            .light
        case .system:
            appearanceMode.colorScheme
        }
    }

    // MARK: - Resolved Colors for Views

    var canvasColor: Color {
        AppColors.palette(for: preset).canvas
    }

    var surfaceColor: Color {
        AppColors.palette(for: preset).surface
    }

    var inkColor: Color {
        AppColors.palette(for: preset).ink
    }

    var inkMutedColor: Color {
        AppColors.palette(for: preset).inkMuted
    }

    var accentColor: Color {
        AppColors.palette(for: preset).accent
    }

    var confettiAccentPalette: [Color]? {
        switch preset {
        case .system:
            nil
        case .retro:
            [
                Color(hex: "00FF41"),
                Color(hex: "FFDD57"),
                Color(hex: "FF6B9D"),
                Color(hex: "00D4FF"),
            ]
        case .paper:
            [
                Color(hex: "8B4513"),
                Color(hex: "A1887F"),
                Color(hex: "DDB892"),
                Color(hex: "6D4C41"),
            ]
        }
    }

    func font(for token: ThemeFontToken) -> Font {
        font(size: token.size, weight: token.weight, role: token.role)
    }

    /// Font resolved for current preset with graceful fallback.
    /// PressStart2P renders bigger than SF at same pt size, so we scale it down.
    func font(size: CGFloat, weight: Font.Weight = .regular, role: ThemeFontRole = .body) -> Font {
        switch preset {
        case .retro:
            let scaledSize = scaledRetroSize(size, role: role)
            return customFont("PressStart2P-Regular", size: scaledSize, fallbackWeight: weight)
        case .paper:
            switch role {
            case .display, .title:
                if UIFont(name: "SpecialElite-Regular", size: size) != nil {
                    return .custom("SpecialElite-Regular", size: size)
                }
                return customFont("Georgia", size: size, fallbackWeight: weight)
            case .body, .chip:
                return customFont("Georgia", size: size, fallbackWeight: weight)
            }
        case .system:
            return .system(size: size, weight: weight)
        }
    }

    @discardableResult
    func verifyBundledFonts() -> [String: Bool] {
        let registered: [String: Bool] = [
            "PressStart2P-Regular": UIFont(name: "PressStart2P-Regular", size: 14) != nil,
            "SpecialElite-Regular": UIFont(name: "SpecialElite-Regular", size: 14) != nil,
            "CaveatBrush-Regular": UIFont(name: "CaveatBrush-Regular", size: 14) != nil,
        ]

        let status = registered
            .map { "\($0.key)=\($0.value ? "ok" : "missing")" }
            .sorted()
            .joined(separator: ", ")

        print("🧩 Theme fonts audit: \(status)")
        print(
            "🧩 Theme font map: system=SF, retro=PressStart2P-Regular, paper=SpecialElite-Regular(headline)+Georgia(body), caveat=reserved"
        )
        return registered
    }

    private func customFont(_ postScriptName: String, size: CGFloat, fallbackWeight: Font.Weight) -> Font {
        if UIFont(name: postScriptName, size: size) != nil {
            return .custom(postScriptName, size: size)
        }
        return .system(size: size, weight: fallbackWeight)
    }

    private func scaledRetroSize(_ base: CGFloat, role: ThemeFontRole) -> CGFloat {
        let scale: CGFloat = switch role {
        case .display:
            0.62
        case .title:
            0.64
        case .body:
            0.66
        case .chip:
            0.68
        }
        return base * scale
    }
}
