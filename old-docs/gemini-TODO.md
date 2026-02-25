# SwiftUI UI Patterns - Code Review Findings

Based on the `swiftui-ui-patterns` and `swift-expert` guidelines, the following violations were found in the codebase:

## 1. Sheet Action Ownership
**Pattern Violation:** "Sheets should own their actions instead of forwarding closures"

*   **`TasksView.swift`:** The `AssigneePickerSheet` forwards `onCancel` and `onConfirm` closures to `TasksContent` instead of handling the actions internally and calling `@Environment(\.dismiss)`.
*   **`ShoppingListView.swift`:** The `RestockSheet` forwards `onRestore`, `onDeleteItem`, and `onClearAll` actions. Instead, it should execute these directly on the `store` it already observes and manage its own dismissal using `@Environment(\.dismiss)`.

## 2. Sheet Presentation State
**Pattern Violation:** "Prefer `.sheet(item:)` over `.sheet(isPresented:)` when representing a model"

*   **`TasksView.swift`:** Uses an awkward `.sheet(isPresented: Binding(get: { pendingNextTask != nil } ...))` instead of the cleaner `.sheet(item: $pendingNextTask)` pattern.

## 3. iOS 26 Tab Bar Typography
**Issue:** Custom fonts (Retro, Paper) are not applying to the native  on iOS 18+.

*   **`ContentView.swift`**: Currently uses the new  syntax introduced in iOS 18 (up to iOS 26). The  settings applied via  do not natively affect the title text attributes of these new  elements.
*   **Solution Path**: To get the custom font applying properly for an iOS 26 target (iPhone 15), we should either:
    *   **(Recommended)** Fall back to exactly how  is written (using ) unconditionally. Even on iOS 26, this forces the use of the older rendering path which perfectly respects  for custom fonts like the .
    *   **(Alternative)** Switch entirely to the custom  mentioned in , which is 100% SwiftUI and fully supports  styling natively along with the iOS 26 Liquid Glass effect.
