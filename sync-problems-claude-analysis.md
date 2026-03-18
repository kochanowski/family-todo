# Bug Analysis: 4 Issues — HousePulse App

_Analysis date: 2026-03-16_

---

## Issue 1: Text Autocapitalization Inconsistency in Shopping Bundles

### Root Cause

In `FamilyTodo/Views/BundlesManagementView.swift`, all TextFields inside bundle flows use `.textInputAutocapitalization(.words)`:

- **Line 446** — `ShoppingBundleHeaderRow` (bundle name field): `.textInputAutocapitalization(.words)`
- **Line 633** — `ShoppingBundleItemRow` (editing existing item): `.textInputAutocapitalization(.words)`
- **Line 669** — `ShoppingBundleComposerRow` (adding new item): `.textInputAutocapitalization(.words)`

In contrast, `FamilyTodo/Views/ShoppingListView.swift` uses:
- Inline editing/composing: **no explicit autocapitalization** (system default = `.sentences`)
- Rapid entry mode (`RapidEntryTextField`, line 1053): explicit `.sentences` via `textField.autocapitalizationType = .sentences`

### Fix

**Files to modify:** `FamilyTodo/Views/BundlesManagementView.swift`

Change the autocapitalization on the two **item** TextFields (lines 633 and 669) from `.words` to `.sentences`.

The **bundle name** (line 446) may legitimately stay as `.words` since bundle names are proper nouns (e.g., "Breakfast Staples") — but should be confirmed with UX requirements. Item content should follow the same sentence-case pattern as the main shopping list.

```swift
// Line 633 — ShoppingBundleItemRow: CHANGE from .words → .sentences
.textInputAutocapitalization(.sentences)

// Line 669 — ShoppingBundleComposerRow: CHANGE from .words → .sentences
.textInputAutocapitalization(.sentences)
```

### Risk
Low. Pure UI change, no logic impact.

---

## Issue 2: UI Flickering / Loss of Local-First Responsiveness

### Root Cause — Primary: BacklogView missing guard

`FamilyTodo/Views/BacklogView.swift`, line 186:

```swift
.task {
    await loadBacklogData()
    markIdeasTutorialAsSeenIfNeeded()
}
```

**There is no guard.** Every time BacklogView appears (tab switch, navigation pop), `.task` fires again, calling `loadBacklogData()` which:
1. Sets `store.isLoading = true` on the store
2. Calls `store.loadData()` which calls `loadFromCache()` synchronously then awaits CloudKit

If any UI element in BacklogView renders an empty state or loading indicator when `isLoading == true` (or checks `categories.isEmpty` before cache repopulates), the view blanks momentarily on every tab return.

Compare: `ShoppingListView` has `guard !didPerformInitialLoad else { return }` (lines 79–82) and `TasksView` has `guard !hasStartedInitialLoad else { return }` (lines 193–198). BacklogView has neither.

### Root Cause — Secondary: isLoading-driven UI blanking

Each store (`BacklogStore.loadData()`, etc.) sets `isLoading = true` at the top of the load function. If any view layer shows empty content while `isLoading == true`, this causes the flicker even when the re-load is triggered. The fix must address both the guard (stop unnecessary re-loads) and any isLoading-driven empty states.

### Fix

**Files to modify:** `FamilyTodo/Views/BacklogView.swift`

**Step 1 — Add initial-load guard** (mirror the pattern from TasksView):

```swift
// Add to BacklogView state
@State private var hasStartedInitialLoad = false

// Modify .task block (line 186)
.task {
    guard !hasStartedInitialLoad else { return }
    hasStartedInitialLoad = true
    await loadBacklogData()
    markIdeasTutorialAsSeenIfNeeded()
}
```

**Step 2 — Verify isLoading-driven empty states** in `BacklogView` body. If any `if store.isLoading { /* blank/spinner */ }` or `if store.categories.isEmpty && !store.isLoading` pattern exists, ensure the empty state is only shown when data has been fetched AND is genuinely empty — not during in-progress loads that will overwrite with cached data.

