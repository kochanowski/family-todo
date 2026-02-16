# claude-PLAN-codex-r4.md — 5 Features: Themes, Tab Colors, Avatars, Celebrations, Digest

> Autor: Claude · Data: 2026-02-16
> Plan dla Codex — implementacja 5 feature'ów

---

## Spis zmian

| # | Feature | Pliki | Effort |
|---|---------|-------|--------|
| 1 | Creative Themes (Retro + Paper + Chalk) | `ThemeStore.swift`, `MoreView.swift`, `AppColors.swift`, `Info.plist`, nowe fonty | 3h |
| 2 | Tab icon color customization | `ThemeStore.swift`, `ContentView.swift`, `MoreView.swift` | 45 min |
| 3 | Task assignee pill enhancement | `TasksView.swift` (TaskRow) | 30 min |
| 4 | Celebrations system (full) | NOWY `CelebrationManager.swift`, NOWY `CelebrationOverlay.swift`, `TasksView.swift`, `ShoppingListView.swift`, `FamilyTodoApp.swift` | 3h |
| 5 | Daily digest — app launch reschedule | `FamilyTodoApp.swift`, `NotificationService.swift` | 30 min |

---

## WAŻNE ZASADY

1. **Nie łamać istniejących funkcjonalności** — każda zmiana musi być backward-compatible
2. **Zachowywać istniejący styl kodu** — `WowAnimation.spring`, `HapticManager`, `@StateObject`, `_Concurrency.Task`
3. **Testować build po każdym kroku** — `xcodebuild build` musi przejść
4. **Commit atomicznie** — jeden commit per feature lub logiczną grupę
5. **iOS 17+ kompatybilność** — wszystkie nowe UI muszą działać na iOS 17+
6. **Komentarze w kodzie po angielsku** — zgodnie z CLAUDE.md

---

## Feature #1 — Creative Themes (Retro + Paper + Chalk)

### Problem
Brak UI do wyboru motywu (ThemePreset). Istnieją 4 presety (journal/pastel/soft/night) ale nie ma selectora. Użytkownik chce 3 nowe motywy kreatywne.

### Architektura zmian

Temat wymaga 3 warstw:
1. **ThemePreset** — paleta kolorów (CardTheme per CardKind)
2. **ThemeFont** — czcionka powiązana z motywem
3. **UI Selector** — widok w Settings do wyboru motywu

### Krok 1: Dodaj niestandardowe czcionki do projektu

**Pliki do dodania:**
- `FamilyTodo/Resources/Fonts/PressStart2P-Regular.ttf` — Retro (Google Fonts, OFL license)
- `FamilyTodo/Resources/Fonts/CaveatBrush-Regular.ttf` — Chalk/Tablica (Google Fonts, OFL license)
- `FamilyTodo/Resources/Fonts/SpecialElite-Regular.ttf` — Paper/maszyna do pisania (Google Fonts, OFL license)

**Plik:** `FamilyTodo/Info.plist` — dodaj klucz:
```xml
<key>UIAppFonts</key>
<array>
    <string>PressStart2P-Regular.ttf</string>
    <string>CaveatBrush-Regular.ttf</string>
    <string>SpecialElite-Regular.ttf</string>
</array>
```

**UWAGA:** Fonty muszą być dodane do Xcode target "FamilyTodo" (Copy Bundle Resources). Ponieważ dev jest na Linux, trzeba zaktualizować `project.pbxproj` — albo dodać fonty przez skrypt, albo opisać w PR do ręcznego dodania w Xcode.

### Krok 2: Rozszerz ThemePreset o nowe motywy

**Plik:** `FamilyTodo/Views/ThemeStore.swift`

**Dodaj do enum ThemePreset (po `case night`):**
```swift
case retro
case paper
case chalk
```

**Dodaj displayName:**
```swift
case .retro: "Retro"
case .paper: "Paper"
case .chalk: "Chalk"
```

**Dodaj palety kolorów:**

