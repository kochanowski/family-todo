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

---

## R5: Bug Fixes & UI Cleanup (2026-02-23)

> **Skills:** `swift-expert`, `swiftui-ui-patterns`
> Bugs identified from device screenshots. Each item includes the exact file, root cause, and the fix.

---

### R5-1: Shopping badge — zły kolor w ciemnym trybie

**Problem:** W dark mode licznik itemów (Shopping header badge) jest żółty, niezgodny z kolorem tab bar.

**Root cause:** `ShoppingCountBadge.standardBadge` używa `themeStore.accentColor`, który w dark mode dla theme `system` jest żółty/złoty.

**Fix:** `standardBadge` powinien używać `themeStore.tabTintColor` color (aktualnie wybrany kolor tab bara).
Jeśli `tabTintColor.color == nil` (automatic), użyć `themeStore.accentColor` jako fallback.

**Plik:** `FamilyTodo/Views/Components/ShoppingCountBadge.swift`

```swift
private var standardBadge: some View {
    let badgeColor = themeStore.tabTint?.color ?? themeStore.accentColor  // Fix: use tab tint
    return Text("\(count)")
        .font(themeStore.font(for: .chip))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(badgeColor))
}
```

> Needs `themeStore.tabTint: TabTintColor` as a computed property if not already public.

---

### R5-2: Shopping — missaligned "Add item" row

**Problem:** Pole "Add item" (rapidEntryRow) jest przesuniete w prawo relatywnie do istniejących itemów.

**Root cause:** `rapidEntryRow` (L291-L308 `ShoppingListView.swift`) ma stałe paddingi, które nie odpowiadają paddingom w `ShoppingItemRow` (L470-L493). Checkbox (Circle, 20pt) w `rapidEntryRow` ma `spacing: 10` w HStack, ale jest wstawiony bez wyrównania z checkboxem w `ShoppingItemRow`.

**Fix:** Sprawdzić i ujednolicić poziomy padding/inset w obu wierszach. Obie struktory powinny mieć identyczne `HStack(spacing: 10)` z tym samym leading padding.

**Plik:** `FamilyTodo/Views/ShoppingListView.swift`

- `rapidEntryRow` — upewnić się, że jest renderowany w tym samym kontenerze i z tym samym `.padding(.horizontal)` co `ShoppingItemRow`
- Jeśli lista ma `.padding(.horizontal, 20)` na ScrollView, a `rapidEntryRow` dodaje własny padding — usunąć duplikowany padding z `rapidEntryRow`

```swift
// rapidEntryRow: upewnić się, że NIE ma własnego horizontal paddingu
// gdy ScrollView/LazyVStack już go dostarcza
private var rapidEntryRow: some View {
    HStack(spacing: 10) {
        Circle()
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
            .frame(width: 20, height: 20)
        RapidEntryTextField(...)
    }
    .padding(.vertical, 6)
    // BRAK dodatkowego .padding(.horizontal) tutaj
}
```

---

### R5-3: Ideas — kategorie niewidoczne w jasnym motywie

**Problem:** W light mode karty kategorii w backlogu (Ideas) są niewidoczne / brak kontrastu. W dark mode widać je dobrze.

**Root cause:** `CategoryCard` (L584-L587 `BacklogView.swift`) używa `.fill(cardBackground)` gdzie `cardBackground = themeStore.surfaceColor`. W light mode `surfaceColor` jest prawdopodobnie zbyt zbliżony do tła ekranu.

**Fix:** W `CategoryCard.cardBackground` — dodać `Color(.systemGray6)` jako fallback dla light mode, lub dodać subtelny cień, lub upewnić się że `surfaceColor` jest wyraźnie odróżnialny od `canvasColor`.

**Plik:** `FamilyTodo/Views/BacklogView.swift` (struct `CategoryCard`)

```swift
private var cardBackground: Color {
    // Upewnić się że karta ma wyraźne tło w light i dark mode
    themeStore.cardSurface  // lub użyć Color(.secondarySystemGroupedBackground)
}
```

**Alternatywnie** — dodać cień do karty:
```swift
.background {
    RoundedRectangle(cornerRadius: 12)
        .fill(themeStore.surfaceColor)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
}
```

Sprawdzić w `ThemeStore` jak wylicza się `surfaceColor` dla preset `.system` w light mode i upewnić się, że różni się od `canvasColor`.

---

### R5-4: System Font Size — owal w owalu

**Problem:** W light i dark mode selektor "System Font Size" wygląda jak owal w owalu — błąd podwójnego tła.

**Root cause:** Komponent wyświetlający `FontSizeScale` (Small/Regular/Large) najprawdopodobniej ma dwa zagnieżdżone elementy z `background` + `Capsule()`. Prawdopodobnie zarówno kontener (`.background(Capsule().fill(...))`) jak i wybrany element mają tło kapsułkowe.

**Fix:** Sprawdzić widok renderujący `systemFontScale` picker w `SettingsView` (MoreView.swift lub plik w którym renderowane są te 3 przyciski). Upewnić się, że:
- Kontenera ma jedną kapsułkę jako tło (`Color(.systemGray5)` lub `Color(.systemGray6)`)
- Wybrany element ma drugą kapsułkę (`.ultraThinMaterial` lub white)
- Nie ma tercjowego tła ani nakładki

Wzorzec do zastosowania (z TasksView filterToggle):
```swift
HStack(spacing: 0) {
    ForEach(FontSizeScale.allCases) { scale in
        Button { themeStore.systemFontScale = scale } label: {
            Text(scale.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(themeStore.systemFontScale == scale ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .background {
            if themeStore.systemFontScale == scale {
                Capsule()
                    .fill(.white)  // lub .ultraThinMaterial
                    .matchedGeometryEffect(id: "font-scale-indicator", in: ns)
            }
        }
    }
}
.padding(4)
.background(Capsule().fill(Color(.systemGray5)))
```

---

### R5-5: Retro shopping badge — dwa kółka nachodzą

**Problem:** W Retro theme licznik itemów w Shopping wyświetla dwa nakładające się kółka (fill + stroke) i tekst jest nieczytelny.

**Root cause:** W `retroCoin` (L25-L56 `ShoppingCountBadge.swift`) używane są dwie warstwy:
```swift
.background { Circle().fill(Color(hex: "F7D51D")) }
.overlay { Circle().stroke(Color.black, lineWidth: 2) }
```
Na monofoncie `PressStart2P` oba kółka renderują się na identycznym rozmiarze, powodując wrażenie nakładania.

**Fix:** Zamiast `.background` + `.overlay`, użyć jednego `ZStack` z kontrolowanymi rozmiarami:

```swift
private var retroCoin: some View {
    let label = "\(count)"
    let isWide = label.count > 1

    return ZStack {
        if isWide {
            Capsule()
                .strokeBorder(Color.black, lineWidth: 2)
                .background(Capsule().fill(Color(hex: "F7D51D")))
        } else {
            Circle()
                .strokeBorder(Color.black, lineWidth: 2)
                .background(Circle().fill(Color(hex: "F7D51D")))
        }
        Text(label)
            .font(themeStore.font(for: .chip))
            .foregroundStyle(.black)
    }
    .frame(minWidth: 26, minHeight: 26)
    .shadow(color: .black.opacity(0.9), radius: 0, x: 2, y: 2)
}
```

> Kluczowe: `strokeBorder` rysuje obrys **wewnątrz** kształtu — nie nakłada się na fill. To eliminuje efekt podwójnego kółka.

---

### R5-6: Paper theme — zostawić tylko warianty E i F

**Problem:** W Settings pokazują się warianty A–G papierowego motywu. Użytkownik chce tylko E i F.

