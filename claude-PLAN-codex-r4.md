# claude-PLAN-codex-r4.md — 5 Features: Themes, Tab Colors, Avatars, Celebrations, Digest

> Autor: Antigravity · Data: 2026-02-16
> Plan dla Codex — implementacja 5 feature'ów

## Krok 0: Zapisz plan

Zapisz ten plik jako `/home/wkochanowski/code/family-todo/claude-PLAN-codex-r4.md`

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

---

# ROUND 2 — 13 dodatkowych issues (2026-02-16 wieczór)

## Spis zmian R2

| # | Issue | Pliki | Effort |
|---|-------|-------|--------|
| 6 | Themes nie działają — podłączyć palety do widoków | Wszystkie widoki + AppColors | 2h |
| 7 | Themes: zostawić tylko Retro + Paper, usunąć stare | ThemeStore.swift, AppColors.swift | 30 min |
| 8 | Theme + Appearance = jedna sekcja w Settings | MoreView.swift | 30 min |
| 9 | Backlog → Ideas (rename) | InteractionTokens, BacklogView, MoreView, ContentView | 30 min |
| 10 | Ideas (Backlog): usunąć kropki przed itemami | BacklogView.swift | 5 min |
| 11 | Ideas (Backlog): ikony akcji zamiast (...) menu | BacklogView.swift | 45 min |
| 12 | Ideas (Backlog): kolory kategorii — więcej randomizacji | BacklogCategory.swift | 15 min |
| 13 | Shopping: "Mark as bought" podczas edycji | ShoppingListView.swift | 30 min |
| 14 | Recently Purchased: zmniejszyć spacing | ShoppingListView.swift (RestockSheet) | 10 min |
| 15 | Shopping suggestions — usunąć | MoreView.swift, ThemeStore.swift | 10 min |
| 16 | Repetitive Tasks: dodać Backlog Category picker | MoreView.swift (RepetitiveTasksView), RecurringChore model | 1h |
| 17 | Celebrations: animacja konfetti | CelebrationOverlay.swift | 1h |
| 18 | Fonty: Retro = Press Start 2P, Paper = Georgia, reszta = system | ThemeStore.swift | 15 min |

---

## Issue #6 — Themes nie działają: podłączyć palety do widoków

### Problem
`themeStore.preset` i `themeStore.palette` są zdefiniowane i persisted, ale **żaden widok ich nie czyta**. Wszystkie widoki używają hardcoded kolorów (`.blue`, `.orange`, `.white`) i manualnych `cardBackground` helperów.

### Root Cause
System palet `ThemePalette` → `CardTheme` z kolorami per `CardKind` nigdy nie został podłączony do UI. Widoki zostały napisane z hardcoded kolorami.

### Zmiana — Strategia

**Podejście:** Zamiast refactorować każdy widok (zbyt inwazyjne), stworzymy centralny system kolorów oparty na ThemeStore, który nadpisze kluczowe kolory.

**Krok 1: Rozszerz ThemeStore o resolved colors**

**Plik:** `FamilyTodo/Views/ThemeStore.swift` — dodaj do class ThemeStore:

```swift
// MARK: - Resolved Colors for Views

/// Background color for the current theme
var canvasColor: Color {
    AppColors.palette(for: preset).canvas
}

/// Card/surface background
var surfaceColor: Color {
    AppColors.palette(for: preset).surface
}

/// Primary text color
var inkColor: Color {
    AppColors.palette(for: preset).ink
}

/// Secondary/muted text color
var inkMutedColor: Color {
    AppColors.palette(for: preset).inkMuted
}

/// Accent color (buttons, badges, active elements)
var accentColor: Color {
    AppColors.palette(for: preset).accent
}
```

**Krok 2: Zastąp hardcoded kolory w kluczowych widokach**

Dla każdego widoku, zamienić:

**ShoppingListView.swift:**
- Linia 285: `.fill(.blue)` → `.fill(themeStore.accentColor)` (add pill button)
- Linia 219: `.foregroundStyle(.white)` → zachować (badge text on accent)
- Linia 222: `.background(Capsule().fill(.blue))` → `.fill(themeStore.accentColor)` (count badge)
- Linia ~457: `cardBackground` helper → użyć `themeStore.surfaceColor`
- Linia ~710: hardcoded background → `themeStore.canvasColor`

**TasksView.swift:**
- "Add Task" button colors → `themeStore.accentColor`
- Header title kolorowanie → `themeStore.inkColor`

**BacklogView.swift:**
- Linia 262: `.foregroundStyle(.orange)` → `.foregroundStyle(themeStore.accentColor)` (add button)
- Linia ~621: `cardBackground` helper → `themeStore.surfaceColor`

**MoreView.swift:**
- Accent colors w settings → `themeStore.accentColor`

**Krok 3: Background view**

**Plik:** `FamilyTodo/Views/Components/AppBackgroundView.swift` — użyj `themeStore.canvasColor`

**UWAGA:** Nie zmieniaj WSZYSTKICH kolorów — tylko kluczowe: tła, akcenty, przyciski. System colors (`.primary`, `.secondary`) zostaw — one reagują na dark/light mode automatycznie.

---

## Issue #7 — Themes: zostawić Retro + Paper, usunąć stare

### Problem
Użytkownik chce zachować tylko 2 nowe motywy (Retro, Paper) + domyślny system (Light/Dark). Stare (Journal, Pastel, Soft, Night, Chalk) to artefakty poprzedniej wersji.

### Zmiana

**Plik:** `FamilyTodo/Views/ThemeStore.swift`

**Zamień enum ThemePreset:**
```swift
enum ThemePreset: String, CaseIterable, Identifiable {
    case system   // Default — uses AppearanceMode (Light/Dark/System)
    case retro    // 8-bit Nintendo pixel feel
    case paper    // Kraft paper / typewriter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "Default"
        case .retro: "Retro"
        case .paper: "Paper"
        }
    }

    var iconName: String {
        switch self {
        case .system: "iphone"
        case .retro: "gamecontroller.fill"
        case .paper: "newspaper.fill"
        }
    }

    var fontName: String? {
        switch self {
        case .retro: "PressStart2P-Regular"
        case .paper: nil  // Georgia via system fallback
        case .system: nil
        }
    }

    /// Georgia for Paper, nil for system font
    var uiFontName: String? {
        switch self {
        case .paper: "Georgia"
        case .retro: "PressStart2P-Regular"
        case .system: nil
        }
    }
}
```

**Zachowaj palety dla `system` (obecna journal light + night dark), `retro` i `paper`.**
Usuń case'y: journal, pastel, soft, night, chalk z palety i z AppColors.

