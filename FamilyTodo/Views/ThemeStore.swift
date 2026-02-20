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
    case sectionHeader
    case inlineTitle
    case bodyStrong
    case bodySmall
    case filterLabel
    case listRowTitle
    case profileName
    case celebrationMessage
    case chip
    case tabLabel
    case buttonLabel

    var size: CGFloat {
        switch self {
        case .screenHeader:
            28
        case .sectionHeader:
            12
        case .inlineTitle:
            16
        case .bodyStrong:
            15
        case .bodySmall:
            13
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
        case .tabLabel:
            10
        case .buttonLabel:
            15
        }
    }

    var weight: Font.Weight {
        switch self {
        case .screenHeader:
            .bold
        case .sectionHeader:
            .semibold
        case .inlineTitle:
            .medium
        case .bodyStrong, .buttonLabel:
            .semibold
        case .bodySmall:
            .regular
        case .filterLabel:
            .semibold
        case .profileName, .celebrationMessage:
            .semibold
        case .chip, .tabLabel:
            .medium
        case .listRowTitle:
            .regular
        }
    }

    var uiWeight: UIFont.Weight {
        switch self {
        case .screenHeader:
            .bold
        case .sectionHeader:
            .semibold
        case .inlineTitle:
            .medium
        case .bodyStrong, .buttonLabel, .filterLabel, .profileName, .celebrationMessage:
            .semibold
        case .bodySmall, .listRowTitle:
            .regular
        case .chip, .tabLabel:
            .medium
        }
    }

    var role: ThemeFontRole {
        switch self {
        case .screenHeader:
            .display
        case .profileName, .inlineTitle:
            .title
        case .chip, .tabLabel:
            .chip
        case .sectionHeader, .bodyStrong, .bodySmall, .filterLabel, .listRowTitle, .celebrationMessage,
             .buttonLabel:
            .body
        }
    }
}

enum PaperVariant: String, CaseIterable, Identifiable {
    case a, b, c, d, e, f, g
    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .a: "A – Classic"
        case .b: "B – Notebook"
        case .c: "C – Literary"
        case .d: "D – Journal"
        case .e: "E – Premium Editorial"
        case .f: "F – Modern Classic"
        case .g: "G – Handwritten Planner"
        }
    }

    var description: String {
        switch self {
        case .a: "SpecialElite + Georgia"
        case .b: "SpecialElite + CaveatBrush"
        case .c: "CaveatBrush + Baskerville"
        case .d: "CaveatBrush + Georgia"
        case .e: "System Serif + System Serif"
        case .f: "Georgia + Georgia"
        case .g: "CaveatBrush + CaveatBrush"
        }
    }

    var headerPostScriptName: String {
        switch self {
        case .a, .b: "SpecialElite-Regular"
        case .c, .d, .g: "CaveatBrush-Regular"
        case .e: "SystemSerif" // Intercepted
        case .f: "Georgia" // Intercepted
        }
    }

    var headerFamilyAliases: [String] {
        switch self {
        case .a, .b: ["Special Elite"]
        case .c, .d, .g: ["Caveat Brush"]
        case .e, .f: []
        }
    }

    var bodyFontName: String {
        switch self {
        case .a, .d, .f: "Georgia"
        case .b, .g: "CaveatBrush-Regular"
        case .c: "Baskerville"
        case .e: "SystemSerif" // Intercepted
        }
    }
}