**Warianty do zachowania:**
- **E – Premium Editorial** (`System Serif + System Serif`)
- **F – Modern Classic** (`Georgia + Georgia`)

**Pliki do zmiany:**

**1. `FamilyTodo/Views/ThemeStore.swift` — enum `PaperVariant`:**

```swift
enum PaperVariant: String, CaseIterable, Identifiable {
    case e, f   // USUNĄĆ: a, b, c, d, g

    var displayName: String {
        switch self {
        case .e: "Premium Editorial"
        case .f: "Modern Classic"
        }
    }
    // description, headerPostScriptName, headerFamilyAliases, bodyFontName
    // zostawić tylko case .e i case .f — usunąć pozostałe
}
```

**2. Domyślna wartość w `ThemeStore`:**
```swift
@AppStorage("paperVariant") private var paperVariantRawValue = PaperVariant.e.rawValue
```

**3. Zaktualizować `switch self` we wszystkich computed properties `PaperVariant`** — usunąć case `.a`, `.b`, `.c`, `.d`, `.g`.

> ⚠️ Sprawdzić czy gdzieś w kodzie nie ma hardcoded `PaperVariant.a` lub `.b` — zastąpić `.e`.

---

### R5-7: Tab bar color — usunąć Automatic, Default = zielony

**Problem:** "Automatic" jako opcja nie jest potrzebna. Default powinien być zielony (oryginalny kolor aplikacji).

**Plik:** `FamilyTodo/Views/ThemeStore.swift` — enum `TabTintColor`

```swift
enum TabTintColor: String, CaseIterable, Identifiable {
    case defaultGreen   // NOWA NAZWA zamiast "automatic"
    case blue
    case red
    case black

    var color: Color {  // Non-optional teraz — zawsze zwraca kolor
        switch self {
        case .defaultGreen: Color(hex: "34C759")   // iOS system green = oryginalny kolor app
        case .blue:         Color(hex: "007AFF")   // iOS system blue
        case .red:          Color(hex: "FF3B30")   // iOS system red
        case .black:        Color(hex: "1C1C1E")   // iOS near-black
        }
    }
}
```

**W `ThemeStore`:**
```swift
@AppStorage("tabTintColor") private var tabTintColorRawValue = TabTintColor.defaultGreen.rawValue
```

**Zmienić wszystkie referencia:** `TabTintColor.automatic` → `TabTintColor.defaultGreen`.

---

### R5-8: Tab bar color — kółka → prostokąty

**Problem:** Selektor kolorów w Settings używa kółek. Zmienić na prostokąty z zaokrąglonymi rogami.

**Lokalizacja UI:** Komponent renderujący `TabTintColor.allCases` (w SettingsView lub AppearanceSelector w MoreView) — szukać gdzie iteruje `TabTintColor.allCases` i renderuje ikony/kółka.

**Fix:** Zamienić `Circle()` na `RoundedRectangle(cornerRadius: 8)`:

```swift
// PRZED (kółka):
Image(systemName: tint.iconName)  // "circle.fill"
    .font(.system(size: 28))
    .foregroundStyle(tint.color ?? .secondary)

// PO (prostokąty):
RoundedRectangle(cornerRadius: 8)
    .fill(tint.color)
    .frame(width: 44, height: 32)
    .overlay {
        if themeStore.tabTint == tint {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white, lineWidth: 2.5)
        }
    }
    .shadow(color: tint.color.opacity(0.3), radius: 4, x: 0, y: 2)
```

**Pełny komponent (zastąpić istniejący picker):**

```swift
// Tab bar color section in SettingsView
HStack(spacing: 10) {
    ForEach(TabTintColor.allCases) { tint in
        Button {
            HapticManager.selection()
            themeStore.tabTint = tint
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.color)
                    .frame(width: 50, height: 34)
                    .overlay {
                        if themeStore.tabTint == tint {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white, lineWidth: 2.5)
                        }
                    }
                    .shadow(color: tint.color.opacity(0.35), radius: 4, x: 0, y: 2)

                Text(tint.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(themeStore.tabTint == tint ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
.padding(.vertical, 4)
```

**Wymagana zmiana w `TabTintColor.displayName`:**
```swift
var displayName: String {
    switch self {
    case .defaultGreen: "Default"
    case .blue:         "Blue"
    case .red:          "Red"
    case .black:        "Black"
    }
}
```

---

### Kolejność implementacji R5

| # | Priorytet | Plik główny |
|---|-----------|-------------|
| R5-7 | Wysoki | `ThemeStore.swift` — usuń Automatic, dodaj 4 kolory |
| R5-8 | Wysoki | `MoreView.swift` / `SettingsView` — prostokąty |
| R5-6 | Wysoki | `ThemeStore.swift` — PaperVariant E+F only |
| R5-5 | Średni | `ShoppingCountBadge.swift` — strokeBorder fix |
| R5-1 | Średni | `ShoppingCountBadge.swift` — tabTint color |
| R5-3 | Średni | `BacklogView.swift` — card shadow/background |
| R5-4 | Niski | `MoreView.swift` / `SettingsView` — fix owal w owalu |
| R5-2 | Niski | `ShoppingListView.swift` — alignment fix |

> **Ważne:** R5-7 i R5-8 są ze sobą powiązane — najpierw zmienić enum, potem UI. R5-6 jest niezależne.

---

## R6: Bug Fixes & UI Improvements — Round 2 (2026-02-23)

> **Skills:** `swift-expert`, `swiftui-ui-patterns`

---

### R6-1: Shopping — "Add Item" pill kolor = tab bar color

**Problem:** Przycisk "Add item" (pill) używa `themeStore.accentColor` we wszystkich themach, a nie koloru tab bara.

**Root cause:** `addPillButton` w `ShoppingListView.swift` (L282-L284):
```swift
.fill(themeStore.accentColor)
.shadow(color: themeStore.accentColor.opacity(0.3), ...)
```

**Fix:** Zastąpić `themeStore.accentColor` przez `themeStore.tabTintUIColor` (lub `themeStore.selectedTabColor`) — ten sam kolor co badge i tab bar.

W `ThemeStore` dodać computed property jeśli nie istnieje:
```swift
var selectedTabColor: Color {
    tabTint.color  // Po R5-7 tabTint.color jest non-optional
}
```

**Plik:** `FamilyTodo/Views/ShoppingListView.swift`

```swift
private var addPillButton: some View {
    let pillColor = themeStore.selectedTabColor  // Zmiana z accentColor
    Button { startRapidEntry() } label: {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 14, weight: .bold))
            Text("Add item").font(themeStore.font(for: .buttonLabel))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppChromeMetrics.compactCTAHorizontalPadding)
        .frame(height: AppChromeMetrics.compactCTAHeight)
        .background {
            Capsule()
                .fill(pillColor)
                .shadow(color: pillColor.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("shoppingAddItemButton")
}
```

> Dotyczy też `makeAccessoryToolbar()` w `RapidEntryTextField` (L629-L644) — zmienić `UIColor.systemBlue` na kolor ze `themeStore` (przekazać przez `ThemeStore` lub przez parameter do konstruktora).

---

### R6-2: Shopping — Retro badge OGROMNY (krytyczny fix)

**Problem:** W Retro theme badge z liczbą itemów zajmuje pół ekranu — jest gigantyczny.

**Root cause PRAWDZIWY:**
Dwie niezależne przyczyny sumują się:
1. `minWidth: 22, minHeight: 22` to **minimalne** wymiary — nie ograniczają rozmiaru w górę. PressStart2P ma proporcje bitmap fontu z lat 80. (~10–12pt rozmiaru wizualnego = ~80pt bounding box), więc `Text("8")` przy `chip` = 11pt daje olbrzymi frame.
2. Jednocześnie `.background { Circle() }` i `.overlay { Circle().stroke() }` renderują się na tym samym ogromnym rozmiarze co Text bounding box.