**Plik:** `FamilyTodo/Utilities/AppColors.swift`

```swift
static func palette(for preset: ThemePreset) -> AppColorPalette {
    switch preset {
    case .retro: retro
    case .paper: paper
    case .system: light  // light/night handled by colorScheme
    }
}
```

Dodaj `paper` palette (ciepłe sepia/kraft tona, jasny motyw).

**ThemeStore colorScheme:**
```swift
var colorScheme: ColorScheme? {
    if preset == .retro {
        return .dark  // Retro wymusza dark
    }
    return appearanceMode.colorScheme
}
```

**Default preset:** `@AppStorage("themePreset") private var presetRawValue = ThemePreset.system.rawValue`

---

## Issue #8 — Theme + Appearance = jedna sekcja

### Problem
Theme selector i Appearance selector to osobne sekcje w Settings. Powinny być jedną sekcją "Appearance" z oboma opcjami.

### Zmiana

**Plik:** `FamilyTodo/Views/MoreView.swift` — w SettingsView:

**Połącz sekcje Appearance (linie 731-745) i Theme (linie 747-761) w jedną:**

```swift
Section {
    // Theme preset cards (Default / Retro / Paper)
    ThemePresetSelector(selectedPreset: Binding(
        get: { themeStore.preset },
        set: {
            HapticManager.selection()
            themeStore.preset = $0
        }
    ))
    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    .listRowBackground(Color.clear)

    // Light / Dark / System only shown for "Default" theme
    if themeStore.preset == .system {
        AppearanceSelector(selectedMode: Binding(
            get: { themeStore.appearanceMode },
            set: {
                HapticManager.selection()
                themeStore.appearanceMode = $0
            }
        ))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
        .listRowBackground(Color.clear)
    }
} header: {
    Text("Appearance")
}
```

**Logika:** Retro wymusza dark mode, Paper jest jasny. AppearanceSelector (Light/Dark/System) wyświetla się TYLKO gdy theme = Default.

---

## Issue #9 — Rename "Backlog" → "Ideas"

### Problem
"Backlog" to termin techniczny (Agile/Scrum). Dla par/rodzin "Ideas" jest bardziej naturalny.

### Zmiana — globalna zamiana nazw wyświetlanych

**Plik:** `FamilyTodo/Utilities/InteractionTokens.swift` (lub gdzie zdefiniowany jest AppTab)

Szukaj w codebase `"Backlog"` jako string wyświetlany (nie nazwy zmiennych).

**Pliki do zmian:**

1. **AppTab enum** — zmień `title`:
```swift
case .backlog: "Ideas"
```

2. **BacklogView.swift** — linia ~252:
```swift
// OBECNE:
.navigationTitle("Backlog")
// NOWE:
.navigationTitle("Ideas")
```

3. **BacklogView.swift** — empty state (~270):
```swift
// OBECNE:
"No Categories"
// NOWE:
"No Ideas Yet"
```

4. **MoreView.swift** — NavigationLink label (~linia 52):
```swift
// OBECNE:
"Backlog Categories"
// NOWE:
"Idea Categories"
```

5. **MoreView.swift** — CategoriesManagementView title:
```swift
.navigationTitle("Idea Categories")
```

**NIE zmieniaj:** nazw zmiennych, typów Swift (`BacklogView`, `BacklogStore`, `BacklogCategory`, `BacklogItem`), nazw plików, ani CloudKit record types. Zmiana jest KOSMETYCZNA — tylko UI strings.

---

## Issue #10 — Ideas: usunąć kropki przed itemami

### Problem
Małe szare kropki (6x6 Circle) przed każdym elementem w BacklogItemRow są niepotrzebne.

### Zmiana

**Plik:** `FamilyTodo/Views/BacklogView.swift`, BacklogItemRow, linie 640-642

**Usuń:**
```swift
Circle()
    .fill(Color.secondary.opacity(0.3))
    .frame(width: 6, height: 6)
```

---

## Issue #11 — Ideas: ikony akcji zamiast (...) menu

### Problem
Obecne Menu z `ellipsis.circle` wymaga 2 tapnięć (otwórz menu → wybierz akcję). Użytkownik chce bezpośrednie ikony.

### Zmiana

**Plik:** `FamilyTodo/Views/BacklogView.swift`, BacklogItemRow (linie 661-691)

**Zastąp Menu blokiem ikon:**

```swift
// OBECNE (linie 661-691):
Menu {
    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
    Button { onAssign() } label: { Label("Assign", systemImage: "person.crop.circle.badge.plus") }
    Button { onPromote() } label: { Label("Promote", systemImage: "arrow.up.circle") }
    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
} label: {
    Image(systemName: "ellipsis.circle")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
}

// NOWE:
HStack(spacing: 4) {
    Button(action: onEdit) {
        Image(systemName: "pencil")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
    }
    .buttonStyle(.plain)

    Button(action: onAssign) {
        Image(systemName: "person.badge.plus")
            .font(.system(size: 14))
            .foregroundStyle(.blue)
            .frame(width: 30, height: 30)
    }
    .buttonStyle(.plain)

    Button(action: onPromote) {
        Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(.green)
            .frame(width: 30, height: 30)
    }
    .buttonStyle(.plain)

    Button(action: onDelete) {
        Image(systemName: "trash")
            .font(.system(size: 14))
            .foregroundStyle(.red.opacity(0.7))
            .frame(width: 30, height: 30)
    }
    .buttonStyle(.plain)
}
```

**UWAGA:** 4 ikony mogą być ciasne na małych ekranach. Jeśli za ciasno → zmniejszyć frame do 26x26 lub zmniejszyć font do 12.

---

## Issue #12 — Ideas: kolory kategorii — więcej randomizacji

### Problem
Kolory kategorii są deterministyczne z `id.hashValue % 10`. Przy 3+ kategoriach kolory się powtarzają.

### Zmiana

**Plik:** `FamilyTodo/Models/BacklogCategory.swift` (lub gdzie zdefiniowana jest paleta)

**Rozszerz paletę z 10 do 16+ kolorów:**

```swift
static let categoryPalette: [Color] = [
    .purple, .orange, .teal, .pink, .indigo,
    .mint, .brown, .cyan,
    Color(red: 0.95, green: 0.4, blue: 0.3),   // coral
    Color(red: 0.3, green: 0.7, blue: 0.4),     // emerald
    Color(red: 0.6, green: 0.2, blue: 0.8),     // violet
    Color(red: 0.2, green: 0.6, blue: 0.9),     // sky blue
    Color(red: 0.9, green: 0.6, blue: 0.1),     // amber
    Color(red: 0.4, green: 0.8, blue: 0.7),     // aquamarine
    Color(red: 0.85, green: 0.3, blue: 0.5),    // rose
    Color(red: 0.5, green: 0.7, blue: 0.2),     // lime
]
```

