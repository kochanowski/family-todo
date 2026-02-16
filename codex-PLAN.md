# Codex Plan: UX Round 4 & R3 Cleanup

> **Context:** Continuing work from Claude. R2 and most of R3 features are implemented. This plan focuses on remaining R3 cleanup and full R4 implementation (Themes, Fonts, Tab Colors).

## Active Skills
- `swift-expert`
- `swiftui-liquid-glass`
- `swiftui-ui-patterns`

---

## 🟢 Status Check (Implemented)
- ✅ **R2-13:** `backlogCategoryId` on Task
- ✅ **R2-14:** Demote to Backlog (callback flow)
- ✅ **R3-1:** Focus Rule Banner (chart icon, dynamic limit)
- ✅ **R3-2:** Backlog Category Colors (deterministic)
- ✅ **R3-3:** Task Tags (Category + Owner)
- ✅ **R3-5:** Active/Completed Toggle + Liquid Glass
- ✅ **R3-Cleanup:** Cleanup dialog in TasksView

---

## 📝 Pending Tasks (To Do)

### R4-1: Themes Engine Expansion (Retro/Paper)
**Goal:** Activate the unwired ThemeStore and add new distinct themes with custom fonts.

1. **Wire up ThemeStore:**
   - `ThemeStore.preset` is currently unused. Ensure app listens to it.
   - Inject selected theme palette into `AppBackgroundView` and Card themes.

2. **Add Custom Fonts:**
   - **Retro (8-bit):** Add `PressStart2P-Regular.ttf` to bundle + Info.plist.
   - **Paper (Serif):** Use system Serif (Georgia/New York).
   - Add `fontName: String?` to `ThemePreset`.

3. **Implement New Themes:**
   - **Retro:** NES Palette (#E60012, #009B3A, #0058A1), dark CRT styling.
   - **Paper:** Cream/Beige texturized background, dark brown text.
   - **Ocean:** Teal/Blue gradients.

4. **Settings UI:**
   - Add `ThemeSelector` grid below AppearanceSelector in `SettingsView`.
   - Show previews of theme palettes.

### R4-2: Tab Bar Tint Color
**Goal:** Allow changing the tab bar active color.

1. **ContentView:**
   - Add `.tint(themeStore.accentColor)` to `TabView`.
2. **Settings:**
   - Add ColorPicker or predefined palette for Tab Tint (if distinct from Theme). *Decision: Link to Theme Preset primarily, or allow override?* -> **Link to Theme Palette accent** for consistency.

### R3-Cleanup: Remove "Task History" from MoreView
**Goal:** Clean up legacy navigation since Completed Tasks moved to TasksView.

1. **MoreView.swift:**
   - Remove `NavigationLink` to `CompletedTasksView`.
   - Comment out or remove `CompletedTasksView` file usage.

---

## 🛠️ Implementation Details

### R4-1: Theme Integration

**File:** `FamilyTodo/Views/ThemeStore.swift`

```swift
enum ThemePreset: String, CaseIterable, Identifiable {
    case journal, pastel, soft, night
    case retro, paper, ocean // NEW

    var fontName: String? {
        switch self {
        case .retro: "PressStart2P-Regular"
        case .paper: "Georgia"
        default: nil
        }
    }
}
```

**File:** `FamilyTodo/FamilyTodoApp.swift` (or where custom modifiers are)

Create a `themedFont` modifier that respects the selected preset's font.

### R4-3: MoreView Cleanup

**File:** `FamilyTodo/Views/MoreView.swift`

```diff
- NavigationLink {
-    CompletedTasksView()
- } label: {
-    MoreRow(icon: "checkmark.circle", title: "Task History")
- }
```

---

## 🚀 Execution Order
1. **R3-Cleanup:** Remove Task History from MoreView. (Quick win)
2. **R4-1 (Part A):** Verify ThemeStore wiring & add ThemeSelector UI.
3. **R4-1 (Part B):** Add Custom Fonts & New Presets (Retro, Paper).
4. **R4-2:** Tint TabView in ContentView based on Theme.