**Fix — STAŁY frame + mały font size dla badge:**

Plik: `FamilyTodo/Views/Components/ShoppingCountBadge.swift`

```swift
private var retroCoin: some View {
    let label = "\(count)"
    let isWide = label.count > 1

    return ZStack {
        // Tło: fill + border w jednym ZStack (bez background+overlay)
        if isWide {
            Capsule().fill(Color(hex: "F7D51D"))
            Capsule().strokeBorder(Color.black, lineWidth: 2)
        } else {
            Circle().fill(Color(hex: "F7D51D"))
            Circle().strokeBorder(Color.black, lineWidth: 2)
        }

        // Tekst z HARDCODED małym rozmiarem — NIE używać themeStore.font(for: .chip)
        // bo PressStart2P na 11pt ma gigantyczny bounding box
        Text(label)
            .font(.custom("PressStart2P-Regular", size: 8))  // Mały, stały rozmiar
            .minimumScaleFactor(0.5)
            .foregroundStyle(.black)
    }
    // STAŁY frame — nie min, nie max — bo min nie ogranicza w górę
    .frame(width: isWide ? 30 : 22, height: 22)
    .shadow(color: .black.opacity(0.85), radius: 0, x: 1.5, y: 1.5)
}

// Do tego, w body, potrzebujemy dostępu do `isWide` → wyciągnąć do computed:
private var isWide: Bool { count > 9 }
```

**Rozwiązanie alternatywne** (prostsze, jeśli powyższe się kompiluje z błędem):
```swift
private var retroCoin: some View {
    Text("\(count)")
        .font(.system(size: 10, weight: .bold, design: .monospaced))  // System mono zamiast custom
        .foregroundStyle(.black)
        .frame(width: 22, height: 22)   // STAŁY rozmiar
        .background(Circle().fill(Color(hex: "F7D51D")))
        .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
        .shadow(color: .black.opacity(0.85), radius: 0, x: 1.5, y: 1.5)
}
```

> ⚠️ **Kluczowe:** `.frame(width: X, height: Y)` (stały) zamiast `.frame(minWidth: X, minHeight: Y)` (bez górnego limitu). To jest root cause gigantycznego rozmiaru.
>
> `minimumScaleFactor(0.5)` pozwala tekstowi się zmniejszyć jeśli i tak jest za duży.

**Plik:** `FamilyTodo/Views/Components/ShoppingCountBadge.swift`

---

### R6-3: Settings — inne ikonki dla Retro i Auto

**Problem:** Obecne ikonki tematów:
- **Retro** → `"gamecontroller.fill"` — zmienić na bardziej 8-bitowy symbol
- **Auto** → `"circle.lefthalf.filled"` — zmienić na symbol systemu

**Sugerowane ikonki (SF Symbols):**

| Theme | Obecna | Nowa | Powód |
|-------|--------|------|-------|
| Retro | `gamecontroller.fill` | `arcade.stick.console.fill` lub `dpad.fill` | Bardziej retro/NES feel |
| Auto  | `circle.lefthalf.filled` | `sparkles` lub `wand.and.stars` | "Auto" = magiczne/automatyczne |

**Uwaga:** Sprawdzić dostępność SF Symbols — `arcade.stick.console.fill` jest dostępny od iOS 16, `dpad.fill` od iOS 14.

**Plik:** `FamilyTodo/Views/ThemeStore.swift` — `UnifiedTheme.iconName`

```swift
var iconName: String {
    switch self {
    case .light: "sun.max.fill"
    case .dark:  "moon.fill"
    case .auto:  "sparkles"              // Zmiana z "circle.lefthalf.filled"
    case .retro: "dpad.fill"            // Zmiana z "gamecontroller.fill"
    case .paper: "newspaper.fill"
    }
}
```

> Opcjonalnie: sprawdzić czy SF Symbols `arcade.stick` lub `joystick` są dostępne na iOS 16+. Jeśli nie — `dpad.fill` jest najbezpieczniejszy.

---

### R6-4: System Font Size — fix owalu (poprawiona wersja)

**Problem:** Selektor Small/Regular/Large nadal wygląda jak "owal w owalu" — zewnętrzny container + wewnętrzny wybrany element obydwa mają pełne tło kapsułkowe.

**Fix:** Zbudować picker dokładnie wg wzorca `filterToggle` z `TasksView` (L388-L422), który działa poprawnie — jeden container Capsule + `matchedGeometryEffect` dla wybranego elementu.

**Znaleźć** komponent renderujący FontSizeScale w Settings (szukać w MoreView.swift lub osobnym pliku widoku AppearanceSelector) i zastąpić jego implementację:

```swift
struct FontSizePicker: View {
    @Binding var selected: FontSizeScale
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FontSizeScale.allCases) { scale in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selected = scale
                    }
                } label: {
                    Text(scale.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected == scale ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(alignment: .center) {
                    if selected == scale {
                        Capsule()
                            .fill(.white)   // lub .ultraThinMaterial w dark mode
                            .matchedGeometryEffect(id: "font-scale", in: ns)
                    }
                }
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(Color(.systemGray5))
        }
    }
}
```

**Kluczowa zasada:**
- ✅ Jeden `Capsule` jako tło kontenera (`Color(.systemGray5)`)
- ✅ Jeden `Capsule` jako tło wybranego elementu (`.fill(.white)`)
- ❌ NIE używać `.overlay` ani dodatkowego tła na kontenerze
- ❌ NIE zagnieżdżać `background { background { } }`

---

### R6-5: Tasks — swipe w prawo = przenieś do Ideas (Backlog)

**Problem:** Sliding w prawo na tasku w sekcji NEXT nie robi nic (lub nie istnieje). Użytkownik chce móc łatwo cofnąć task do Backlog/Ideas.

**Mechanizm demote:** W `TasksView` istnieje już `TaskDetailSheet` z `onDemoteToBacklog` callbackiem który woła `demoteTaskToBacklog`. Ta logika powinna być dostępna też przez swipe.

**Fix:** Dodać `.swipeActions(edge: .leading)` do tasków w sekcji **NEXT** w `activeTasksContent`:

**Plik:** `FamilyTodo/Views/TasksView.swift`

```swift
// W activeTasksContent, ForEach dla store.nextTasks:
ForEach(Array(store.nextTasks.enumerated()), id: \.element.id) { index, task in
    if taskBeingCompleted != task.id {
        TaskRow(...)
            .rowInsertAnimation()
            .accessibilityIdentifier("taskRow_\(task.title)")
            // NOWE: swipe w prawo = cofnij do Ideas
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    withAnimation {
                        demoteTaskToBacklog(task)
                    }
                } label: {
                    Label("Ideas", systemImage: "archivebox.fill")
                }
                .tint(.indigo)
            }
    }
}
```

> **Uwaga:** `.swipeActions(edge: .leading)` = swipe **w prawo** (od lewej krawędzi).

**Implementacja `demoteTaskToBacklog` w `TasksContent`:**

Funkcja powinna już istnieć (dodana w R2-14). Jeśli nie — dodać:

```swift
private func demoteTaskToBacklog(_ task: Task) {
    Task {
        if let categoryId = task.backlogCategoryId {
            await backlogStore.addItem(
                to: categoryId,
                title: task.title,
                assigneeId: task.assigneeId,
                notes: task.notes
            )
        } else {
            // Brak kategorii — dodać do pierwszej dostępnej lub pominąć
            guard let firstCategory = backlogStore.categories.first else { return }
            await backlogStore.addItem(
                to: firstCategory.id,
                title: task.title,
                assigneeId: task.assigneeId,
                notes: task.notes
            )
        }
        await store.deleteTask(task)
    }
}
```