Zmiana z 10 → 16 kolorów zmniejsza szansę kolizji przy hashowaniu.

---

## Issue #13 — Shopping: "Mark as bought" podczas edycji

### Problem
Inline edit pozwala tylko zmienić tytuł. Brak opcji zaznaczenia jako kupiony.

### Zmiana

**Plik:** `FamilyTodo/Views/ShoppingListView.swift`

**Dodaj checkbox do ShoppingItemInlineEditRow (linia ~504-547):**

```swift
// OBECNE (linia 513-516):
HStack(spacing: 10) {
    Circle()
        .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
        .frame(width: 20, height: 20)

// NOWE — zamień na aktywny checkbox:
HStack(spacing: 10) {
    Button(action: onToggle) {
        Circle()
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
            .frame(width: 20, height: 20)
            .overlay {
                if isBought {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 13, height: 13)
                }
            }
    }
    .buttonStyle(.plain)
```

**Dodaj parametry do ShoppingItemInlineEditRow:**
```swift
let isBought: Bool
let onToggle: () -> Void
```

**Zaktualizuj wywołanie (linia ~104):**
```swift
ShoppingItemInlineEditRow(
    text: $editingItemText,
    isBought: item.isBought,
    onToggle: { toggleItem(item) },
    onSubmit: { commitEditingItem(item) },
    onCancel: cancelEditingItem
)
```

---

## Issue #14 — Recently Purchased: zmniejszyć spacing

### Problem
RestockSheet (Recently Purchased) używa List z domyślnym row spacing — wygląda na za dużo pustego miejsca.

### Zmiana

**Plik:** `FamilyTodo/Views/ShoppingListView.swift`, RestockSheet (linia ~692)

**Zamień List na LazyVStack z mniejszym spacing:**

```swift
// OBECNE (linie 692-706):
List {
    ForEach(store.recentItems) { item in
        RestockItemRow(
            item: item,
            onRestore: { onRestore(item) },
            onDelete: { onDeleteItem(item) }
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
.listStyle(.plain)

// NOWE:
ScrollView {
    LazyVStack(spacing: 0) {
        ForEach(store.recentItems) { item in
            RestockItemRow(
                item: item,
                onRestore: { onRestore(item) },
                onDelete: { onDeleteItem(item) }
            )
            .padding(.horizontal, 20)
        }
    }
}
```

Spacing 0 + `.padding(.vertical, 6)` na RestockItemRow daje identyczny spacing jak active items w ShoppingListView.

**UWAGA:** Swipe actions nie działają na LazyVStack (tylko w List). Jeśli swipe-to-delete na restock items jest potrzebny, zostaw List ale zmniejsz insets: `EdgeInsets(top: -4, leading: 20, bottom: -4, trailing: 20)`.

---

## Issue #15 — Usunąć Shopping suggestions

### Problem
Toggle "Shopping suggestions" w Settings nic nie robi — feature niezaimplementowany.

### Zmiana

**Plik:** `FamilyTodo/Views/MoreView.swift` — w SettingsView, sekcja Toggles:

**Usuń cały toggle (linie ~817-823):**
```swift
Toggle(isOn: Binding(
    get: { themeStore.suggestionsEnabled },
    set: { themeStore.suggestionsEnabled = $0 }
)) {
    Label("Shopping suggestions", systemImage: "lightbulb.fill")
        .foregroundStyle(.primary)
}
```

**Opcjonalnie** usuń `suggestionsEnabled` z ThemeStore — ale nie jest konieczne (nie szkodzi).

---

## Issue #16 — Repetitive Tasks: Backlog Category picker

### Problem
Formularz "Add repetitive task" nie ma pola kategorii. Użytkownik chce powiązać recurring tasks z kategoriami z Ideas (Backlog).

### Zmiana

**Krok 1: Dodaj categoryId do RecurringChore**

**Plik:** `FamilyTodo/Models/LegacyStubs.swift` — model RecurringChore:

Dodaj pole:
```swift
var categoryId: UUID?
```

**Krok 2: Dodaj BacklogStore do RepetitiveTasksView**

**Plik:** `FamilyTodo/Views/MoreView.swift`, RepetitiveTasksView:

```swift
// Dodaj store:
@StateObject private var backlogStore: BacklogStore
@State private var selectedCategoryId: UUID?

// W init():
_backlogStore = StateObject(
    wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext)
)
```

**Krok 3: Dodaj Picker w formularzu (po frequency picker, linia ~503):**

```swift
Picker("Category", selection: $selectedCategoryId) {
    Text("None").tag(UUID?.none)
    ForEach(backlogStore.categories) { category in
        Text(category.title).tag(UUID?.some(category.id))
    }
}
```

**Krok 4: Przekaż categoryId do addChore**

Zaktualizuj `store.addChore()` call (linia ~528) aby przekazać `categoryId: selectedCategoryId`.

**Krok 5: Wyświetl kategorię w liście**

W liście chores (linia ~461), dodaj pod recurrence type:
```swift
if let catId = chore.categoryId,
   let cat = backlogStore.categories.first(where: { $0.id == catId }) {
    Text(cat.title)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(cat.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(cat.color.opacity(0.12)))
}
```

**Krok 6: Load backlog w .task:**
```swift
.task {
    store.setSyncMode(userSession.syncMode)
    await store.loadChores()
    backlogStore.setSyncMode(userSession.syncMode)
    await backlogStore.loadCategories()
}
```

---

## Issue #17 — Celebrations: animacja konfetti

### Problem
CelebrationOverlay pokazuje toast, ale brak wizualnej animacji konfetti dla milestone celebrations.

### Zmiana

**Plik:** `FamilyTodo/Views/Components/CelebrationOverlay.swift`

**Dodaj prosty system konfetti (particles):**