enum FontSizeScale: String, CaseIterable, Identifiable {
    case small, regular, large
    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .small: "Small"
        case .regular: "Regular"
        case .large: "Large"
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .small: 0.85
        case .regular: 1.0
        case .large: 1.15
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
    case automatic
    case coral
    case rust
    case sand
    case forest

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .coral: "Coral"
        case .rust: "Rust"
        case .sand: "Warm Sand"
        case .forest: "Forest Green"
        }
    }

    var color: Color? {
        switch self {
        case .automatic: nil
        case .coral: Color(hex: "FF7F50")
        case .rust: Color(hex: "b7410e")
        case .sand: Color(hex: "dcb881")
        case .forest: Color(hex: "2E8B57")
        }
    }

    var iconName: String {
        switch self {
        case .automatic: "circle.lefthalf.filled"
        case .coral, .rust, .sand, .forest: "circle.fill"
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
    @Published private(set) var fontRegistration: FontRegistrationReport

    @AppStorage("themePreset") private var presetRawValue = ThemePreset.system.rawValue
    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @AppStorage("celebrationsEnabled") var celebrationsEnabled = true
    @AppStorage("tabTintColor") private var tabTintColorRawValue = TabTintColor.automatic.rawValue
    @AppStorage("paperVariant") private var paperVariantRawValue = PaperVariant.a.rawValue
    @AppStorage("paperFontScale") private var paperFontScaleRawValue = FontSizeScale.regular.rawValue
    @AppStorage("retroFontScale") private var retroFontScaleRawValue = FontSizeScale.regular.rawValue

    init(initialFontReport: FontRegistrationReport? = nil) {
        let report = initialFontReport ?? FontRegistrar.registerBundledFonts()
        fontRegistration = report
        logFontAudit(report)
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
        get { TabTintColor(rawValue: tabTintColorRawValue) ?? .automatic }
        set {
            tabTintColorRawValue = newValue.rawValue
            objectWillChange.send()
        }
    }

    var paperVariant: PaperVariant {
        get { PaperVariant(rawValue: paperVariantRawValue) ?? .a }
        set { paperVariantRawValue = newValue.rawValue; objectWillChange.send() }
    }

    var paperFontScale: FontSizeScale {
        get { FontSizeScale(rawValue: paperFontScaleRawValue) ?? .regular }
        set { paperFontScaleRawValue = newValue.rawValue; objectWillChange.send() }
    }

    var retroFontScale: FontSizeScale {
        get { FontSizeScale(rawValue: retroFontScaleRawValue) ?? .regular }
        set { retroFontScaleRawValue = newValue.rawValue; objectWillChange.send() }
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
        switch preset {
        case .retro:
            return Color(hex: "E94560")
        case .paper:
            if tabTintColor == .automatic {
                return Color(hex: "8B4513") // Warm default for paper
            }
            return tabTintColor.color
        case .system:
            if tabTintColor == .automatic {
                return Color(hex: "D9A259") // Warm default for system theme
            }
            return tabTintColor.color
        }
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

    func uiFont(for token: ThemeFontToken) -> UIFont {
        uiFont(size: token.size, weight: token.uiWeight, role: token.role)
    }

    /// Font resolved for current preset with graceful fallback.
    /// PressStart2P renders bigger than SF at same pt size, so we scale it down.
    func font(size: CGFloat, weight: Font.Weight = .regular, role: ThemeFontRole = .body) -> Font {
        let baseSize = size

        switch preset {
        case .retro:
            let scaledCustomSize = scaledRetroSize(baseSize, role: role) * retroFontScale.multiplier
            return customFont(
                postScriptName: "PressStart2P-Regular",
                baseSize: baseSize,
                customSize: scaledCustomSize,
                fallbackWeight: weight,
                familyAliases: ["Press Start 2P"]
            )
        case .paper:
            let variant = paperVariant
            let scale = paperFontScale.multiplier
            switch role {
            case .display, .title:
                if variant == .e {
                    return .system(size: baseSize * scale, weight: weight, design: .serif)
                } else if variant == .f {
                    return namedOrSystemFont(uiFontName: "Georgia", baseSize: baseSize * scale, fallbackWeight: weight)
                } else {
                    return customFont(
                        postScriptName: variant.headerPostScriptName,
                        baseSize: baseSize,
                        customSize: baseSize * scale,
                        fallbackWeight: weight,
                        familyAliases: variant.headerFamilyAliases,
                        fallbackUIFontName: "Georgia"
                    )
                }
            case .body, .chip:
                if variant.bodyFontName == "System" {
                    return .system(size: baseSize * scale, weight: weight)
                } else if variant.bodyFontName == "SystemSerif" {
                    return .system(size: baseSize * scale, weight: weight, design: .serif)
                }
                return namedOrSystemFont(
                    uiFontName: variant.bodyFontName,
                    baseSize: baseSize * scale,
                    fallbackWeight: weight
                )
            }
        case .system:
            return .system(size: baseSize, weight: weight)
        }
    }

    func uiFont(size: CGFloat, weight: UIFont.Weight = .regular, role: ThemeFontRole = .body) -> UIFont {
        let baseSize = size

        switch preset {
        case .retro:
            let scaledCustomSize = scaledRetroSize(baseSize, role: role) * retroFontScale.multiplier
            if let resolvedName = resolveCustomFontName(
                postScriptName: "PressStart2P-Regular",
                familyAliases: ["Press Start 2P"]
            ),
                let custom = UIFont(name: resolvedName, size: scaledCustomSize)
            {
                return custom
            }
            return .systemFont(ofSize: baseSize, weight: weight)
        case .paper:
            let variant = paperVariant
            let scale = paperFontScale.multiplier
            switch role {
            case .display, .title:
                if variant == .e {
                    let desc = UIFont.systemFont(ofSize: baseSize * scale, weight: weight).fontDescriptor
                    if let serifDesc = desc.withDesign(.serif) {
                        return UIFont(descriptor: serifDesc, size: baseSize * scale)
                    }
                    return .systemFont(ofSize: baseSize * scale, weight: weight)
                } else if variant == .f {
                    if let georgia = UIFont(name: "Georgia", size: baseSize * scale) {
                        return georgia
                    }
                    return .systemFont(ofSize: baseSize * scale, weight: weight)
                } else {
                    if let resolvedName = resolveCustomFontName(
                        postScriptName: variant.headerPostScriptName,
                        familyAliases: variant.headerFamilyAliases
                    ),
                        let custom = UIFont(name: resolvedName, size: baseSize * scale)
                    {
                        return custom
                    }
                    if let georgia = UIFont(name: "Georgia", size: baseSize * scale) {
                        return georgia
                    }
                    return .systemFont(ofSize: baseSize * scale, weight: weight)
                }
            case .body, .chip:
                if variant.bodyFontName == "System" {
                    return .systemFont(ofSize: baseSize * scale, weight: weight)
                } else if variant.bodyFontName == "SystemSerif" {
                    let desc = UIFont.systemFont(ofSize: baseSize * scale, weight: weight).fontDescriptor
                    if let serifDesc = desc.withDesign(.serif) {
                        return UIFont(descriptor: serifDesc, size: baseSize * scale)
                    }
                    return .systemFont(ofSize: baseSize * scale, weight: weight)
                }
                if let font = UIFont(name: variant.bodyFontName, size: baseSize * scale) {
                    return font
                }
                return .systemFont(ofSize: baseSize * scale, weight: weight)
            }
        case .system:
            return .systemFont(ofSize: baseSize, weight: weight)
        }
    }

    @discardableResult
    func verifyBundledFonts() -> FontRegistrationReport {
        let report = FontRegistrar.registerBundledFonts()
        fontRegistration = report
        logFontAudit(report)
        return report
    }

    private func customFont(
        postScriptName: String,
        baseSize: CGFloat,
        customSize: CGFloat,
        fallbackWeight: Font.Weight,
        familyAliases: [String] = [],
        fallbackUIFontName: String? = nil
    ) -> Font {
        if let resolvedName = resolveCustomFontName(
            postScriptName: postScriptName,
            familyAliases: familyAliases
        ) {
            return .custom(resolvedName, size: customSize)
        }

        if let fallbackUIFontName,
           UIFont(name: fallbackUIFontName, size: baseSize) != nil
        {
            return .custom(fallbackUIFontName, size: baseSize)
        }

        return .system(size: baseSize, weight: fallbackWeight)
    }

    private func namedOrSystemFont(
        uiFontName: String,
        baseSize: CGFloat,
        fallbackWeight: Font.Weight
    ) -> Font {
        if UIFont(name: uiFontName, size: baseSize) != nil {
            return .custom(uiFontName, size: baseSize)
        }
        return .system(size: baseSize, weight: fallbackWeight)
    }

    private func resolveCustomFontName(
        postScriptName: String,
        familyAliases: [String]
    ) -> String? {
        if fontRegistration.isFontAvailable(postScriptName: postScriptName) ||
            UIFont(name: postScriptName, size: 12) != nil
        {
            return postScriptName
        }

        for familyName in familyAliases {
            let familyFonts = UIFont.fontNames(forFamilyName: familyName)
            if let exactMatch = familyFonts.first(where: {
                $0.caseInsensitiveCompare(postScriptName) == .orderedSame
            }) {
                return exactMatch
            }
            if let firstAvailable = familyFonts.first {
                return firstAvailable
            }
        }

        if let item = fontRegistration.item(for: postScriptName) {
            if let exactMatch = item.availableFontNames.first(where: {
                $0.caseInsensitiveCompare(postScriptName) == .orderedSame
            }) {
                return exactMatch
            }
            if let firstAvailable = item.availableFontNames.first {
                return firstAvailable
            }
        }

        return nil
    }

    private func logFontAudit(_ report: FontRegistrationReport) {
        print("🧩 Theme fonts audit: \(report.statusSummary)")
        for item in report.items {
            let location = switch (item.foundInRootBundle, item.foundInResourcesFonts) {
            case (true, true):
                "root+Resources/Fonts"
            case (true, false):
                "root"
            case (false, true):
                "Resources/Fonts"
            case (false, false):
                "missing"
            }

            let registrationState = item.registrationAttempted
                ? (item.registrationSuccess ? "registered" : "register_failed")
                : "not_attempted"
            let availableFonts = item.availableFontNames.isEmpty
                ? "none"
                : item.availableFontNames.joined(separator: "|")
            let errorMessage = item.registrationError.map { " error=\($0)" } ?? ""

            print(
                "🧩 Font[\(item.postScriptName)] file=\(item.fileName) location=\(location) state=\(registrationState) detected=\(item.postScriptDetected) fonts=\(availableFonts)\(errorMessage)"
            )
        }
        print(
            "🧩 Theme font map: system=SF, retro=PressStart2P-Regular, paper=SpecialElite-Regular(headline)+Georgia(body), caveat=reserved"
        )
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