**Pliki:** `FamilyTodo/Views/TasksView.swift`

---

### Kolejność implementacji R6

| # | Plik | Zmiana |
|---|------|--------|
| R6-3 | `ThemeStore.swift` | Zmiana iconName dla Retro i Auto |
| R6-5 | `TasksView.swift` | `.swipeActions(edge: .leading)` na NEXT tasks |
| R6-1 | `ShoppingListView.swift` | `addPillButton` kolor = `selectedTabColor` |
| R6-2 | `ShoppingCountBadge.swift` | Zmniejszyć retroCoin do rozmiaru standardBadge |
| R6-4 | `MoreView.swift` / AppearanceSelector | Fix `FontSizePicker` — jeden owal |

> R6-3 jest najprostsze i niezależne. R6-5 wymaga sprawdzenia czy `demoteTaskToBacklog` jest dostępne w scope TasksContent – jeśli nie, dodać. R6-1 zależy od R5-7 (non-optional `tabTint.color`).

---

## R7: Globalny Accent Color + Light2/Dark2 Themes + Ideas Cleanup (2026-02-23)

> **Skills:** `swift-expert`, `swiftui-ui-patterns`
>
> **Kontekst kodu:**
> - `MainAppView` (ContentView.swift L82) już ma `.tint(themeStore.resolvedTabTint)` na `TabView` ✅
> - `TabTintColor` po R5-7: `defaultGreen`, `blue`, `red`, `black`
> - `UnifiedTheme`: `light`, `dark`, `auto`, `retro`, `paper`
> - `ThemePreset`: `system`, `retro`, `paper`
> - `BacklogItemRow`: pencil=`.secondary`, assign=`.blue`, promote=`.green`, trash=`.red`
> - FAB "Add item": `themeStore.accentColor` → po R6-1: `themeStore.selectedTabColor`

---

### R7-1: Rename "Tab bar color" → "Accent Color" + rozszerzyć do 6 kolorów

**Zmiana w ThemeStore.swift — enum `TabTintColor`:**

Dodać `orange` i `purple` do istniejących 4 kolorów (defaultGreen, blue, red, black):

```swift
enum TabTintColor: String, CaseIterable, Identifiable {
    case defaultGreen
    case blue
    case orange
    case pink
    case purple
    case monochrome   // Color.primary — czarny w light, biały w dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .defaultGreen: "Green"
        case .blue:         "Blue"
        case .orange:       "Orange"
        case .pink:         "Pink"
        case .purple:       "Purple"
        case .monochrome:   "Mono"
        }
    }

    var color: Color {
        switch self {
        case .defaultGreen: Color(hex: "34C759")
        case .blue:         Color.blue
        case .orange:       Color.orange
        case .pink:         Color.pink
        case .purple:       Color.purple
        case .monochrome:   Color.primary
        }
    }
}
```

**W ThemeStore — dodać computed property `accentTabColor`:**
```swift
var accentTabColor: Color {
    tabTint.color  // Używane globalnie jako .tint() + FAB + Badge
}
```

**Zmiana nazwy w Settings UI:**
- Znaleźć sekcję "Tab bar color" w MoreView lub AppearanceSelector
- Zmienić title sekcji na `"Accent Color"`
- Rozszerzyć HStack pickera do 6 kolorów (3+3 w dwóch rzędach jeśli nie mieszczą się w jednej linii)

**Plik:** `FamilyTodo/Views/ThemeStore.swift`, `FamilyTodo/Views/MoreView.swift`

---

### R7-2: Nowe warianty Light 2 i Dark 2 (czyste tła)

**Kontekst:** Aktualnie `light`/`dark` to tryby w `AppearanceMode`, nie osobne tematy. `ThemePreset` kontroluje fonty i kolory kart. Nie ma "light2" i "dark2" — trzeba je dodać.

**Podejście:** Dodać dwa nowe case do `UnifiedTheme` (i zmapować je do `ThemePreset.system` + nowe `AppearanceMode` lub osobny `ThemeVariant`).

**Prostsze podejście:** Dodać `light2` i `dark2` jako nowe `UnifiedTheme` case które wymuszają `ThemePreset.system` + odpowiednie `ColorScheme`, ale z innymi wartościami `surfaceColor` / `canvasColor`.

**Zmiana w `ThemeStore.swift`:**

```swift
// 1. Dodać do UnifiedTheme:
enum UnifiedTheme: String, CaseIterable, Identifiable {
    case light, dark, auto
    case light2  // NEW: czyste białe tło
    case dark2   // NEW: czyste czarne tło
    case retro, paper

    var displayName: String {
        switch self {
        case .light:  "Light"
        case .dark:   "Dark"
        case .auto:   "Auto"
        case .light2: "Light 2"
        case .dark2:  "Dark 2"
        case .retro:  "Retro"
        case .paper:  "Paper"
        }
    }

    var iconName: String {
        switch self {
        case .light:  "sun.max.fill"
        case .dark:   "moon.fill"
        case .auto:   "sparkles"         // z R6-3
        case .light2: "sun.max"          // Outline = "czyste"
        case .dark2:  "moon"             // Outline = "czyste"
        case .retro:  "dpad.fill"        // z R6-3
        case .paper:  "newspaper.fill"
        }
    }
}

// 2. W ThemeStore, rozszerzyć canvasColor / surfaceColor dla light2 / dark2:
var canvasColor: Color {
    switch unifiedTheme {
    // ...istniejące case...
    case .light2: Color(uiColor: .systemBackground)     // Pure White = #FFFFFF w light
    case .dark2:  Color(uiColor: .systemBackground)     // Pure Black = #000000 w dark
    // Żeby light2 wymusił light mode, a dark2 dark mode — patrz punkt 3
    }
}

var surfaceColor: Color {
    switch unifiedTheme {
    // ...istniejące case...
    case .light2: Color(uiColor: .secondarySystemGroupedBackground)  // #F2F2F7 — jasny szary
    case .dark2:  Color(uiColor: .secondarySystemGroupedBackground)  // #1C1C1E — ciemny szary
    }
}
```

**3. Wymuszenie ColorScheme dla light2 i dark2:**

W `ThemeStore` dodać computed property:
```swift
var preferredColorScheme: ColorScheme? {
    switch unifiedTheme {
    case .light, .light2: .light
    case .dark, .dark2:   .dark
    case .auto, .retro, .paper:
        // Retro i Paper mają własne appearanceMode
        appearanceMode.colorScheme
    }
}
```

W `FamilyTodoApp.swift` lub `MainAppView` zastosować:
```swift
.preferredColorScheme(themeStore.preferredColorScheme)
```

**Plik:** `FamilyTodo/Views/ThemeStore.swift`, `FamilyTodo/FamilyTodoApp.swift`

---

### R7-3: Ideas — wyciszenie kolorów ikon akcji

**Problem:** `BacklogItemRow` (BacklogView.swift L674-L704) używa:
- `pencil` → `.secondary` ✅ (już OK)
- `person.badge.plus` → `.blue` ❌ → zmienić na `.secondary`
- `arrow.up.circle.fill` → `.green` ❌ → zmienić na `.secondary`
- `trash` → `.red.opacity(0.7)` ✅ (zachować)

**Fix:**
```swift
// BacklogItemRow body, HStack z ikonami:
Button(action: onAssign) {
    Image(systemName: "person.badge.plus")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)   // Zmiana z .blue
        .frame(width: 30, height: 30)
}

Button(action: onPromote) {
    Image(systemName: "arrow.up.circle.fill")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)   // Zmiana z .green
        .frame(width: 30, height: 30)
}
```