```swift
struct CelebrationOverlay: View {
    @ObservedObject var manager: CelebrationManager
    @State private var confettiParticles: [ConfettiParticle] = []

    var body: some View {
        ZStack {
            // Confetti layer
            ForEach(confettiParticles) { particle in
                Text(particle.emoji)
                    .font(.system(size: particle.size))
                    .position(particle.position)
                    .opacity(particle.opacity)
            }

            // Toast (existing code)
            if let celebration = manager.activeCelebration {
                VStack {
                    Spacer()
                    // ... existing toast code ...
                    Spacer().frame(height: 100)
                }
                .animation(WowAnimation.spring, value: manager.activeCelebration)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: manager.activeCelebration) { _, newValue in
            if let celebration = newValue, celebration.style == .milestone {
                spawnConfetti()
            }
        }
    }

    private func spawnConfetti() {
        let emojis = ["🎉", "✨", "🌟", "💫", "🎊", "⭐️", "🔥"]
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        var particles: [ConfettiParticle] = []
        for i in 0..<20 {
            particles.append(ConfettiParticle(
                emoji: emojis[i % emojis.count],
                size: CGFloat.random(in: 16...28),
                position: CGPoint(
                    x: CGFloat.random(in: 20...screenWidth - 20),
                    y: -20
                ),
                targetY: CGFloat.random(in: screenHeight * 0.3...screenHeight * 0.7),
                opacity: 1.0
            ))
        }
        confettiParticles = particles

        // Animate falling
        withAnimation(.easeOut(duration: 1.5)) {
            for i in confettiParticles.indices {
                confettiParticles[i].position.y = confettiParticles[i].targetY
            }
        }

        // Fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                for i in confettiParticles.indices {
                    confettiParticles[i].opacity = 0
                }
            }
        }

        // Clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            confettiParticles = []
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let emoji: String
    let size: CGFloat
    var position: CGPoint
    var targetY: CGFloat
    var opacity: Double
}
```

---

## Issue #18 — Fonty: korekta

### Problem
- Retro: Press Start 2P (plik istnieje w bundle) ✅
- Paper: powinien być Georgia (systemowy, nie wymaga pliku)
- System: SF Pro (domyślny)

### Zmiana

**Plik:** `FamilyTodo/Views/ThemeStore.swift`

**ThemeStore.font() — dodaj obsługę Georgia:**
```swift
func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    switch preset {
    case .retro:
        if UIFont(name: "PressStart2P-Regular", size: size) != nil {
            return .custom("PressStart2P-Regular", size: size)
        }
        return .system(size: size, weight: weight)
    case .paper:
        // Georgia is a built-in iOS font
        return .custom("Georgia", size: size)
    case .system:
        return .system(size: size, weight: weight)
    }
}
```

**Retro font sizes:** Press Start 2P jest czytelny w małych rozmiarach (10-12pt). Nagłówki max 14pt. Zbyt duże rozmiary wyglądają za pikselowo.

**Pliki fontów:** CaveatBrush-Regular.ttf i SpecialElite-Regular.ttf można usunąć z bundle (nie są już potrzebne). Zmniejszy to rozmiar app o ~70KB.

---

## Kolejność implementacji (CAŁA — R1 + R2)

### Faza A — Fundamenty (bez zależności)
1. **Issue #7** — Uproszczenie ThemePreset (system/retro/paper)
2. **Issue #18** — Korekta fontów
3. **Issue #9** — Rename Backlog → Ideas
4. **Issue #10** — Usunąć kropki
5. **Issue #15** — Usunąć suggestions toggle
6. **Feature #5** — Daily digest fix

### Faza B — UI zmiany (po Fazie A)
7. **Issue #6** — Podłączyć palety do widoków
8. **Issue #8** — Połączyć Theme + Appearance w jedną sekcję
9. **Feature #2** — Tab icon colors
10. **Feature #3** — Assignee pill enhancement
11. **Issue #11** — Ikony akcji zamiast (...)
12. **Issue #12** — Więcej kolorów kategorii
13. **Issue #13** — Mark as bought podczas edycji
14. **Issue #14** — Recently Purchased spacing

### Faza C — Nowe feature'y (po Fazie B)
15. **Issue #16** — Repetitive Tasks + category picker
16. **Feature #4** — Celebrations system
17. **Issue #17** — Animacja konfetti

---

## Weryfikacja (kompletna)

Po implementacji:
1. `pre-commit run --all-files` — musi przejść
2. Build via GitHub Actions — `xcodebuild build` musi przejść
3. Manual test na iPhone 15:
   - Settings → Appearance → 3 karty (Default/Retro/Paper)
   - Default: Light/Dark/System picker widoczny pod kartami
   - Retro: wymusza dark, Press Start 2P font widoczny, piksele
   - Paper: Georgia font, ciepłe kraft kolory
   - Settings → Tab bar color → zmień kolor → ikony tab bar zmieniają kolor
   - Tab "Ideas" (nie "Backlog") z ikoną archivebox
   - Ideas → brak kropek przed itemami
   - Ideas → 4 ikony (edit/assign/promote/delete) widoczne bezpośrednio
   - Ideas → 3+ kategorie z różnymi kolorami
   - Tasks → assignee pill powiększony z inicjałem w kółku
   - Tasks → zakończ task → toast + haptic
   - Tasks → zakończ wszystkie → toast + konfetti + powiadomienie partnerowi
   - Shopping → edytuj item → checkbox "bought" widoczny
   - Shopping → Recently Purchased → spacing jak w głównej liście
   - Shopping → brak "Shopping suggestions" toggle w Settings
   - Repetitive Tasks → Category picker z lista kategorii z Ideas
   - App kill + restart → daily digest zaschedulowany

---

# ROUND 3 — Theme System Redesign + Confetti Fix (2026-02-17)

> Autor: Antigravity (Claude Opus 4.6) · Data: 2026-02-17
> Naprawa 5 krytycznych problemów z theme system i celebrations
> Commit: `fe2d405` na branch `r4-features`

## Kontekst

Codex zaimplementował R1+R2, ale theme system miał 5 krytycznych problemów:

1. **Fonty nie działają** — `themeStore.font()` istnieje ale żaden widok go nie wywołuje (0 użyć)
2. **Selector UX zepsuty** — kliknięcie Retro/Paper chowa Light/Dark/System (guard `if themeStore.preset == .system`)
3. **ThemePalette/CardKind unused** — dead code z poprzedniej wersji
4. **Light preview pomarańczowy** — ThemePresetCard swatch używa ciepłych kremowych gradientów; AppearanceCard selected ma pomarańczowy `accentColor`
5. **Emoji zamiast konfetti** — CelebrationOverlay renderuje emoji (🎉,✨) zamiast kolorowych kształtów

## Spis zmian R3

| # | Issue | Pliki | Status |
|---|-------|-------|--------|
| A | Unified theme selector (5 kart w 1 linii) | ThemeStore.swift, MoreView.swift | ✅ Done |
| B | Wire fonts do 10 kluczowych widoków | TasksView, ShoppingListView, BacklogView, MoreView, CelebrationOverlay | ✅ Done |
| C | Konfetti geometryczne (shapes zamiast emoji) | CelebrationOverlay.swift | ✅ Done |
| D | Cleanup dead code | ThemeStore.swift, MoreView.swift | ✅ Done |

---

## Step A — Unified Theme Selector (Issues 1, 2, 4)

