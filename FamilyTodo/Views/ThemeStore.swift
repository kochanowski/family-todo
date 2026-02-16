import SwiftUI
import UIKit

enum ThemePreset: String, CaseIterable, Identifiable {
    case journal
    case pastel
    case soft
    case night
    case retro
    case paper
    case chalk

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .journal:
            "Journal"
        case .pastel:
            "Pastel"
        case .soft:
            "Soft"
        case .night:
            "Night"
        case .retro:
            "Retro"
        case .paper:
            "Paper"
        case .chalk:
            "Chalk"
        }
    }

    var iconName: String {
        switch self {
        case .journal:
            "book.fill"
        case .pastel:
            "paintpalette.fill"
        case .soft:
            "cloud.fill"
        case .night:
            "moon.stars.fill"
        case .retro:
            "gamecontroller.fill"
        case .paper:
            "newspaper.fill"
        case .chalk:
            "pencil.and.outline"
        }
    }

    /// Preferred font for the selected preset.
    /// Custom fonts gracefully fall back to system if unavailable in bundle.
    var fontName: String? {
        switch self {
        case .retro:
            "PressStart2P-Regular"
        case .paper:
            "SpecialElite-Regular"
        case .chalk:
            "CaveatBrush-Regular"
        case .journal, .pastel, .soft, .night:
            nil
        }
    }

    var palette: ThemePalette {
        switch self {
        case .journal:
            // Warm journal palette to match the reference UI.
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
        case .pastel:
            // Soft Aurora palette - Redesign 2026-01-28
            ThemePalette(cardThemes: [
                .shoppingList: CardTheme(
                    gradientColors: [Color(hex: "F3E8FF"), Color(hex: "E9D5FF")],
                    accentColor: Color(hex: "A855F7"),
                    primaryTextColor: Color(hex: "6B21A8"),
                    secondaryTextColor: Color(hex: "7E22CE")
                ),
                .todo: CardTheme(
                    gradientColors: [Color(hex: "ECFDF5"), Color(hex: "D1FAE5")],
                    accentColor: Color(hex: "10B981"),
                    primaryTextColor: Color(hex: "065F46"),
                    secondaryTextColor: Color(hex: "047857")
                ),
                .backlog: CardTheme(
                    gradientColors: [Color(hex: "FEF3C7"), Color(hex: "FDE68A")],
                    accentColor: Color(hex: "F59E0B"),
                    primaryTextColor: Color(hex: "92400E"),
                    secondaryTextColor: Color(hex: "B45309")
                ),
                .recurring: CardTheme(
                    gradientColors: [Color(hex: "FFEDD5"), Color(hex: "FED7AA")],
                    accentColor: Color(hex: "F97316"),
                    primaryTextColor: Color(hex: "9A3412"),
                    secondaryTextColor: Color(hex: "C2410C")
                ),
                .household: CardTheme(
                    gradientColors: [Color(hex: "EFF6FF"), Color(hex: "BFDBFE")],
                    accentColor: Color(hex: "3B82F6"),
                    primaryTextColor: Color(hex: "1E40AF"),
                    secondaryTextColor: Color(hex: "1D4ED8")
                ),
                .areas: CardTheme(
                    gradientColors: [Color(hex: "F0FDFA"), Color(hex: "99F6E4")],
                    accentColor: Color(hex: "14B8A6"),
                    primaryTextColor: Color(hex: "115E59"),
                    secondaryTextColor: Color(hex: "0F766E")
                ),
                .settings: CardTheme(
                    gradientColors: [Color(hex: "F8FAFC"), Color(hex: "E2E8F0")],
                    accentColor: Color(hex: "64748B"),
                    primaryTextColor: Color(hex: "334155"),
                    secondaryTextColor: Color(hex: "475569")
                ),
            ])
        case .soft:
            ThemePalette(cardThemes: [
                .shoppingList: CardTheme(
                    gradientColors: [Color(hex: "F3E8FF"), Color(hex: "EDE9FE")],
                    accentColor: Color(hex: "A855F7"),
                    primaryTextColor: Color(hex: "6B21A8"),
                    secondaryTextColor: Color(hex: "7E22CE")
                ),
                .todo: CardTheme(
                    gradientColors: [Color(hex: "DCFCE7"), Color(hex: "D1FAE5")],
                    accentColor: Color(hex: "22C55E"),
                    primaryTextColor: Color(hex: "166534"),
                    secondaryTextColor: Color(hex: "16A34A")
                ),
                .backlog: CardTheme(
                    gradientColors: [Color(hex: "FEF3C7"), Color(hex: "FDE68A")],
                    accentColor: Color(hex: "F59E0B"),
                    primaryTextColor: Color(hex: "78350F"),
                    secondaryTextColor: Color(hex: "B45309")
                ),
                .recurring: CardTheme(
                    gradientColors: [Color(hex: "FFE4D2"), Color(hex: "FDBA8C")],
                    accentColor: Color(hex: "F97316"),
                    primaryTextColor: Color(hex: "9A3412"),
                    secondaryTextColor: Color(hex: "C2410C")
                ),
                .household: CardTheme(
                    gradientColors: [Color(hex: "E6FFFB"), Color(hex: "B2F5EA")],
                    accentColor: Color(hex: "14B8A6"),
                    primaryTextColor: Color(hex: "115E59"),
                    secondaryTextColor: Color(hex: "0F766E")
                ),
                .areas: CardTheme(
                    gradientColors: [Color(hex: "E0F2FE"), Color(hex: "BAE6FD")],
                    accentColor: Color(hex: "0EA5E9"),
                    primaryTextColor: Color(hex: "075985"),
                    secondaryTextColor: Color(hex: "0284C7")
                ),
                .settings: CardTheme(
                    gradientColors: [Color(hex: "FFE4E6"), Color(hex: "FECDD3")],
                    accentColor: Color(hex: "F43F5E"),
                    primaryTextColor: Color(hex: "9F1239"),
                    secondaryTextColor: Color(hex: "BE123C")
                ),
            ])
        case .night:
            ThemePalette(cardThemes: [
                .shoppingList: CardTheme(
                    gradientColors: [Color(hex: "1E1B4B"), Color(hex: "312E81")],
                    accentColor: Color(hex: "A78BFA"),
                    primaryTextColor: Color(hex: "EDE9FE"),
                    secondaryTextColor: Color(hex: "C4B5FD")
                ),
                .todo: CardTheme(
                    gradientColors: [Color(hex: "052E16"), Color(hex: "14532D")],
                    accentColor: Color(hex: "4ADE80"),
                    primaryTextColor: Color(hex: "DCFCE7"),
                    secondaryTextColor: Color(hex: "86EFAC")
                ),
                .backlog: CardTheme(
                    gradientColors: [Color(hex: "422006"), Color(hex: "713F12")],
                    accentColor: Color(hex: "FACC15"),
                    primaryTextColor: Color(hex: "FEF3C7"),
                    secondaryTextColor: Color(hex: "FDE68A")
                ),
                .recurring: CardTheme(
                    gradientColors: [Color(hex: "431407"), Color(hex: "7C2D12")],
                    accentColor: Color(hex: "FB923C"),
                    primaryTextColor: Color(hex: "FFEDD5"),
                    secondaryTextColor: Color(hex: "FDBA74")
                ),
                .household: CardTheme(
                    gradientColors: [Color(hex: "042F2E"), Color(hex: "134E4A")],
                    accentColor: Color(hex: "2DD4BF"),
                    primaryTextColor: Color(hex: "CCFBF1"),
                    secondaryTextColor: Color(hex: "5EEAD4")
                ),
                .areas: CardTheme(
                    gradientColors: [Color(hex: "0C4A6E"), Color(hex: "155E75")],
                    accentColor: Color(hex: "38BDF8"),
                    primaryTextColor: Color(hex: "E0F2FE"),
                    secondaryTextColor: Color(hex: "7DD3FC")
                ),
                .settings: CardTheme(
                    gradientColors: [Color(hex: "4C0519"), Color(hex: "881337")],
                    accentColor: Color(hex: "FB7185"),
                    primaryTextColor: Color(hex: "FFE4E6"),
                    secondaryTextColor: Color(hex: "FDA4AF")
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
        case .chalk:
            ThemePalette(cardThemes: [
                .shoppingList: CardTheme(
                    gradientColors: [Color(hex: "2C3E2D"), Color(hex: "3A5240")],
                    accentColor: Color(hex: "FFEB99"),
                    primaryTextColor: Color(hex: "F5F5DC"),
                    secondaryTextColor: Color(hex: "C8C8A9")
                ),
                .todo: CardTheme(
                    gradientColors: [Color(hex: "2A3A2A"), Color(hex: "354E38")],
                    accentColor: Color(hex: "FFB3B3"),
                    primaryTextColor: Color(hex: "FFFFFF"),
                    secondaryTextColor: Color(hex: "D5D5C0")
                ),
                .backlog: CardTheme(
                    gradientColors: [Color(hex: "2E3D2F"), Color(hex: "3C5041")],
                    accentColor: Color(hex: "ADD8E6"),
                    primaryTextColor: Color(hex: "F0F0E0"),
                    secondaryTextColor: Color(hex: "C0C0A8")
                ),
                .recurring: CardTheme(
                    gradientColors: [Color(hex: "2B3B2C"), Color(hex: "384D3C")],
                    accentColor: Color(hex: "98FB98"),
                    primaryTextColor: Color(hex: "FFFACD"),
                    secondaryTextColor: Color(hex: "D4D4B0")
                ),
                .household: CardTheme(
                    gradientColors: [Color(hex: "303E31"), Color(hex: "3F5343")],
                    accentColor: Color(hex: "FFA07A"),
                    primaryTextColor: Color(hex: "F5F5F0"),
                    secondaryTextColor: Color(hex: "CCCCB8")
                ),
                .areas: CardTheme(
                    gradientColors: [Color(hex: "2D3D2E"), Color(hex: "3B5040")],
                    accentColor: Color(hex: "B0E0E6"),
                    primaryTextColor: Color(hex: "FFFAF0"),
                    secondaryTextColor: Color(hex: "D0D0BC")
                ),
                .settings: CardTheme(
                    gradientColors: [Color(hex: "2F3F30"), Color(hex: "3D5242")],
                    accentColor: Color(hex: "DDA0DD"),
                    primaryTextColor: Color(hex: "F5F5E8"),
                    secondaryTextColor: Color(hex: "C5C5B0")
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

@MainActor
final class ThemeStore: ObservableObject {
    @AppStorage("themePreset") private var presetRawValue = ThemePreset.journal.rawValue
    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @AppStorage("celebrationsEnabled") var celebrationsEnabled = true
    @AppStorage("suggestionsEnabled") var suggestionsEnabled = true
    @AppStorage("tabTintColor") private var tabTintColorRawValue = TabTintColor.system.rawValue

    var preset: ThemePreset {
        get { ThemePreset(rawValue: presetRawValue) ?? .journal }
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

    var palette: ThemePalette {
        preset.palette
    }

    var resolvedTabTint: Color? {
        tabTintColor.color
    }

    var colorScheme: ColorScheme? {
        if preset == .retro || preset == .chalk {
            return .dark
        }
        return appearanceMode.colorScheme
    }

    /// Font resolved for current preset with graceful fallback.
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard
            let fontName = preset.fontName,
            UIFont(name: fontName, size: size) != nil
        else {
            return .system(size: size, weight: weight)
        }
        return .custom(fontName, size: size)
    }
}