```swift
case .retro:
    // 8-bit Nintendo/Mario pixel feel — bright primaries on dark
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
    // Kraft paper / typewriter — warm sepia tones
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
    // Chalkboard / school blackboard — dark green/gray + white chalk
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
```

### Krok 3: Dodaj font per motyw do ThemeStore

**Plik:** `FamilyTodo/Views/ThemeStore.swift`

**Dodaj właściwość `fontName` do ThemePreset:**
```swift
/// Custom font for the theme. `nil` means system font.
var fontName: String? {
    switch self {
    case .retro: "PressStart2P-Regular"
    case .paper: "SpecialElite-Regular"
    case .chalk: "CaveatBrush-Regular"
    default: nil
    }
}
```

**Dodaj helper do ThemeStore:**
```swift
/// Font for the current theme. Falls back to system font.
func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    if let fontName = preset.fontName {
        return .custom(fontName, size: size)
    }
    return .system(size: size, weight: weight)
}
```

**Dodaj `iconName` do ThemePreset (do użycia w selectorze):**
```swift
var iconName: String {
    switch self {
    case .journal: "book.fill"
    case .pastel: "paintpalette.fill"
    case .soft: "cloud.fill"
    case .night: "moon.stars.fill"
    case .retro: "gamecontroller.fill"
    case .paper: "newspaper.fill"
    case .chalk: "pencil.and.outline"
    }
}
```

### Krok 4: Dodaj AppColors dla nowych motywów

**Plik:** `FamilyTodo/Utilities/AppColors.swift`

Zmienić `palette(for:)`:
```swift
// OBECNE:
static func palette(for preset: ThemePreset) -> AppColorPalette {
    preset == .night ? night : light
}

// NOWE:
static func palette(for preset: ThemePreset) -> AppColorPalette {
    switch preset {
    case .night: night
    case .retro: retro
    case .chalk: chalk
    default: light
    }
}
```

Dodać nowe palety:
```swift
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
```

### Krok 5: Dodaj Theme Preset Selector UI w Settings

**Plik:** `FamilyTodo/Views/MoreView.swift` — w `SettingsView.body`, PO sekcji "Appearance" (linia ~744), dodaj nową sekcję:

```swift
// MARK: - Theme Section
Section {
    ThemePresetSelector(selectedPreset: Binding(
        get: { themeStore.preset },
        set: {
            HapticManager.selection()
            themeStore.preset = $0
        }
    ))
    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    .listRowBackground(Color.clear)
} header: {
    Text("Theme")
}
```

**Dodaj komponent `ThemePresetSelector` na końcu MoreView.swift (po AppearanceSelector):**

```swift
private struct ThemePresetSelector: View {
    @Binding var selectedPreset: ThemePreset

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ThemePreset.allCases) { preset in
                    ThemePresetCard(
                        preset: preset,
                        isSelected: selectedPreset == preset
                    ) {
                        selectedPreset = preset
                    }
                }
            }
        }
    }
}

private struct ThemePresetCard: View {
    let preset: ThemePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Color preview swatch
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: preset.palette.theme(for: .todo).gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 40)
                    .overlay(
                        Image(systemName: preset.iconName)
                            .font(.system(size: 16))
                            .foregroundStyle(preset.palette.theme(for: .todo).accentColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(preset.displayName)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
```

### Krok 6: AppearanceMode — Retro/Chalk wymuszają dark

**Plik:** `FamilyTodo/Views/ThemeStore.swift` — zmień `colorScheme` computed property:

```swift
// OBECNE:
var colorScheme: ColorScheme? {
    appearanceMode.colorScheme
}

// NOWE:
var colorScheme: ColorScheme? {
    // Retro and Chalk are dark-only themes
    if preset == .retro || preset == .chalk {
        return .dark
    }
    return appearanceMode.colorScheme
}
```

---

## Feature #2 — Tab Icon Color Customization

### Problem
Użytkownik chce zmieniać kolor ikon tab bar w Settings.