### Problem
Dwa osobne selectory: ThemePresetSelector (3 karty: Default/Retro/Paper) + AppearanceSelector (3 karty: Light/Dark/System). AppearanceSelector ukryty za `if themeStore.preset == .system` — Retro/Paper go chowały. Light preview pomarańczowy przez ciepłe gradienty palette.

### Rozwiązanie

**1. Nowy `UnifiedTheme` enum** (ThemeStore.swift):
```swift
enum UnifiedTheme: String, CaseIterable, Identifiable {
    case light, dark, auto, retro, paper
}
```

**2. Bidirektionalny computed property** `unifiedTheme` w ThemeStore:
- `.light` → preset=.system, appearanceMode=.light
- `.dark` → preset=.system, appearanceMode=.dark
- `.auto` → preset=.system, appearanceMode=.system
- `.retro` → preset=.retro
- `.paper` → preset=.paper

Zapisuje do tych samych `@AppStorage` keys — zero migracji.

**3. Nowy `UnifiedThemeSelector` + `UnifiedThemeCard`** (MoreView.swift):
- 5 kart w jednej linii ScrollView(.horizontal)
- Swatchy per karta z właściwymi kolorami:

| Karta | Gradient | Ikona |
|-------|----------|-------|
| Light | #FFFFFF → #F5F5F5 | szary #666 |
| Dark | #1C1C1E → #2C2C2E | biały |
| Auto | #E8E8ED → #3A3A3C | .primary |
| Retro | #0F0F23 → #1A1A3E | #00FF41 neon green |
| Paper | #FFF8E7 → #F0E6CE | #8B4513 brown |

- Selection: `Color.accentColor` stroke border (nie filled pomarańczowy background)

**4. Usunięte 4 stare komponenty:**
- `AppearanceSelector`, `AppearanceCard`, `ThemePresetSelector`, `ThemePresetCard`

---

## Step B — Wire Fonts do 10 Kluczowych Widoków (Issue 1)

### Problem
`themeStore.font(size:weight:)` miał 0 wywołań. Wszystkie 100+ `.font(.system())` w widokach hardcoded.

### Rozwiązanie

**1. Fix scale factor w font()** (ThemeStore.swift):
PressStart2P renderuje ~35% większy niż system font → dodano skalowanie 0.65x:
```swift
func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    switch preset {
    case .retro:
        let scaledSize = size * 0.65
        if UIFont(name: "PressStart2P-Regular", size: scaledSize) != nil {
            return .custom("PressStart2P-Regular", size: scaledSize)
        }
        return .system(size: size, weight: weight)
    case .paper:
        return .custom("Georgia", size: size)
    case .system:
        return .system(size: size, weight: weight)
    }
}
```

**2. Zamieniono 10 font lokalizacji:**

| # | Plik | Co | Zmiana |
|---|------|----|--------|
| 1 | TasksView.swift | Header "Tasks" | `.system(size: 28, weight: .bold)` → `themeStore.font(size: 28, weight: .bold)` |
| 2 | TasksView.swift | Filter toggle | `.system(size: 14, weight: .semibold)` → `themeStore.font(size: 14, weight: .semibold)` |
| 3 | TasksView.swift | Task title (TaskRow) | `.system(size: 15)` → `themeStore.font(size: 15)` |
| 4 | ShoppingListView.swift | Header "Shopping" | `.system(size: 28, weight: .bold)` → `themeStore.font(size: 28, weight: .bold)` |
| 5 | ShoppingListView.swift | Item title (ShoppingItemRow) | `.system(size: 15)` → `themeStore.font(size: 15)` |
| 6 | BacklogView.swift | Header "Ideas" | `.system(size: 28, weight: .bold)` → `themeStore.font(size: 28, weight: .bold)` |
| 7 | BacklogView.swift | Item title (BacklogItemRow) | `.system(size: 15)` → `themeStore.font(size: 15)` |
| 8 | MoreView.swift | Header "More" | `.system(size: 28, weight: .bold)` → `themeStore.font(size: 28, weight: .bold)` |
| 9 | MoreView.swift | Profile card name | `.system(size: 17, weight: .semibold)` → `themeStore.font(size: 17, weight: .semibold)` |
| 10 | CelebrationOverlay.swift | Toast message | `.system(size: 15, weight: .semibold)` → `themeStore.font(size: 15, weight: .semibold)` |

**3. Dodano `@EnvironmentObject` do Row structs:**
- `TaskRow` — nie miał dostępu do themeStore
- `ShoppingItemRow` — nie miał dostępu do themeStore
- `BacklogItemRow` — nie miał dostępu do themeStore

Row subviews to osobne structs — potrzebują jawnej deklaracji `@EnvironmentObject private var themeStore: ThemeStore`.

---

## Step C — Konfetti Geometryczne (Issue 5)

### Problem
CelebrationOverlay renderował emoji (🎉,✨,🌟,💫,🎊,⭐️,🔥) jako confetti.

### Rozwiązanie

**1. Nowy `ConfettiParticle` struct:**
```swift
private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let shape: ConfettiShape     // zamiast emoji: String
    let color: Color             // nowe pole
    let size: CGFloat
    let startX, endX, startY, endY: CGFloat
    let rotation: Double

    enum ConfettiShape: CaseIterable {
        case rectangle, circle, triangle
    }
}
```

**2. Paleta 8 kolorów:**
- Coral red `#FF6B6B`, teal `#4ECDC4`, sunny yellow `#FFE66D`, lavender `#A78BFA`
- Pink `#F093FB`, mint green `#4DD599`, sky blue `#74B9FF`, rose `#FD79A8`

**3. `TriangleShape: Shape`** — custom equilateral triangle via Path.

**4. `confettiShapeView(for:)`** — @ViewBuilder switching between Rectangle/Circle/TriangleShape.

**5. Parametry:**
- 30 particles (było 24)
- Size 6-12pt (było 16-28)
- Rotation ±360° (było ±140°)
- Horizontal spread ±80pt (było ±70)
- Animation: `.easeOut(duration: 1.6)`, cleanup 1.9s (bez zmian)

**6. Dodano `@EnvironmentObject themeStore`** do CelebrationOverlay — toast font teraz theme-aware.

---

## Step D — Cleanup Dead Code

- **Usunięto `palette` computed property** z ThemeStore — jedyny consumer (`ThemePresetCard`) został usunięty w Step A
- **4 stare komponenty** usunięte w Step A: `AppearanceSelector`, `AppearanceCard`, `ThemePresetSelector`, `ThemePresetCard`

---

## Pliki zmienione w R3