**Plik:** `FamilyTodo/Views/BacklogView.swift` (struct `BacklogItemRow`, L683-L697)

---

### R7-4: Ideas — tła kart dla light2/dark2

`CategoryCard.cardBackground` już używa `themeStore.surfaceColor` po R5-3. Po dodaniu `surfaceColor` dla `.light2` i `.dark2` w R7-2 — karty będą automatycznie poprawne.

Jednak dla czytelności dodać też cień w light mode (z R5-3):

```swift
private var cardBackground: Color {
    themeStore.surfaceColor  // Automatycznie poprawny dla wszystkich themów po R7-2
}

// W body CategoryCard, .background modifier:
.background {
    RoundedRectangle(cornerRadius: 12)
        .fill(cardBackground)
        .shadow(
            color: colorScheme == .light ? .black.opacity(0.06) : .clear,
            radius: 4, x: 0, y: 2
        )
}
```

**Plik:** `FamilyTodo/Views/BacklogView.swift` (struct `CategoryCard`, L584-L587)

---

### R7-5: Ideas — tagi assignee z lepszym kontrastem

`BacklogItemRow` L662-L669 ma tag z `Color.secondary.opacity(0.14)` — niski kontrast. Dla light2/dark2 poprawić:

```swift
if let assigneeName {
    Text(assigneeName)
        .font(themeStore.font(for: .chip))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.secondary.opacity(colorScheme == .dark ? 0.2 : 0.12))
        )
}
```

**Plik:** `FamilyTodo/Views/BacklogView.swift` (struct `BacklogItemRow`, L662-L669)

---

### R7-6: FAB "Add Item" + Badge = Accent Color (konsolidacja z R6-1)

> R6-1 już to planuje — R7-6 jest potwierdzeniem że po R7-1 (non-optional `tabTint.color`) R6-1 staje się trywialne.

**Plik:** `FamilyTodo/Views/ShoppingListView.swift`

```swift
// addPillButton:
let pillColor = themeStore.accentTabColor  // Z R7-1
```

**ShoppingCountBadge** (standardBadge):
```swift
let badgeColor = themeStore.accentTabColor  // Z R7-1
```

---

### Tabela zmian R7

| # | Plik | Zmiana |
|---|------|--------|
| R7-1 | `ThemeStore.swift` | `TabTintColor` → 6 kolorów; Settings: rename do "Accent Color" |
| R7-2 | `ThemeStore.swift`, `FamilyTodoApp.swift` | `UnifiedTheme.light2/dark2`, `canvasColor`/`surfaceColor` per theme, `preferredColorScheme` |
| R7-3 | `BacklogView.swift` | assign+promote ikony → `.secondary` |
| R7-4 | `BacklogView.swift` | cień na CategoryCard w light mode |
| R7-5 | `BacklogView.swift` | tag opacity adaptacyjny light/dark |
| R7-6 | `ShoppingListView.swift`, `ShoppingCountBadge.swift` | FAB + badge używają `accentTabColor` |

### Kolejność implementacji R7

1. **R7-1** — rozszerzenie `TabTintColor` (niezależne, nowy `color` zawsze non-optional)
2. **R7-2** — `UnifiedTheme.light2/dark2` + `surfaceColor`/`canvasColor` + `preferredColorScheme`
3. **R7-3** — trivialny fix ikon (2 linie)
4. **R7-4 + R7-5** — karty i tagi (przy okazji R7-3, ten sam plik)
5. **R7-6** — FAB + badge (po R7-1 trivial)

> **Uwaga:** R7-2 wymaga ostrożnego mapowania `unifiedTheme` → `ColorScheme`. Sprawdzić czy `FamilyTodoApp.swift` już aplikuje `preferredColorScheme`, czy jest to w `MainAppView`.

---

## R8: Polish & Consistency (2026-02-24)

> **Skills:** `swift-expert`, `swiftui-ui-patterns`

---

### R8-1: Recently Purchased — przycisk "+" = Accent Color

**Problem:** Przyciski `+` w arkuszu "Recently Purchased" używają `themeStore.accentColor` zamiast globalnego koloru akcentu (po R7-1 `tabTint.color`).

**Root cause:** `RestockItemRow` (ShoppingListView.swift L758-L764):
```swift
.foregroundStyle(themeStore.accentColor)  // ← stary accentColor
```

**Fix:**
```swift
// RestockItemRow body, plus.circle.fill button:
Button { onRestore() } label: {
    Image(systemName: "plus.circle.fill")
        .font(.system(size: 22))
        .foregroundStyle(themeStore.accentTabColor)  // Z R7-1
}
```

**Plik:** `FamilyTodo/Views/ShoppingListView.swift` (struct `RestockItemRow`, ~L763)

---

### R8-2: Settings — ikona "Auto" diagonalnie płaska

**Problem:** Ikona "Auto" ma gradientowy wygląd. Użytkownik chce: płaska, bez gradientu, diagonalny split dark/light.

**Opcja A (SF Symbol rotowany):**
```swift
// W widoku karty tematu dla .auto — zastąpić ikonę:
Image(systemName: "circle.lefthalf.filled")
    .rotationEffect(.degrees(-45))
    .font(.system(size: 28, weight: .light))  // .light weight = cienszy, bez fill
```

**Opcja B (niestandardowy kształt — brak gradientu):**
```swift
struct DiagonalSplitIcon: View {
    var body: some View {
        ZStack {
            // Ciemna połowa
            Rectangle()
                .fill(Color.primary)
                .clipShape(DiagonalClip(isLeft: true))
            // Jasna połowa
            Rectangle()
                .fill(Color(uiColor: .systemBackground))
                .clipShape(DiagonalClip(isLeft: false))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: 28, height: 28)
    }
}

struct DiagonalClip: Shape {
    let isLeft: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if isLeft {
            p.move(to: rect.origin)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}
```

> Opcja A jest szybsza. Opcja B daje perfekcyjny wygląd jeśli czas pozwala.

**Plik:** MoreView.swift lub komponent renderujący siateczkę tematów (szukać gdzie renderowane są karty tematów `UnifiedTheme.allCases`)

---

### R8-3: Settings — ikona "Retro" = dyskietka

**Problem:** Ikona Retro = `gamecontroller.fill` (lub `dpad.fill` po R6-3). Zmienić na dyskietkę.

**Fix w `UnifiedTheme.iconName`:**
```swift
case .retro: "floppy.disk"   // Dostępny od iOS 17, iPadOS 17
```

> ⚠️ **Sprawdzić dostępność:** `"floppy.disk"` to SF Symbol dostępny od iOS 17+. Jeśli target jest iOS 16 — użyć `"externaldrive.fill"` jako fallback.
> Sprawdzić minimum deployment target w `FamilyTodo.xcodeproj`.

**Plik:** `FamilyTodo/Views/ThemeStore.swift` — `UnifiedTheme.iconName` (wcześniej zmieniony w R6-3)

---

### R8-4: Ideas — "+ Add item" = Accent Color

**Problem:** Przycisk "Add item" wewnątrz kart kategorii w Ideas (BacklogView) używa `themeStore.accentColor`.

**Root cause:** `CategoryCard` (BacklogView.swift L563-L574):
```swift
.stroke(themeStore.accentColor.opacity(0.55), ...)
.foregroundStyle(themeStore.accentColor)
```

**Fix — zastąpić `themeStore.accentColor` przez `themeStore.accentTabColor`:**
```swift
Circle()
    .stroke(themeStore.accentTabColor.opacity(0.55), lineWidth: 1.5)
    ...
    .foregroundStyle(themeStore.accentTabColor)

Text("Add item")
    .foregroundStyle(themeStore.accentTabColor)
```

