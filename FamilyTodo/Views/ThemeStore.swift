import SwiftUI

enum ThemePreset: String, CaseIterable, Identifiable {
    case pastel
    case soft
    case night

    var id: String { rawValue }

    var displayName: String {
        switch self {
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
        case .pastel:
            ThemePalette(cardThemes: [
                .shoppingList: CardTheme(
                    gradientColors: [Color(hex: "E9D5FF"), Color(hex: "DDD6FE")],
                    accentColor: Color(hex: "C084FC"),
                    primaryTextColor: Color(hex: "581C87"),
                    secondaryTextColor: Color(hex: "6B21A8")
                ),
                .todo: CardTheme(
                    gradientColors: [Color(hex: "DCFCE7"), Color(hex: "BBF7D0")],
                    accentColor: Color(hex: "4ADE80"),
                    primaryTextColor: Color(hex: "166534"),
                    secondaryTextColor: Color(hex: "15803D")
                ),
                .backlog: CardTheme(
                    gradientColors: [Color(hex: "FEF9C3"), Color(hex: "FEF08A")],
                    accentColor: Color(hex: "FACC15"),
                    primaryTextColor: Color(hex: "713F12"),
                    secondaryTextColor: Color(hex: "CA8A04")
                ),
                .recurring: CardTheme(
                    gradientColors: [Color(hex: "FED7AA"), Color(hex: "FDBA74")],
                    accentColor: Color(hex: "FB923C"),
                    primaryTextColor: Color(hex: "9A3412"),
                    secondaryTextColor: Color(hex: "C2410C")
                ),
                .household: CardTheme(
                    gradientColors: [Color(hex: "CCFBF1"), Color(hex: "99F6E4")],
                    accentColor: Color(hex: "2DD4BF"),
                    primaryTextColor: Color(hex: "115E59"),
                    secondaryTextColor: Color(hex: "0F766E")
                ),
                .areas: CardTheme(
                    gradientColors: [Color(hex: "BAE6FD"), Color(hex: "7DD3FC")],
                    accentColor: Color(hex: "38BDF8"),
                    primaryTextColor: Color(hex: "0C4A6E"),
                    secondaryTextColor: Color(hex: "0369A1")
                ),
                .settings: CardTheme(
                    gradientColors: [Color(hex: "FECDD3"), Color(hex: "FDA4AF")],
                    accentColor: Color(hex: "FB7185"),
                    primaryTextColor: Color(hex: "9F1239"),
                    secondaryTextColor: Color(hex: "BE123C")
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
        cardThemes[kind] ?? CardTheme(
            gradientColors: [Color(.systemGray5), Color(.systemGray4)],
            accentColor: Color(.systemGray),
            primaryTextColor: Color.primary,
            secondaryTextColor: Color.secondary
        )
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    @AppStorage("themePreset") private var presetRawValue = ThemePreset.pastel.rawValue

    var preset: ThemePreset {
        get { ThemePreset(rawValue: presetRawValue) ?? .pastel }
        set {
            presetRawValue = newValue.rawValue
            objectWillChange.send()
        }
    }

    var palette: ThemePalette {
        preset.palette
    }
}