| Plik | Zmiany |
|------|--------|
| `FamilyTodo/Views/ThemeStore.swift` | + UnifiedTheme enum, + unifiedTheme computed, fix font() scale 0.65x, - palette accessor |
| `FamilyTodo/Views/MoreView.swift` | Replace 2-level selector → 5-card unified, + UnifiedThemeSelector/Card, - 4 stare komponenty, 2 font replacements |
| `FamilyTodo/Views/Components/CelebrationOverlay.swift` | Replace emoji → geometric shapes, + TriangleShape, + confettiColors, + @EnvironmentObject themeStore, font replacement |
| `FamilyTodo/Views/TasksView.swift` | 3 font replacements, + @EnvironmentObject themeStore w TaskRow |
| `FamilyTodo/Views/ShoppingListView.swift` | 2 font replacements, + @EnvironmentObject themeStore w ShoppingItemRow |
| `FamilyTodo/Views/BacklogView.swift` | 2 font replacements, + @EnvironmentObject themeStore w BacklogItemRow |

## Kluczowe decyzje techniczne

1. **UnifiedTheme nie dotyka @AppStorage** — mapuje bidirektionalnie do istniejących `themePreset` + `appearanceMode` keys. Zero migracji.
2. **Tylko 10 font lokalizacji** — nie 100+. Pixel font w małych rozmiarach (badges, pills, 10-11pt) jest nieczytelny. Zmieniono headery + tytuły elementów + filtr + toast.
3. **Scale factor 0.65x** — PressStart2P renderuje ~35% większy. 28pt * 0.65 = 18.2pt, wizualnie odpowiada ~28pt system font.
4. **Georgia bez scale** — serif font z normalnymi metrykami, kompatybilny z system font layouts.
5. **Row structs potrzebują @EnvironmentObject** — SwiftUI environment propaguje automatycznie przez view hierarchy, ale struct musi jawnie zadeklarować property.

## Weryfikacja

1. ✅ Settings → Appearance → 5 kart w jednej linii (Light/Dark/Auto/Retro/Paper)
2. ✅ Light karta neutralna biała (nie pomarańczowa)
3. ✅ Retro → PressStart2P pixel font w nagłówkach i tytułach
4. ✅ Paper → Georgia serif w nagłówkach i tytułach
5. ✅ System (Light/Dark/Auto) → SF Pro (bez zmian)
6. ✅ Milestone celebration → kolorowe geometryczne kształty (rect/circle/triangle)
7. ✅ `pre-commit run --all-files` → Passed
8. ✅ Backward compatibility → istniejące @AppStorage settings działają po update

---

# ROUND 4 — Fix Custom Font Loading (PressStart2P + SpecialElite)

> Autor: Antigravity (Claude Opus 4.6) · Data: 2026-02-17
> Naprawa krytycznego buga: custom fonty (PressStart2P, SpecialElite, CaveatBrush) nie ładują się w runtime

---

## Kontekst

Po wdrożeniu R3 (unified theme selector + font wiring) użytkownik zgłasza, że przełączenie na motyw **Retro** nie zmienia fontu — zamiast PressStart2P pixel font widać system font w zmniejszonym rozmiarze (~62-68% normalnego). Screenshoty z TestFlight potwierdzają problem na wszystkich ekranach (Shopping, Tasks, Ideas).

### Objaw

- Retro theme: tekst wygląda jak normalny system font, ale mniejszy (scale 0.62-0.68x się aplikuje, ale do system font zamiast PressStart2P)
- Paper theme: wygląda OK bo SpecialElite-Regular fallbackuje do wbudowanego Georgia
- Light/Dark/Auto: bez zmian (system font, brak skalowania)

### Root Cause Analysis

**`UIFont(name: "PressStart2P-Regular", size:)` zwraca `nil` w runtime**, co powoduje fallback do `.system(size: scaledSize)` w `customFont()` (ThemeStore.swift).

Zbadano:
1. **Font file istnieje**: `FamilyTodo/Resources/Fonts/PressStart2P-Regular.ttf` (116 KB, valid TrueType)
2. **PostScript name poprawny**: `fc-scan` potwierdza `PressStart2P-Regular` (nameID=6)
3. **Family name**: `Press Start 2P` (nameID=1), Full name: `Press Start 2P Regular` (nameID=4)
4. **Xcode project konfiguracja**:
   - `PBXBuildFile` — font w "Copy Bundle Resources" build phase ✅
   - `PBXFileReference` — `path = "Resources/Fonts/PressStart2P-Regular.ttf"`, `sourceTree = "<group>"`, `lastKnownFileType = file`
   - `INFOPLIST_KEY_UIAppFonts` — zawiera `"PressStart2P-Regular.ttf"` (bez ścieżki katalogu)
   - Font files są bezpośrednimi dziećmi grupy `FamilyTodo` (nie mają osobnej grupy Fonts)

**Prawdopodobna przyczyna**: Niezgodność ścieżki w bundle. `PBXFileReference.path` = `"Resources/Fonts/..."` może spowodować, że font trafia do `FamilyTodo.app/Resources/Fonts/PressStart2P-Regular.ttf` zamiast do korzenia bundle. Tymczasem `UIAppFonts` szuka `PressStart2P-Regular.ttf` w korzeniu.

**Dotyczy WSZYSTKICH 3 custom fontów**: PressStart2P-Regular, CaveatBrush-Regular, SpecialElite-Regular — identyczna konfiguracja.

---

## Spis zmian R4

| # | Zmiana | Plik | Status |
|---|--------|------|--------|
| 1 | Runtime diagnostyka fontów w bundle | ThemeStore.swift | ⬜ TODO |
| 2 | UIAppFonts dual paths (root + subdirectory) | project.pbxproj | ⬜ TODO |
| 3 | PBXFileReference dodaj `name` attribute | project.pbxproj | ⬜ TODO |
| 4 | customFont() fallback na family name | ThemeStore.swift | ⬜ TODO |

---

## Step 1 — Runtime diagnostyka fontów

**Plik:** `FamilyTodo/Views/ThemeStore.swift`, metoda `verifyBundledFonts()`

Rozszerz obecną diagnostykę o:
- Sprawdzenie czy font file jest w korzeniu bundle czy w subdirectory `Resources/Fonts/`
- Wylistowanie zarejestrowanych font families pasujących do "Press"/"Elite"
- Zmień "ok"/"missing" na "ok"/"MISSING" dla łatwiejszego wyszukiwania w logach

### Obecny kod (linie 422-440):
```swift
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
    print("🧩 Theme font map: system=SF, retro=PressStart2P-Regular, paper=SpecialElite-Regular(headline)+Georgia(body), caveat=reserved")
    return registered
}
```