### Krok 1: Dodaj enum i storage

**Plik:** `FamilyTodo/Views/ThemeStore.swift`

**Dodaj enum `TabTintColor` (przed ThemeStore class):**
```swift
enum TabTintColor: String, CaseIterable, Identifiable {
    case system
    case green
    case red
    case blue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "Default"
        case .green: "Green"
        case .red: "Red"
        case .blue: "Blue"
        }
    }

    var color: Color? {
        switch self {
        case .system: nil
        case .green: .green
        case .red: .red
        case .blue: .blue
        }
    }

    var iconName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .green: "circle.fill"
        case .red: "circle.fill"
        case .blue: "circle.fill"
        }
    }
}
```

**Dodaj do ThemeStore class:**
```swift
@AppStorage("tabTintColor") private var tabTintColorRawValue = TabTintColor.system.rawValue

var tabTintColor: TabTintColor {
    get { TabTintColor(rawValue: tabTintColorRawValue) ?? .system }
    set {
        tabTintColorRawValue = newValue.rawValue
        objectWillChange.send()
    }
}

var resolvedTabTint: Color? {
    tabTintColor.color
}
```

### Krok 2: Zastosuj .tint() na TabView

**Plik:** `FamilyTodo/ContentView.swift`

**Dodaj `@EnvironmentObject` do MainAppView (linia ~22):**
```swift
@EnvironmentObject private var themeStore: ThemeStore
```

**Zmień `modernTabView` (linia ~42-64) — dodaj .tint() po zamknięciu TabView:**
```swift
// OBECNE:
TabView(selection: $activeTab) {
    // ... tabs ...
}

// NOWE:
TabView(selection: $activeTab) {
    // ... tabs ...
}
.tint(themeStore.resolvedTabTint)
```

**Zmień `legacyTabView` (linia ~67-101) — analogicznie:**
```swift
TabView(selection: $activeTab) {
    // ... tabs ...
}
.tint(themeStore.resolvedTabTint)
```

### Krok 3: UI w Settings

**Plik:** `FamilyTodo/Views/MoreView.swift` — w `SettingsView.body`, po sekcji "Theme" z Feature #1, dodaj:

```swift
// MARK: - Tab Color Section
Section {
    HStack(spacing: 16) {
        ForEach(TabTintColor.allCases) { tint in
            Button {
                HapticManager.selection()
                themeStore.tabTintColor = tint
            } label: {
                VStack(spacing: 4) {
                    Circle()
                        .fill(tint.color ?? Color.accentColor)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(themeStore.tabTintColor == tint ? Color.primary : Color.clear, lineWidth: 2)
                        )
                    Text(tint.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(themeStore.tabTintColor == tint ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
        Spacer()
    }
    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
} header: {
    Text("Tab bar color")
}
```

---

## Feature #3 — Task Assignee Pill Enhancement

### Problem
Obecny pill assignee w TaskRow (linia 842-855 w TasksView.swift) jest za mały i niewidoczny. Użytkownik chce go powiększyć i dodać kolorowe tło per member.

### Zmiana

**Plik:** `FamilyTodo/Views/TasksView.swift`, TaskRow, linie 842-855

**Dodaj `assigneeId` do TaskRow:**
```swift
// OBECNE (linia 800-801):
let task: Task
let assigneeName: String?

// NOWE:
let task: Task
let assigneeName: String?
let assigneeId: String?
```

**Zaktualizuj tworzenie TaskRow wszędzie (linie ~238-252, ~258-278, sekcja done):**
```swift
// Dodaj nowy parametr:
TaskRow(
    task: task,
    assigneeName: assigneeName(for: task),
    assigneeId: task.assigneeId,
    // ... reszta parametrów
)
```