**Step 3 — Verify TasksView and ShoppingListView** for the same isLoading-driven issue to confirm no additional flickering sources exist (these have guards but may still flicker on first load if isLoading causes empty-list rendering).

### Risk
Low-medium. The guard change is safe — `onChange` handlers (lines 190–194) still trigger `loadBacklogData()` on sync mode changes, so live updates remain intact.

---

## Issue 3: Disabled 'Save' Button in Household Edit View

### Root Cause

`FamilyTodo/Views/HouseholdSettingsView.swift`, the `EditHouseholdNameSheet` struct (around line 770+):

```swift
.disabled(
    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        isSaving
)
```

The disabled condition checks **only** whether the name is empty or a save is in progress. It does **not** check whether any actual change has been made (no `hasChanges` logic).

There are two possible manifestations of the bug:

**Scenario A — Button stays disabled (most likely):**
The `household` object is an `@Model` class (SwiftData reference type). When the user edits the TextField bound to `$name`, the `Household.name` property on the reference object may also update reactively, keeping `name == household.name` at all times. If someone previously tried to add a `!hasChanges` condition and compared against `household.name`, the comparison would always be false.

> **Investigation needed:** Confirm whether `household` is `@Model` (class) or struct. If class, TextField binding `$name` updates `name: @State var` — which is isolated — but if somewhere a computed property reads `household.name`, that may shadow.

**Scenario B — hasChanges guard was added incorrectly:**
A `hasChanges` computed property may have been added with a bug (e.g., comparing wrong values), resulting in the condition always evaluating `!hasChanges == true` → always disabled.