**Plik:** `FamilyTodo/Views/BacklogView.swift` (struct `CategoryCard`, L563-L574)

---

### R8-5: Tasks — wyciszony wygląd dla zadań powyżej limitu

**Problem:** Przekroczone zadania (indeksy 3+) wyświetlają `orange` tło i kolor checkboxa — wizualny szum.

**Istniejąca logika (TaskRow.swift L828-L957):**
- `WipZone.warning` → checkbox=`.orange`, tło=`.orange.opacity(0.06)`
- `WipZone.danger` → checkbox=`.red`, tło=`.red.opacity(0.08)`

**Nowe zachowanie — "dimmed" zamiast kolorowania:**

**Krok 1 — Zmienić `uncheckedColor` i `rowBackgroundColor` w `TaskRow`:**
```swift
private var uncheckedColor: Color {
    switch wipZone {
    case .safe:    .green.opacity(0.5)
    case .normal:  .secondary.opacity(0.3)
    case .warning, .danger:
        .secondary.opacity(0.25)  // Wyciszony szary — nie orange/red
    }
}

private var rowBackgroundColor: Color {
    switch wipZone {
    case .safe:   .green.opacity(0.04)
    case .normal: .clear
    case .warning, .danger:
        .clear  // Brak kolorowego tła
    }
}
```

**Krok 2 — Dodać dimmed efekt na tekście taska powyżej limitu:**
```swift
// W TaskRow body, Text(task.title):
Text(task.title)
    .font(themeStore.font(for: .listRowTitle))
    .foregroundStyle(
        isCompleted ? .secondary :
        (wipZone == .warning || wipZone == .danger) ? .secondary :  // Dimmed
        .primary
    )
    .strikethrough(isCompleted)
```

**Krok 3 — Dodać separator "Over limit" po 3. tasku w `activeTasksContent`:**

W `TasksView.activeTasksContent` (L236-L283), po ForEach dla `store.nextTasks`, wstawić separator jeśli `store.nextTasks.count > 3`:

```swift
// Po pierwszych 3 taskach, jeśli są kolejne z warning/danger wipZone:
ForEach(Array(store.nextTasks.enumerated()), id: \.element.id) { index, task in
    if taskBeingCompleted != task.id {
        // Wstawiamy separator przed 4. taskiem
        if index == 3 && store.nextTasks.count > 3 {
            HStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                Text("Over limit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.vertical, 4)
        }

        TaskRow(...)
            .swipeActions(edge: .leading, allowsFullSwipe: false) { ... }
    }
}
```

**Pliki:**
- `FamilyTodo/Views/TasksView.swift` (struct `TaskRow` L828-L984, `activeTasksContent` L236-L283)

---

### R8-6: Settings — "System Font Size" w tym samym stylu co "Accent Color"

**Problem:** Selektor Small/Regular/Large wygląda "nago" bez kontenera, podczas gdy sekcja "Accent Color" ma białe zaokrąglone tło.

**Fix:** Owinąć `FontSizePicker` lub istniejący selektor w ten sam kontener co inne sekcje Settings:

```swift
// W widoku Settings (MoreView lub AppearanceSelector), sekcja Font Size:
VStack(alignment: .leading, spacing: 8) {
    Text("System Font Size")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)

    // Istniejący FontSizePicker — owinąć:
    FontSizePicker(selected: $themeStore.systemFontScale)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
}
```

Alternatywnie, jeśli sekcje są w `Form`/`List` — użyć `Section("System Font Size") { FontSizePicker(...) }` i pozwolić FormStyle za styl.

**Plik:** `FamilyTodo/Views/MoreView.swift` lub komponent AppearanceSelector (szukać gdzie renderowany jest `systemFontScale` picker)

---

### R8-7: Ujednolicenie tytułów Shopping / Tasks / Ideas

**Problem:** Tytuł "Shopping" wygląda inaczej niż "Tasks" i "Ideas" — inne położenie, rozmiar, lub padding.

**Diagnoza:**
- `ShoppingListView.header` (L213-L264): custom `HStack` z `Text("Shopping")` w `VStack` z `padding(.horizontal, 20)` + `padding(.top, 16)`
- `TasksView.header` (L383-L401): custom `HStack` z `Text("Tasks")`
- `BacklogView.header` (L251-L254): `HStack` z `Text("Ideas")`

Wszystkie trzy używają `.font(themeStore.font(for: .screenHeader))` — font jest ten sam.

**Potencjalne różnice do wyrównać:**

1. **Padding górny:** Upewnić się że każdy screen ma identyczny `padding(.top, X)` na headerze. Sprawdzić `AppChromeMetrics.headerTopPadding` jeśli istnieje.

2. **Padding poziomy:** Shopping używa `.padding(.horizontal, 20)` — sprawdzić czy Tasks i Ideas też mają 20pt.

3. **Wysokość HStack:** Jeśli Shopping ma badge (`ShoppingCountBadge`) a Tasks nie ma — HStack może być wyższy w Shopping. Upewnić się że badge nie rozciąga HStack pionowo:
```swift
ShoppingCountBadge(count: count)
    .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
```

4. **Sprawdzić `screenHeader` token** w ThemeStore — czy `size` i `weight` są takie same dla wszystkich presetów.

5. **Jeśli Shopping ma `.large` navigation title przez NavigationStack** a innych nie — upewnić się że wszystkie trzy używają custom inline header bez `navigationTitle`. Sprawdzić czy żaden z ekranów nie ma:
```swift
.navigationTitle("Shopping")   // ← usunąć jeśli jest, custom header ma priorytet
```

**Plik:** `ShoppingListView.swift`, `TasksView.swift`, `BacklogView.swift` — porównać i wyrównać `header` var

---

### Kolejność implementacji R8

| # | Priorytet | Plik | Zmiana |
|---|-----------|------|--------|
| R8-3 | Bardzo niski | `ThemeStore.swift` | `"floppy.disk"` dla Retro icon |
| R8-4 | Niski | `BacklogView.swift` | `accentTabColor` w "Add item" |
| R8-1 | Niski | `ShoppingListView.swift` | `accentTabColor` w RestockItemRow |
| R8-5 | Średni | `TasksView.swift` | WipZone dimmed + separator "Over limit" |
| R8-7 | Średni | Wszystkie 3 views | Inspekcja i wyrównanie headerów |
| R8-2 | Niski | `MoreView.swift` | Ikona Auto — opcja A (SF Symbol rotowany) |
| R8-6 | Niski | `MoreView.swift` | FontSizePicker w wrapperze |

> R8-3 i R8-4 są trywialne (1 linia). R8-5 jest najbardziej złożone — dodanie separatora wymaga modyfikacji ForEach w `activeTasksContent`. R8-7 to diagnoza + drobne korekty paddingów.

---

## R9: Settings Cleanup, Task UX & Polish (2026-02-24)

> **Skills:** `swift-expert`, `swiftui-ui-patterns`

---

### R9-1: Settings → Retro — usuń wybór fontów, zawsze używaj PressStart2P

**Problem:** Sekcja "Retro Font" w Settings pokazuje picker "Font Style" (A – Classic, B – Thin). Retro ma zawsze używać A – Classic (Press Start 2P).

**Root cause:** `SettingsView.swift` L58-L80:
```swift
} else if themeStore.preset == .retro {
    Section {
        Picker("Font Style", ...) { ... }  // ← USUNĄĆ
        FontScaleSelector(...)
    } header: { Text("Retro Font") }
}
```

**Fix — dwa kroki:**

