# PROMPT FOR iOS SwiftUI AGENT - WOW POLISH + SHARED NOTIFICATIONS (POST-ONBOARDING ONLY)

You are a senior iOS engineer and SwiftUI developer working on an existing iOS app.
IMPORTANT: All onboarding and initial setup flows are already implemented and working.
Do NOT modify onboarding or the first-launch configuration.

Your task is to implement ONLY the new “wow” polish and the shared-list notification behavior described below,
starting from the point where the user is already inside the main app (tabs).

Constraints:
- Keep the CI/TestFlight pipeline working (do not break build/upload).
- Do not redesign screens; only add the specified UX polish and behaviors.
- Use CloudKit as the backend (already partially implemented). Extend it, do not replace it.
- Do not invent unrelated features. If anything is ambiguous, make minimal assumptions and document them in IMPLEMENTATION_NOTES.md.

---

## 1) GLOBAL WOW SYSTEM: HAPTICS + ANIMATION TOKENS
Create a small, centralized “interaction tokens” layer and use it across all screens.

### Haptics palette (use only these)
- selectionChanged: state changes (tab switch, segmented choices, toggles, selection)
- impactLight: add actions, checkbox taps, opening panels
- impactMedium: completion events (task completion, household created - already exists, don’t touch)
- notificationSuccess: milestone success (complete all tasks)
- notificationWarning: destructive confirmations (delete category with items)

Rules:
- Subtle usage only - no heavy impacts.

### Animation tokens
- Duration: 150-250ms
- Curves: easeOut or subtle spring (response ~0.35, damping ~0.85)
- Use animations only for semantically meaningful transitions:
  - list row insert/remove
  - check/completion transitions
  - move-to-restock
  - appearance crossfade

If you repeat these patterns, factor them into reusable helpers.

---

## 2) SHOPPING LIST: NOTES-STYLE RAPID ENTRY (CRITICAL)
Goal: The shopping list behaves like Apple Notes rapid entry.
The list is simple and dense, no icons/emojis in items.

### Required behavior
- Tap “Add item”:
  - insert a new editable row in the list (choose consistent position, preferably end)
  - auto-focus the text field (keyboard opens)
  - haptic: impactLight
- Press Return/Enter while editing:
  - if text is non-empty: commit/save item, immediately create the next empty editable row, move focus to it
  - if text is empty: exit rapid entry, remove empty row, dismiss keyboard
  - haptic: selectionChanged on successful commit
- Tap outside:
  - commit if non-empty; otherwise remove empty row and exit
- Ensure the focused row is always visible above the keyboard (auto-scroll).

### Row style
- Compact row height, minimal separators (Notes-like).
- Single-line text with truncation; tap existing row to edit inline.

---

## 3) SHOPPING LIST: RESTOCK AS HIDDEN CONTAINER (ALREADY DESIGNED, IMPLEMENT/REFINE)
Checked items move out of the main list and go into Restock.
Restock is accessed via a compact icon (basket/restock style). Items inside are hidden until tapped.

### Move-to-restock animation + haptics
When checkbox toggled ON:
1) checkbox fill (fast)
2) row slightly shrinks (scale 0.98), fades, slides down and disappears
3) restock icon pulses subtly (scale 1.0 -> 1.08 -> 1.0)
Haptics:
- impactLight on checkbox tap
- selectionChanged when row is moved

### Open restock
- Tap restock icon:
  - show sheet/expandable panel with blurred background
  - restock items appear with subtle staggered fade-in
  - haptic: impactLight

---

## 4) SHARED LISTS: CLOUDKIT REAL-TIME AWARENESS + NOTIFICATIONS (NEW)
Both Shopping List and Tasks are shared within a Household. CloudKit is already used; extend it.

### Core requirement
If I am shopping and another household member adds a new shopping item, I must get notified so I know something new was added.
This applies to Shopping List and (optionally per settings) Tasks.

### Implement CloudKit-based push notifications
- Use CloudKit subscriptions (or existing project CloudKit notification plumbing).
- Only implement what is needed for:
  - New Shopping item added by another user -> push notification
  - New Task added (optional), Task assigned to me (optional if assignment exists in spec)
- Do not replace CloudKit with a custom backend.

### Anti-spam rules
- Do not notify the author of the change (self-notify OFF).
- Aggregate notifications:
  - If multiple items are added within 60-120 seconds, send one notification:
    - “3 new items added to Shopping List”
- Keep it minimal and reliable.

### In-app awareness (when the app is open)
When new remote items arrive while the user is on Shopping List:
- show a small in-app banner/toast: “New items added (2)”
- tapping it scrolls to / highlights the new items briefly
- haptic: selectionChanged when the banner appears (once per batch)

The app must still update UI on remote changes even if push permissions are not granted (live updates when app is active).

---

## 5) TASKS: COMPLETION WOW (LIGHTWEIGHT)
Do not redesign Tasks. Add polish:
- Completing a task:
  - checkmark draw + row slides/fades into completed section (if present)
  - haptic: impactMedium
- Completing all tasks:
  - subtle success moment (header check animation)
  - haptic: notificationSuccess
  - only when truly all tasks are completed

---

## 6) BACKLOG: CATEGORY POLISH (LIGHTWEIGHT)
- Add category:
  - category expands in subtly
  - haptic: impactLight
- Delete category with tasks:
  - warning confirmation
  - haptic: notificationWarning
  - category collapses vertically on delete

---

## 7) MORE / SETTINGS: APPEARANCE TRANSITION POLISH
Appearance selection UI already exists (Light/Dark/System cards).
Add/ensure:
- selectionChanged haptic on tap
- smooth crossfade theme transition (~200ms) without flicker

Toggles:
- selectionChanged haptic

---

## 8) DELIVERY DISCIPLINE
- Keep changes scoped strictly to the above.
- Add/update `IMPLEMENTATION_NOTES.md` with:
  - what you changed
  - assumptions
  - how CloudKit notifications/subscriptions are implemented at high level
  - how to test: remote add -> in-app banner + push notification
- Before each push:
  - run `pre-commit run --all-files` and fix issues
- You may use `gh` to verify CI remains green and TestFlight upload still runs.

Definition of done:
- Rapid entry works (Add -> type -> Enter -> next row) and is smooth.
- Restock flow works with the specified animations and haptics.
- Remote additions via CloudKit produce in-app banner and push notifications (with aggregation and no self-notify).
- Tasks/Backlog/Appearance have the described polish.
- pre-commit passes and CI/TestFlight still works.