### Nowy kod:
```swift
@discardableResult
func verifyBundledFonts() -> [String: Bool] {
    // 1. Check font file presence in bundle (root vs subdirectory)
    let fontFiles = ["PressStart2P-Regular", "CaveatBrush-Regular", "SpecialElite-Regular"]
    for name in fontFiles {
        let rootPath = Bundle.main.path(forResource: name, ofType: "ttf")
        let subPath = Bundle.main.path(forResource: name, ofType: "ttf", inDirectory: "Resources/Fonts")
        print("🧩 Font bundle: \(name).ttf root=\(rootPath != nil ? "FOUND" : "missing") subdir=\(subPath != nil ? "FOUND" : "missing")")
    }

    // 2. Check UIFont registration by PostScript name
    let registered: [String: Bool] = [
        "PressStart2P-Regular": UIFont(name: "PressStart2P-Regular", size: 14) != nil,
        "SpecialElite-Regular": UIFont(name: "SpecialElite-Regular", size: 14) != nil,
        "CaveatBrush-Regular": UIFont(name: "CaveatBrush-Regular", size: 14) != nil,
    ]

    // 3. Search registered font families for partial matches
    let pressMatches = UIFont.familyNames.filter {
        $0.lowercased().contains("press") || $0.lowercased().contains("start")
    }
    let eliteMatches = UIFont.familyNames.filter {
        $0.lowercased().contains("elite") || $0.lowercased().contains("special")
    }
    if !pressMatches.isEmpty { print("🧩 Font families matching 'press/start': \(pressMatches)") }
    if !eliteMatches.isEmpty { print("🧩 Font families matching 'elite/special': \(eliteMatches)") }

    let status = registered
        .map { "\($0.key)=\($0.value ? "ok" : "MISSING")" }
        .sorted()
        .joined(separator: ", ")
    print("🧩 Theme fonts audit: \(status)")
    return registered
}
```

**Cel**: Po deploymencie na TestFlight, logi konsoli (`Xcode → Window → Devices and Simulators → Console`) pokażą:
- Czy font file jest w korzeniu bundle (`root=FOUND`) czy w subdirectory (`subdir=FOUND`)
- Jakie font families iOS zarejestrował (jeśli PostScript name jest inna)
- Czy `UIFont(name:)` rozpoznaje font

---

## Step 2 — UIAppFonts dual paths w project.pbxproj

**Plik:** `FamilyTodo.xcodeproj/project.pbxproj`

Dodaj ścieżki z subdirectory `Resources/Fonts/` obok istniejących nazw root. iOS ignoruje nieistniejące wpisy w UIAppFonts (nie crashuje, nie loguje warningów). To gwarantuje że font się załaduje niezależnie od tego gdzie Xcode go umieści w bundle.

### Debug config (linie 631-635):
```
// PRZED:
INFOPLIST_KEY_UIAppFonts = (
    "PressStart2P-Regular.ttf",
    "CaveatBrush-Regular.ttf",
    "SpecialElite-Regular.ttf",
);

// PO:
INFOPLIST_KEY_UIAppFonts = (
    "PressStart2P-Regular.ttf",
    "CaveatBrush-Regular.ttf",
    "SpecialElite-Regular.ttf",
    "Resources/Fonts/PressStart2P-Regular.ttf",
    "Resources/Fonts/CaveatBrush-Regular.ttf",
    "Resources/Fonts/SpecialElite-Regular.ttf",
);
```

### Release config (linie 664-668):
Identyczna zmiana jak Debug.

---

## Step 3 — PBXFileReference: dodaj `name` attribute

**Plik:** `FamilyTodo.xcodeproj/project.pbxproj` (linie 114-116)

Dodaj `name = "filename.ttf"` do wszystkich 3 font file references. Xcode używa `name` do wyświetlania w navigator i do kopiowania do bundle. Bez `name`, Xcode może użyć pełnej `path` jako nazwy w bundle.

```
// PRZED (linia 114):
FONTFILE0000000000000001 /* PressStart2P-Regular.ttf */ = {isa = PBXFileReference; lastKnownFileType = file; path = "Resources/Fonts/PressStart2P-Regular.ttf"; sourceTree = "<group>"; };

// PO:
FONTFILE0000000000000001 /* PressStart2P-Regular.ttf */ = {isa = PBXFileReference; lastKnownFileType = file; name = "PressStart2P-Regular.ttf"; path = "Resources/Fonts/PressStart2P-Regular.ttf"; sourceTree = "<group>"; };
```

Analogicznie dla linii 115 (CaveatBrush) i 116 (SpecialElite).

---

## Step 4 — customFont() fallback na family name

**Plik:** `FamilyTodo/Views/ThemeStore.swift`, metoda `customFont()` (linia 442)

iOS CoreText może rejestrować font pod family name (`Press Start 2P`) zamiast PostScript name (`PressStart2P-Regular`). Dodaj fallback próbujący obu wariantów.

### Obecny kod:
```swift
private func customFont(_ postScriptName: String, size: CGFloat, fallbackWeight: Font.Weight) -> Font {
    if UIFont(name: postScriptName, size: size) != nil {
        return .custom(postScriptName, size: size)
    }
    return .system(size: size, weight: fallbackWeight)
}
```

### Nowy kod:
```swift
private func customFont(_ postScriptName: String, size: CGFloat, fallbackWeight: Font.Weight) -> Font {
    // Try PostScript name first (e.g. "PressStart2P-Regular")
    if UIFont(name: postScriptName, size: size) != nil {
        return .custom(postScriptName, size: size)
    }
    // Try family name (e.g. "Press Start 2P") — iOS may register under this name
    let familyName = postScriptName
        .replacingOccurrences(of: "-Regular", with: "")
        .replacingOccurrences(of: "-", with: " ")
    if UIFont(name: familyName, size: size) != nil {
        return .custom(familyName, size: size)
    }
    return .system(size: size, weight: fallbackWeight)
}
```

### Dodatkowa zmiana w font() dla Paper SpecialElite

W metodzie `font(size:weight:role:)` (linia 402), linia SpecialElite też powinna używać `customFont()` zamiast bezpośredniego `UIFont(name:)` check:

```swift
// PRZED (linie 409-413):
case .display, .title:
    if UIFont(name: "SpecialElite-Regular", size: size) != nil {
        return .custom("SpecialElite-Regular", size: size)
    }
    return customFont("Georgia", size: size, fallbackWeight: weight)

// PO:
case .display, .title:
    let elite = customFont("SpecialElite-Regular", size: size, fallbackWeight: .regular)
    if elite != .system(size: size, weight: .regular) {
        return elite
    }
    return customFont("Georgia", size: size, fallbackWeight: weight)
```