**Scenario C — Expected UX (button should enable on changes, but doesn't):**
The intent is for Save to only activate when the user has changed something from the original values, but the required `hasChanges` logic was never implemented. Currently the Save button IS enabled by default (because household.name is non-empty), but a user who enters the view and immediately tries Save finds that nothing visually changed — and assumes the button must be disabled because it "feels" inert.

### Fix

**Files to modify:** `FamilyTodo/Views/HouseholdSettingsView.swift`

Add proper `hasChanges` tracking by storing initial values and comparing against current:

```swift
// Add to EditHouseholdNameSheet properties
private let initialName: String
private let initialIconSymbol: String

// Update init (lines 796–804)
init(household: Household, onSaveSuccess: @escaping () -> Void) {
    self.household = household
    self.onSaveSuccess = onSaveSuccess
    self.initialName = household.name
    self.initialIconSymbol = household.iconSymbol
    _name = State(initialValue: household.name)
    _selectedIconSymbol = State(initialValue: household.iconSymbol)
}

// Add computed property
private var hasChanges: Bool {
    name.trimmingCharacters(in: .whitespacesAndNewlines) != initialName ||
        selectedIconSymbol != initialIconSymbol
}

// Update disabled condition (lines 884–887)
.disabled(
    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        isSaving ||
        !hasChanges
)
```

This ensures:
- Button starts disabled (no changes yet — clean state on open)
- Button enables the moment name or icon differs from original
- Button disables again if user reverts both to original values
- Button disables during save in progress

### Risk
Low. Pure UI state logic, no store or CloudKit changes.

---

## Issue 4: TipKit Not Appearing After Hard Reset

### Root Cause

`FamilyTodo/Services/AppTips.swift` — Hard reset calls `AppTips.resetForDevelopment()` (line 582 of FamilyTodoApp.swift), which:

```swift
static func resetForDevelopment() {
    if #available(iOS 17, *) {
        try Tips.resetDatastore()      // ✅ resets tip state
    }
    clearOnboardingProgress()
    defaults.removeObject(forKey: AppTipStorageKey.contextSignature)
    bumpRuntimeGeneration()
    hasConfigured = false
    configureIfNeeded()                // ✅ re-configures TipKit
}
```

This looks correct in isolation. But the problem occurs **after** this point: `syncContextIfNeeded()` (lines 76–108 of AppTips.swift) is called when session/household context changes, and it **also calls `Tips.resetDatastore()`** (line 97).

**The sequence that breaks tips:**

1. Hard reset fires → `AppTips.resetForDevelopment()` → `Tips.resetDatastore()` + `Tips.configure()` ✅
2. User lands on onboarding screen
3. User creates or joins a household → session context changes → `syncContextIfNeeded()` fires
4. `syncContextIfNeeded()` calls `Tips.resetDatastore()` again ⚠️
5. After this second reset, **`Tips.configure()` is NOT called again**
6. TipKit is now in a reset-but-not-configured state → tips are invisible

Additional suspect: after the second `Tips.resetDatastore()`, `hasConfigured` remains `true` (it was set by step 1's `configureIfNeeded()`). So subsequent calls to `configureIfNeeded()` skip re-configuration (`guard !hasConfigured else { return }`). TipKit never recovers.

### Fix

**Files to modify:** `FamilyTodo/Services/AppTips.swift`

**Step 1 — Fix `syncContextIfNeeded()`:**

Ensure that whenever `Tips.resetDatastore()` is called, `Tips.configure()` follows immediately. Two sub-options:

*Option A — Call `configureIfNeeded()` after reset in `syncContextIfNeeded()`:*
```swift
// In syncContextIfNeeded(), after Tips.resetDatastore()
hasConfigured = false
configureIfNeeded()
```

*Option B — Centralize reset+configure into a single private method:*
```swift
private static func resetAndReconfigure() throws {
    if #available(iOS 17, *) {
        try Tips.resetDatastore()
    }
    hasConfigured = false
    configureIfNeeded()
}
```
Then call `resetAndReconfigure()` from both `resetForDevelopment()` and `syncContextIfNeeded()`.

**Step 2 — Verify `syncContextIfNeeded()` trigger timing:**

Confirm whether `syncContextIfNeeded()` is called during the post-reset onboarding flow. If it fires every time a new household is joined/created, and if the intent is to reset tips per-household, that's valid — but it must be followed by re-configuration. If it fires unnecessarily (e.g., when context hasn't meaningfully changed), the condition logic should be tightened.

**Step 3 — Verify context signature after reset:**

`defaults.removeObject(forKey: AppTipStorageKey.contextSignature)` is called in `resetForDevelopment()`. This means when a new household is created, `syncContextIfNeeded()` will detect a context change (old signature = nil, new signature = household ID) and trigger its own reset. This is the concrete trigger for the double-reset. The fix in Step 1 (ensure configure follows reset) is the correct resolution.

### Risk
Medium. TipKit is session-wide state. Any change to configure/reset sequencing can affect tip display across all flows. Must test:
- Fresh install (no hard reset)
- Hard reset → create household
- Hard reset → join household
- Normal household switch (no reset)

---

## Summary Table

| # | Issue | File | Line(s) | Root Cause | Fix Complexity |
|---|-------|------|---------|------------|----------------|
| 1 | Autocapitalization | `BundlesManagementView.swift` | 633, 669 | `.words` instead of `.sentences` | Trivial |
| 2 | UI Flickering | `BacklogView.swift` | 186 | Missing `hasStartedInitialLoad` guard | Low |
| 3 | Save Button Disabled | `HouseholdSettingsView.swift` | 884–887, init | Missing `hasChanges` logic | Low |
| 4 | TipKit After Reset | `AppTips.swift` | ~97 (syncContextIfNeeded) | `Tips.resetDatastore()` without re-configure in `syncContextIfNeeded()` | Medium |

---

## Recommended Implementation Order

1. **Bug 1** (autocapitalization) — 1-line fix, ships safely, fast regression
2. **Bug 3** (Save button) — isolated UI logic, no CloudKit risk
3. **Bug 2** (flickering) — add guard first, verify isLoading-driven states second
4. **Bug 4** (TipKit) — most nuanced, test all session paths thoroughly

---

## Pre-implementation Checklist

- [ ] Confirm `Household` is `@Model` (class) or struct — affects Bug 3 diagnosis
- [ ] Confirm exact `syncContextIfNeeded()` trigger conditions — affects Bug 4 fix scope
- [ ] Run `pre-commit run --all-files` after each change
- [ ] Test Bug 4 on a physical device (TipKit behavior differs in Simulator)
