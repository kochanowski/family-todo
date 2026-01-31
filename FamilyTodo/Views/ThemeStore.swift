import SwiftUI

enum ThemePreset: String, CaseIterable, Identifiable {
    case journal
    case pastel
    case soft
    case night

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

@MainActor
final class ThemeStore: ObservableObject {
    @AppStorage("themePreset") private var presetRawValue = ThemePreset.journal.rawValue

    var preset: ThemePreset {
        get { ThemePreset(rawValue: presetRawValue) ?? .journal }
        set {
            presetRawValue = newValue.rawValue
            objectWillChange.send()
        }
    }

    var palette: ThemePalette {
        preset.palette
    }

    var colorScheme: ColorScheme? {
        switch preset {
        case .night:
            return .dark
        default:
            return nil // Use system default
        }
    }
}