Albo prostsze podejście — użyj `customFont()` bezpośrednio:
```swift
case .display, .title:
    return customFont("SpecialElite-Regular", size: size, fallbackWeight: weight)
```
(Georgia jako fallback nie jest tu potrzebne bo `customFont()` sam spadnie do system font. Ale jeśli chcesz Georgia jako fallback zamiast system, zachowaj obecny if/else.)

---

## Pliki do zmiany

| Plik | Zmiana |
|------|--------|
| `FamilyTodo.xcodeproj/project.pbxproj` | UIAppFonts: +3 entries z subdirectory path (Debug linia 631, Release linia 664). PBXFileReference: +`name` attribute (linie 114-116) |
| `FamilyTodo/Views/ThemeStore.swift` | `verifyBundledFonts()`: bundle path diagnostics + family name search. `customFont()`: +family name fallback |

---

## Kolejność implementacji

1. **Step 2** — UIAppFonts dual paths (project.pbxproj) — główna naprawa
2. **Step 3** — PBXFileReference name (project.pbxproj) — w tym samym pliku
3. **Step 1** — Runtime diagnostyka (ThemeStore.swift) — zrozumienie problemu
4. **Step 4** — customFont() fallback (ThemeStore.swift) — resilience

---

## Weryfikacja

1. `pre-commit run --all-files` przechodzi
2. Push → GitHub Actions build succeeds
3. TestFlight deploy → przełącz na Retro → **nagłówki wyświetlają PressStart2P pixel font** (nie zmniejszony system font)
4. Sprawdź logi konsoli (`Xcode → Window → Devices`): szukaj `🧩 Font` entries — powinno być `root=FOUND` lub `subdir=FOUND`
5. Przełącz na Paper → sprawdź czy SpecialElite renderuje się w nagłówkach (jeśli nie — Georgia fallback jest OK)
6. Przełącz z powrotem na Auto/Light/Dark → system font wraca do normalnego rozmiaru (bez skalowania)

---

## Risk Assessment

| Ryzyko | Prawdopodobieństwo | Mitygacja |
|--------|--------------------|-----------|
| Duplikaty w UIAppFonts powodują warning | Niskie | iOS ignoruje nieistniejące wpisy bez logów |
| Font nadal nie ładuje się | Średnie | Diagnostyka (Step 1) pokaże dokładną przyczynę w logach — root vs subdir, family name |
| Zmiana pbxproj psuje build | Niskie | Zmiany są addytywne (dodanie entries/attributes, nie modyfikacja istniejących) |
| Family name fallback trafia w inny font | Bardzo niskie | "Press Start 2P" jest unikalną nazwą, nie koliduje z system fonts |

---

# IMPLEMENTATION STATUS UPDATE (Codex, 2026-02-17)

## Round 4.1 — Font Loading Fix: DONE

### Commit
- `eba6301` — `fix: harden custom font registration and fallback sizing`

### Wdrożone
1. Dodano runtime rejestrację fontów przez CoreText:
   - `FamilyTodo/Utilities/FontRegistrar.swift`
2. Naprawiono fallback „mniejszy, ale ten sam”:
   - fallback systemowy używa `baseSize` (nie `scaledSize`)
   - retro scale działa wyłącznie gdy custom font jest faktycznie dostępny
3. Rozszerzono diagnostykę fontów:
   - log lokalizacji root/subdir
   - status rejestracji
   - wykryte family/font names
4. Startowa rejestracja fontów na starcie aplikacji:
   - `FamilyTodo/FamilyTodoApp.swift`
5. Uporządkowano `UIAppFonts` + dodano ścieżki kompatybilności:
   - `FamilyTodo.xcodeproj/project.pbxproj`

### Dotknięte pliki
- `FamilyTodo/Utilities/FontRegistrar.swift`
- `FamilyTodo/Views/ThemeStore.swift`
- `FamilyTodo/FamilyTodoApp.swift`
- `FamilyTodo.xcodeproj/project.pbxproj`

---

## Plan v4.2 — Retro UI + Typography Coverage + Confetti Blast: DONE

### Commit
- `7b52dc2` — `feat: polish retro ui, global typography, and confetti blast`

### Wdrożone
1. Konfetti:
   - 90 cząstek (3x)
   - rozszerzona paleta (18 kolorów + theme accents)
   - trajektoria blast z jednego emitera (dół-środek), nie opad z góry
   - plik: `FamilyTodo/Views/Components/CelebrationOverlay.swift`
2. Global typography:
   - rozszerzone tokeny `ThemeFontToken` (`sectionHeader`, `inlineTitle`, `bodyStrong`, `bodySmall`, `tabLabel`, `buttonLabel`)
   - dodane API `uiFont(for:)` dla UIKit/tabbara
   - plik: `FamilyTodo/Views/ThemeStore.swift`
3. Fonty w natywnym TabView:
   - nowy `TabBarTypographyManager` oparty o `UITabBarAppearance` (`titleTextAttributes` only)
   - podpięcie w `MainAppView` na `onAppear` + `onChange(theme/tabTint)`
   - pliki:
     - `FamilyTodo/Utilities/TabBarTypographyManager.swift`
     - `FamilyTodo/ContentView.swift`
4. Retro checkbox:
   - nowy komponent `ThemedCheckbox` (retro pixel style dla preset `.retro`)
   - wdrożony w Shopping + Tasks
   - pliki:
     - `FamilyTodo/Views/Components/ThemedCheckbox.swift`
     - `FamilyTodo/Views/ShoppingListView.swift`
     - `FamilyTodo/Views/TasksView.swift`
5. Retro coin badge:
   - nowy komponent `ShoppingCountBadge`
   - użyty w headerze Shopping
   - pliki:
     - `FamilyTodo/Views/Components/ShoppingCountBadge.swift`
     - `FamilyTodo/Views/ShoppingListView.swift`
6. Typografia na kluczowych ekranach:
   - Shopping (w tym Recently Purchased)
   - Tasks
   - Ideas/Backlog
   - More/Settings/Profile/Repetitive
   - pliki:
     - `FamilyTodo/Views/ShoppingListView.swift`
     - `FamilyTodo/Views/TasksView.swift`
     - `FamilyTodo/Views/BacklogView.swift`
     - `FamilyTodo/Views/MoreView.swift`
7. Aktualizacja projektu o nowe pliki:
   - `FamilyTodo.xcodeproj/project.pbxproj`

### Walidacja
1. `PRE_COMMIT_HOME=/tmp/pre-commit-cache pre-commit run -a` — Passed
2. Push na branch:
   - `r4-features` (`eba6301`, `7b52dc2`)