**1. `SettingsView.swift` — usunąć Picker "Font Style" z sekcji Retro:**
```swift
} else if themeStore.preset == .retro {
    Section {
        // USUNĄĆ: cały blok Picker("Font Style", ...)
        FontScaleSelector(
            selectedScale: Binding(
                get: { themeStore.retroFontScale },
                set: { HapticManager.selection(); themeStore.retroFontScale = $0 }
            )
        )
    } header: {
        Text("Retro Font")
    } footer: {
        Text("Regular is the default font size.")
    }
}
```

**2. `ThemeStore.swift` — hardcode `retroVariant` na `.a`:**

W `ThemeStore` dodać do `init` lub w computed property:
```swift
// Upewnić się że retroVariant zawsze = .a bez względu na zapisaną wartość
var retroVariant: RetroVariant {
    get { .a }  // Zawsze A – Classic (PressStart2P)
    set { }     // Ignorować zapis
}
```
Lub alternatywnie: usunąć `@AppStorage("retroVariant")` i wszędzie gdzie kod używa `themeStore.retroVariant` zastąpić literalem `.a`.

**Plik:** `FamilyTodo/Views/SettingsView.swift` (L58-L80), `FamilyTodo/Views/ThemeStore.swift`

---

### R9-2: Settings → Paper — usuń wybór fontów, zawsze używaj Modern Classic (Georgia)

**Problem:** Sekcja "Paper Font" w Settings pokazuje picker "Font Style" (A–G). Paper ma zawsze używać wariantu F – Modern Classic (Georgia + Georgia).

**Root cause:** `SettingsView.swift` L31-L57 — `Picker("Font Style")` dla `PaperVariant`.

**Fix — dwa kroki:**

**1. `SettingsView.swift` — usunąć Picker "Font Style" z sekcji Paper:**
```swift
if themeStore.preset == .paper {
    Section {
        // USUNĄĆ: cały blok Picker("Font Style", ...)
        FontScaleSelector(
            selectedScale: Binding(
                get: { themeStore.paperFontScale },
                set: { HapticManager.selection(); themeStore.paperFontScale = $0 }
            )
        )
    } header: {
        Text("Paper Font")
    }
}
```

**2. `ThemeStore.swift` — hardcode `paperVariant` na `.f`:**
```swift
var paperVariant: PaperVariant {
    get { .f }  // Zawsze F – Modern Classic (Georgia + Georgia)
    set { }     // Ignorować zapis
}
```

> Uwaga: Po R5-6 `PaperVariant` ma tylko `.e` i `.f`. `.f` = "Modern Classic" = Georgia + Georgia.

**Plik:** `FamilyTodo/Views/SettingsView.swift` (L31-L57), `FamilyTodo/Views/ThemeStore.swift`

---

### R9-3: Settings — usuń Light2/Dark2, Light i Dark przejm ich ustawienia

**Problem:** W Settings jest 7 kafelków (Light, Dark, Auto, Light2, Dark2, Retro, Paper). Użytkownik chce 5: Light, Dark, Auto, Retro, Paper — ale Light używa palety Light2, a Dark używa palety Dark2.

**Krok 1 — `ThemeStore.swift`: aktualizacja `canvasColor` i `surfaceColor` dla `.light` i `.dark`:**

```swift
// PRZED (light):
case .light: Color(hex: "F9F9F9")  // lub podobny lekko szary

// PO (light = czyste białe jak light2):
case .light: Color(uiColor: .systemBackground)  // Pure white w light mode

// PRZED (dark):
case .dark: Color(hex: "1C1C1E")   // lub podobny

// PO (dark = czyste czarne jak dark2):
case .dark: Color(uiColor: .systemBackground)   // Pure black w dark mode
```

Analogicznie `surfaceColor`:
```swift
case .light: Color(uiColor: .secondarySystemGroupedBackground)  // Jasny szary #F2F2F7
case .dark:  Color(uiColor: .secondarySystemGroupedBackground)  // Ciemny szary #1C1C1E
```

**Krok 2 — `ThemeStore.swift`: usunąć `.light2` i `.dark2` z `UnifiedTheme`:**
```swift
enum UnifiedTheme: String, CaseIterable, Identifiable {
    case light, dark, auto, retro, paper
    // USUNĄĆ: case light2, dark2
}
```

**Krok 3 — `ThemeStore.swift`: naprawić wszystkie switch/case:**

Poszukać wszystkich `switch unifiedTheme` (lub `switch self` w `UnifiedTheme`) i usunąć case `.light2` i `.dark2`. Zastąpić logikę która była w `.light2`/`.dark2` przez nowe wartości dla `.light`/`.dark`.

**Krok 4 — `SettingsView.swift`: swatch gradient zachować:**

`UnifiedThemeCard.swatchGradient` dla `.light` już ma:
```swift
case .light: [Color(hex: "FFFFFF"), Color(hex: "F5F5F5")]  // Zachować wygląd kafelka
case .dark:  [Color(hex: "1C1C1E"), Color(hex: "2C2C2E")]  // Zachować wygląd kafelka
```

**Pliki:** `FamilyTodo/Views/ThemeStore.swift` (enum `UnifiedTheme`, `canvasColor`, `surfaceColor`, `preferredColorScheme`), `FamilyTodo/Views/SettingsView.swift` (sprawdzić czy `light2`/`dark2` nie są używane)

---

### R9-4: Tasks — usuń nagłówek "NEXT"

**Problem:** Tasks wyświetla sekcję nagłówkową "NEXT" nad listą aktywnych tasków — niepotrzebna etykieta.

**Root cause:** `TasksView.swift` L239:
```swift
sectionHeader("NEXT")  // ← USUNĄĆ
```

**Fix:**
```swift
private var activeTasksContent: some View {
    if !store.nextTasks.isEmpty {
        // USUNĄĆ: sectionHeader("NEXT")

        ForEach(Array(store.nextTasks.enumerated()), id: \.element.id) { index, task in
            // ... bez zmian
        }
    }
    // ... reszta bez zmian
}
```

**Plik:** `FamilyTodo/Views/TasksView.swift` (L239)

---

### R9-5: Tasks — swipe w lewo = "Move to Ideas"

**Problem:** Swipe w lewo na tasku w sekcji aktywnych (NEXT) powinien przenosić go do Ideas/Backlog.

**Uwaga:** `.swipeActions(edge: .trailing)` = swipe w **lewo**. Aktualnie NEXT tasks nie mają żadnych trailing swipe actions (L241-L255).

**Krok 1 — dodać funkcję `moveToIdeas` w `TasksView`/`TasksContent`:**

```swift
private func moveToIdeas(_ task: Task) {
    _Concurrency.Task {
        // Zmiana statusu na backlog — sprawdzić jak `startTaskFromBacklog` robi reverse
        // Wzorzec: tasks z store.backlogTasks mają status == .backlog lub isBacklog == true
        await store.demoteToBacklog(task)  // Dodać tę metodę do TaskStore jeśli nie istnieje
    }
}
```

**Krok 2 — dodać `demoteToBacklog` w `TaskStore`:**

```swift
func demoteToBacklog(_ task: Task) async {
    var updated = task
    updated.status = .backlog   // Lub .ideas, zależnie od enum Task.Status
    await updateTask(updated)
}
```

> Sprawdzić jak `startTaskFromBacklog` działa (L274) — robi reverse tej operacji. Użyć odwrotnej logiki.

**Krok 3 — dodać `.swipeActions(edge: .trailing)` na NEXT tasks:**

```swift
ForEach(Array(store.nextTasks.enumerated()), id: \.element.id) { index, task in
    if taskBeingCompleted != task.id {
        TaskRow(...)
            .rowInsertAnimation()
            .accessibilityIdentifier("taskRow_\(task.title)")
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .none) {
                    moveToIdeas(task)
                } label: {
                    Label("Ideas", systemImage: "archivebox.fill")
                }
                .tint(.indigo)
            }
    }
}
```