**Zamień blok assignee w TaskRow (linie 842-855):**
```swift
// OBECNE:
if let assigneeName {
    let ownerColor = categoryColor ?? .secondary
    HStack(spacing: 4) {
        Image(systemName: "person.fill")
            .font(.system(size: 8))
            .foregroundStyle(ownerColor)
        Text(assigneeName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ownerColor)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Capsule().fill(ownerColor.opacity(0.12)))
}

// NOWE:
if let assigneeName {
    let memberColor = Self.memberColor(for: assigneeId)
    HStack(spacing: 5) {
        // Colored circle with initial
        Text(String(assigneeName.prefix(1)).uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(memberColor))

        Text(assigneeName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(memberColor)
    }
    .padding(.trailing, 8)
    .padding(.leading, 2)
    .padding(.vertical, 3)
    .background(Capsule().fill(memberColor.opacity(0.12)))
}
```

**Dodaj statyczną funkcję do TaskRow (np. po `dateFormatter`):**
```swift
/// Deterministic color for a member based on their ID hash
private static func memberColor(for id: String?) -> Color {
    guard let id else { return .secondary }
    let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint]
    let hash = abs(id.hashValue)
    return colors[hash % colors.count]
}
```

---

## Feature #4 — Celebrations System (Full)

### Problem
Toggle `celebrationsEnabled` istnieje w Settings, ale zero logiki celebrations. Potrzebny pełny system: toast + confetti + notyfikacja partnerowi.

### Krok 1: Stwórz CelebrationManager

**NOWY PLIK:** `FamilyTodo/Services/CelebrationManager.swift`

```swift
import SwiftUI

/// Duolingo-style gentle celebrations — private, optional, never competitive
@MainActor
final class CelebrationManager: ObservableObject {
    static let shared = CelebrationManager()

    @Published var activeCelebration: Celebration?

    struct Celebration: Identifiable, Equatable {
        let id = UUID()
        let emoji: String
        let message: String
        let style: Style

        enum Style {
            case normal      // Simple toast
            case milestone   // Toast + confetti
        }

        static func == (lhs: Celebration, rhs: Celebration) -> Bool {
            lhs.id == rhs.id
        }
    }

    private init() {}

    /// Celebrate a single task completion
    func celebrateTaskCompletion(taskTitle: String) {
        let messages = [
            ("✨", "Done! \(taskTitle)"),
            ("👏", "Nice one!"),
            ("✅", "\(taskTitle) — sorted!"),
            ("💪", "Crushed it!"),
        ]
        let pick = messages.randomElement()!
        show(Celebration(emoji: pick.0, message: pick.1, style: .normal))
    }

    /// Celebrate all tasks cleared from Next
    func celebrateAllTasksComplete() {
        show(Celebration(emoji: "🎉", message: "All tasks done! Time to relax", style: .milestone))
    }

    /// Celebrate shopping list cleared
    func celebrateShoppingComplete() {
        show(Celebration(emoji: "🛒", message: "Shopping done! Fridge is happy", style: .milestone))
    }

    /// Notify partner about completion (local notification)
    func notifyPartner(completedBy memberName: String, action: String) {
        #if !targetEnvironment(simulator) && !CI
        let content = UNMutableNotificationContent()
        content.title = "💙 \(memberName) is on fire!"
        content.body = action
        content.sound = .default
        content.categoryIdentifier = "CELEBRATION"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "celebration-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        _Concurrency.Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
        #endif
    }

    private func show(_ celebration: Celebration) {
        activeCelebration = celebration
        HapticManager.success()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.activeCelebration?.id == celebration.id {
                withAnimation(WowAnimation.easeOut) {
                    self?.activeCelebration = nil
                }
            }
        }
    }
}
```

### Krok 2: Stwórz CelebrationOverlay

**NOWY PLIK:** `FamilyTodo/Views/Components/CelebrationOverlay.swift`