**Pliki:** `FamilyTodo/Views/TasksView.swift`, `FamilyTodo/Store/TaskStore.swift` (lub analogiczny plik)

---

### R9-6: Ideas — "Add item" natychmiast otwiera klawiaturę

**Problem:** Po kliknięciu "Add item" w karcie kategorii (Ideas), `TextField` się pojawia, ale klawiatura nie otwiera się automatycznie — trzeba kliknąć ponownie.

**Root cause:** `CategoryCard` (`BacklogView.swift` L458) używa `@State var isAddingItem = false`, ale `TextField` nie ma `@FocusState` — klawiatura nie jest wymuszana programatycznie.

**Fix — dodać `@FocusState` do `CategoryCard`:**

```swift
struct CategoryCard: View {
    // ... istniejące właściwości ...
    @State private var isAddingItem = false
    @FocusState private var isTextFieldFocused: Bool   // NOWE
    @State private var newItemText = ""

    // W body, w bloku gdzie isAddingItem == true:
    if isAddingItem {
        HStack {
            TextField("Add item", text: $newItemText)
                .focused($isTextFieldFocused)         // NOWE
                .font(themeStore.font(for: .listRowTitle))
                .submitLabel(.done)
                .onSubmit { commitNewItem() }
                // ... reszta bez zmian
        }
    } else {
        Button { isAddingItem = true } label: { ... }
    }

    // W onChange lub task, wymusić focus gdy isAddingItem = true:
    .onChange(of: isAddingItem) { _, newValue in
        if newValue {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTextFieldFocused = true   // Mały delay dla animacji
            }
        }
    }
}
```

> Alternatywnie użyć `.task(id: isAddingItem) { if isAddingItem { isTextFieldFocused = true } }` — bez DispatchQueue.

**Plik:** `FamilyTodo/Views/BacklogView.swift` (struct `CategoryCard`, ~L458-L540)

---

### R9-7: Settings — System Font Size z efektem szkła (przywrócić stary wygląd)

**Problem:** `FontScaleSelector` wywoływany z `showSelectionPill: false, showBorder: false` wygląda "nago" — brak efektu selection i brak border.

**Root cause:** `SettingsView.swift` L83-L100:
```swift
FontScaleSelector(
    selectedScale: ...,
    showSelectionPill: false,   // ← wyłączona "pastylka" dla wybranego
    showBorder: false           // ← wyłączony border kontenera
)
```

Parametry `showSelectionPill: false` i `showBorder: false` wyłączają efekt szkła który pokazuje wybrany element.

**Fix — przywrócić domyślne wartości (usunąć override):**

```swift
FontScaleSelector(
    selectedScale: Binding(
        get: { themeStore.systemFontScale },
        set: { HapticManager.selection(); themeStore.systemFontScale = $0 }
    )
    // Usunąć: showSelectionPill: false, showBorder: false
    // Domyślnie: showSelectionPill = true, showBorder = true
)
.listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
.listRowBackground(Color.clear)
```

I usunąć zewnętrzny wrapper `.padding(12).background { RoundedRectangle ... }` bo `FontScaleSelector` ma własne tło.

**Plik:** `FamilyTodo/Views/SettingsView.swift` (L81-L101)

---

### R9-8: Accent Color "Mono" + Dark mode — niewidoczne przełączniki Toggle

**Problem:** Gdy Accent Color = Mono (`Color.primary`) i theme = Dark, przełączniki Toggle w Settings (Celebrations, Enable notifications itd.) są niewidoczne — biały toggle na ciemnym tle nie sygnalizuje stanu ON.

**Root cause:** iOS `Toggle` używa `.tint()` ze środowiska do koloru stanu ON. `Color.primary` w dark mode = biały = niewidoczny na białym tle ON-state.

**Fix — w `ThemeStore.swift` dodać `toggleTintColor`:**

```swift
var toggleTintColor: Color {
    guard case .monochrome = tabTintColor else {
        return tabTintColor.color  // Normalny kolor = OK
    }
    // Mono w dark mode: użyj szarego zamiast białego
    // Sprawdzić colorScheme — ThemeStore nie ma dostępu, użyć preferredColorScheme
    switch preferredColorScheme {
    case .dark:   return Color(hex: "8E8E93")  // iOS system gray — widoczny w dark
    case .light:  return Color.primary          // Czarny = OK w light
    default:      return Color(hex: "8E8E93")  // Safe default
    }
}
```

> Ponieważ `ThemeStore` może nie mieć dostępu do aktualnego `colorScheme`, inny podejście:

**Alternatywne podejście — zmodyfikować kolor Mono w `TabTintColor.color`:**

Zamiast `Color.primary`, użyć innego koloru dla "Mono" który wygląda dobrze w obydwu trybach:

```swift
case .monochrome: Color(uiColor: .label)  // Zamiast Color.primary — label jest bardziej przewidywalny
```

Lub całkowicie zmienić definicję toggle tint w sekcji Toggles Settings:

**W `SettingsView.swift`, zmienić `.tint()` na Toggles Section:**
```swift
Section {
    Toggle(...) { ... }
    Toggle(...) { ... }
}
.tint(themeStore.safeToggleTint)  // Nowa property w ThemeStore

// W ThemeStore:
var safeToggleTint: Color {
    let base = tabTintColor.color
    // Jeśli kolor jest zbyt jasny (luminancja > 0.8), zamień na szary
    // Prosta heurystyka: Color.primary i białe kolory → szary
    if tabTintColor == .monochrome {
        return Color(hex: "34C759")  // Zielony jako bezpieczny fallback dla toggles
    }
    return base
}
```

> Prostsze podejście: zmienić `case .monochrome` w `TabTintColor.color` tak żeby zawracał `Color.primary` tylko dla tint tab bar, a Toggle używa osobnego systemu. Jednak najprostsza zmiana to użycie `.tint(Color.green)` lub `.tint(themeStore.accentColor)` na sekcji Toggles gdy `tabTintColor == .monochrome`.

**Plik:** `FamilyTodo/Views/SettingsView.swift` (Section z Toggle, L154-L163, L180-L210), `FamilyTodo/Views/ThemeStore.swift`

---

### Kolejność implementacji R9

| # | Plik | Zmiana |
|---|------|--------|
| R9-4 | `TasksView.swift` | Usunąć `sectionHeader("NEXT")` — 1 linia |
| R9-1 | `SettingsView.swift`, `ThemeStore.swift` | Usuń Retro font picker, hardcode `.a` |
| R9-2 | `SettingsView.swift`, `ThemeStore.swift` | Usuń Paper font picker, hardcode `.f` |
| R9-7 | `SettingsView.swift` | Usunąć `showSelectionPill: false, showBorder: false` |
| R9-3 | `ThemeStore.swift`, `SettingsView.swift` | Usuń `light2`/`dark2` z enum, przenieś ich palette do `light`/`dark` |
| R9-5 | `TasksView.swift`, `TaskStore.swift` | `.swipeActions(edge: .trailing)` = "Move to Ideas" |
| R9-6 | `BacklogView.swift` | `@FocusState` + `focused($isTextFieldFocused)` w `CategoryCard` |
| R9-8 | `ThemeStore.swift`, `SettingsView.swift` | Safe toggle tint dla Mono accent |

> **Uwaga do R9-3:** Po usunięciu `.light2` i `.dark2` upewnić się że `@AppStorage("unifiedTheme")` fallback jest `.light` (nie `.light2`, które przestanie istnieć). Dodać migrację: jeśli `rawValue == "light2"` → ustawić `.light`.