```swift
import SwiftUI

/// Overlay view that shows celebration toasts and optional confetti
struct CelebrationOverlay: View {
    @ObservedObject var manager: CelebrationManager

    var body: some View {
        ZStack {
            if let celebration = manager.activeCelebration {
                VStack {
                    Spacer()

                    HStack(spacing: 10) {
                        Text(celebration.emoji)
                            .font(.system(size: 24))

                        Text(celebration.message)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))

                    Spacer().frame(height: 100) // Above tab bar
                }
                .animation(WowAnimation.spring, value: manager.activeCelebration)
            }
        }
        .allowsHitTesting(false)
    }
}
```

### Krok 3: Dodaj CelebrationOverlay do app root

**Plik:** `FamilyTodo/FamilyTodoApp.swift`

**Dodaj StateObject (po istniejących, linia ~11):**
```swift
@StateObject private var celebrationManager = CelebrationManager.shared
```

**Dodaj overlay + environmentObject do RootView (linia ~75-81):**
```swift
// OBECNE:
RootView()
    .environmentObject(userSession)
    // ...

// NOWE:
RootView()
    .environmentObject(userSession)
    .environmentObject(themeStore)
    .environmentObject(householdStore)
    .environmentObject(onboardingState)
    .environmentObject(subscriptionManager)
    .environmentObject(celebrationManager) // DODANE
    .modelContainer(sharedModelContainer)
    .preferredColorScheme(themeStore.colorScheme)
    .overlay {
        CelebrationOverlay(manager: celebrationManager)
    }
    // ... .task { ... }
```

### Krok 4: Trigger celebrations w TasksView

**Plik:** `FamilyTodo/Views/TasksView.swift`

**Dodaj EnvironmentObject (po istniejących):**
```swift
@EnvironmentObject private var celebrationManager: CelebrationManager
@EnvironmentObject private var themeStore: ThemeStore
```

**W `toggleTask` — po `HapticManager.mediumTap()` (normalna kompletacja, linia ~557):**
```swift
// OBECNE:
HapticManager.mediumTap()

// NOWE:
HapticManager.mediumTap()
if themeStore.celebrationsEnabled {
    celebrationManager.celebrateTaskCompletion(taskTitle: task.title)
    // Notify partner if multi-member household
    if activeMembers.count > 1, let name = currentMember?.displayName {
        celebrationManager.notifyPartner(
            completedBy: name,
            action: "\(task.title) — done!"
        )
    }
}
```

**W bloku `willCompleteAll` (linia ~551-555):**
```swift
// OBECNE:
HapticManager.success()
showAllCompleteAnimation = true

// NOWE:
HapticManager.success()
showAllCompleteAnimation = true
if themeStore.celebrationsEnabled {
    celebrationManager.celebrateAllTasksComplete()
    if activeMembers.count > 1, let name = currentMember?.displayName {
        celebrationManager.notifyPartner(
            completedBy: name,
            action: "Cleared all tasks! 🏡"
        )
    }
}
```

### Krok 5: Trigger celebrations w ShoppingListView

**Plik:** `FamilyTodo/Views/ShoppingListView.swift`

Znaleźć akcję "Clear all" / "Mark all as bought" i dodać:
```swift
if themeStore.celebrationsEnabled {
    celebrationManager.celebrateShoppingComplete()
}
```

**UWAGA:** Trzeba sprawdzić dokładną lokalizację tej akcji w ShoppingListView — prawdopodobnie przy akcji clear/restock.

---

## Feature #5 — Daily Digest: App Launch Reschedule

### Problem
Daily digest jest w pełni zaimplementowany, ale NIE jest reschedulowany po reinstalacji/restart. Jest schedulowany tylko gdy user odwiedzi Settings. Komunikat jest generyczny.

### Krok 1: Reschedule na starcie aplikacji

**Plik:** `FamilyTodo/FamilyTodoApp.swift` — w `.task { }` bloku (linia ~83-107), dodaj po `ChoreScheduler`:

```swift
// OBECNE (koniec .task bloku):
await ChoreScheduler.shared.runIfNeeded(
    householdId: userSession.currentHouseholdID,
    modelContext: sharedModelContainer.mainContext,
    syncMode: userSession.syncMode
)

// NOWE:
await ChoreScheduler.shared.runIfNeeded(
    householdId: userSession.currentHouseholdID,
    modelContext: sharedModelContainer.mainContext,
    syncMode: userSession.syncMode
)

// Re-schedule daily digest on every app launch
#if !CI
let notifSettings = NotificationSettingsStore()
NotificationService.shared.setSettingsStore(notifSettings)
await NotificationService.shared.checkAuthorizationStatus()
if notifSettings.isEnabled, notifSettings.dailyDigestEnabled {
    let components = Calendar.current.dateComponents([.hour, .minute], from: notifSettings.reminderTime)
    await NotificationService.shared.scheduleDailyDigest(
        at: components.hour ?? 8,
        minute: components.minute ?? 0
    )
}
#endif
```

### Krok 2 (Opcjonalnie): Personalizuj treść digestu

**Plik:** `FamilyTodo/Services/NotificationService.swift` — linie 106-108

Obecny komunikat jest generyczny: "Good morning! / Check your tasks for today".
Można wzbogacić o liczbę tasków, ale wymagałoby to parametryzacji `scheduleDailyDigest`.

**Decyzja:** Na razie zostawiamy obecny komunikat — personalizacja wymaga dostępu do TaskStore w momencie schedulowania, co komplikuje architekturę. Zostawiamy jako TODO na przyszłość.

---

## Podsumowanie odpowiedzi na pytania użytkownika

| # | Pytanie | Odpowiedź |
|---|---------|-----------|
| 1 | Themes Retro/Paper/Chalk — czy to możliwe? | **TAK.** Custom fonty przez Info.plist + `.custom()`. Retro = Press Start 2P, Paper = Special Elite, Chalk = Caveat Brush. |
| 2 | Zmiana koloru ikon tab bar | **TAK.** `.tint()` na TabView + @AppStorage. Proste 4 opcje: default/green/red/blue. |
| 3 | Awatar/bąbelek przy taskach | **JUŻ ISTNIEJE** jako mały pill. Powiększamy: 13pt font + kolorowe kółko z inicjałem 20x20. |
| 4 | Celebrations — jak mają działać? | Toast z emoji + haptic przy każdym tasku. Confetti + toast przy "all complete". Powiadomienie lokalne partnerowi. Opcjonalne (toggle w Settings). |
| 5 | Daily digest — czy działa? | **TAK, w pełni zaimplementowany.** O domyślnej 8:00 rano, komunikat: "Good morning! / Check your tasks for today". Brakuje tylko reschedule na app launch — naprawiamy. |

---

## Kolejność implementacji

1. **Feature #5** (Daily digest fix) — 30 min, zero zależności
2. **Feature #3** (Assignee pill) — 30 min, zero zależności
3. **Feature #2** (Tab colors) — 45 min, wymaga ThemeStore zmian
4. **Feature #1** (Themes) — 3h, wymaga font files + ThemeStore + MoreView
5. **Feature #4** (Celebrations) — 3h, wymaga nowych plików + integracji

Feature #5, #3, #2 mogą iść równolegle. Feature #1 i #4 wymagają kolejności (ThemeStore zmiany z #1 muszą być gotowe przed #4 bo #4 czyta `celebrationsEnabled`).

---

## Weryfikacja

Po implementacji:
1. `pre-commit run --all-files` — musi przejść
2. Build via GitHub Actions — `xcodebuild build` musi przejść
3. Manual test na iPhone 15:
   - Settings → Theme selector → przełącz między motywami → UI zmienia kolory
   - Settings → Tab bar color → zmień kolor → tab bar icons zmieniają kolor
   - Tasks → stwórz task z assignee → widoczny powiększony pill z inicjałem
   - Tasks → zakończ task → toast celebration pojawia się na 2.5s
   - Tasks → zakończ ostatni Next task → milestone celebration
   - Shopping → wyczyść listę → celebration toast
   - Zabij i uruchom app → daily digest powinien być zaschedulowany
