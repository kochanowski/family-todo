# Onboarding Flow — UI/UX Analysis & Improvement Plan

_HIG review · iOS 17+ · HousePulse · 2026-03-17_

---

## Current flow

```
App launch (first time)
│
├─ [1] OnboardingCarouselView   (.onboarding)
│       4 slides, Aurora animated background → "Get Started"
│
├─ [2] SignInView                (.auth)
│       Logo + "Sign in with Apple" / "Continue without account"
│
└─ [3] OnboardingView            (.householdSetup)
        "Create Household" + "Join Household"
```

State machine: `OnboardingState.currentState` (`LaunchState`) — persisted via `@AppStorage`.

---

## Screen 1 — OnboardingCarouselView

### Current slides (4)

| # | Icon | Title | Subtitle |
|---|---|---|---|
| 1 | `cart.fill` | Smart Shopping | Build and restore grocery lists quickly with one-tap recent purchases. |
| 2 | `checklist` | Clear Your Mind | Turn home chaos into clear, assignable tasks everyone can see. |
| 3 | `slider.horizontal.3` | Make It Yours | Pick the theme and workflow that feels right for your household. |
| 4 | `person.2.fill` | Better Together | Invite members and keep shopping, tasks, and ideas in sync. |

### ✅ What works

- **Aurora animated background** — 3 orbiting gradient blobs with `.ultraThinMaterial` overlay, cross-dissolve between palettes per slide. Memorable, differentiating.
- **Glassmorphic icon container** — `.ultraThinMaterial`, `cornerRadius: 32`, shadow — modern, depth-conveying per HIG Depth principle.
- **Haptic per slide** — `HapticManager.selection()` — correct HIG pattern.
- **"Get Started" only on last slide** — progressive disclosure, animation `.opacity + .move(edge: .bottom)`.
- **Theme fonts used** — `themeStore.font(for:)` throughout.

### ⚠️ Issues

| # | Severity | Issue | Fix |
|---|---|---|---|
| 1 | 🔴 High | `UIScreen.main.bounds.height * 0.5` — deprecated iOS 16+, breaks on Stage Manager / iPad | Use `GeometryReader` or `.containerRelativeFrame` |
| 2 | 🟠 Medium | No skip button on early slides — users who know the app are trapped in 4-slide flow | Add "Skip" in top-right after slide 1 |
| 3 | 🟠 Medium | Page dots use `Color.primary / Color.secondary` directly — not themed | Use `themeStore.contentPrimaryColor` |
| 4 | 🟡 Low | "Get Started" button uses hardcoded `.blue` fill — ignores theme accent | Use `Color.accentColor` or `themeStore.accentTabColor` |
| 5 | 🟡 Low | `Spacer().frame(height: 40/60)` — magic numbers, not adaptive to Dynamic Type XL | Use relative padding |
| 6 | 🟡 Low | No `.accessibilityLabel` on page indicator dots | Add `"Slide \(n) of \(total)"` |

---

## Screen 2 — SignInView

### ✅ What works

- `ASAuthorizationAppleIDButton` via `UIViewRepresentable` — correct HIG-mandated button.
- Logo uses `Color.accentColor` — theme-adaptive. `.accessibilityHidden(true)` on decorative logo.
- "Continue without account" is clearly secondary (`.bordered` vs absent `.borderedProminent`).
- `guestFootnote` text clarifies local-only mode.
- `ProgressView("Signing in...")` during `.authenticating` — correct pattern.

### ⚠️ Issues

| # | Severity | Issue | Fix |
|---|---|---|---|
| 1 | 🟡 Info | "Debug" button visible in production | Intentional for dev phase — remove before release |
| 2 | 🟠 Medium | `ASAuthorizationAppleIDButton` uses hardcoded `.black` style — ignores Dark Mode | Use dynamic style or `.whiteOutline` in light mode |
| 3 | 🟠 Medium | `frame(maxWidth: 280)` — too narrow on wide iPad | Use `.infinity` + `.padding(.horizontal, 40)` |
| 4 | 🟡 Low | Error state: "Try again" + "Open diagnostics" side-by-side `HStack` can clip on narrow devices | Stack vertically or `ViewThatFits` |

---

## Screen 3 — OnboardingView (Household Setup)

### ✅ What works

- Clear hierarchy: icon → title → subtitle → CTA buttons.
- Guest-mode text below disabled "Join" — explains the constraint.
- `CreateHouseholdSheet` auto-fills name from display name.
- `interactiveDismissDisabled(isCreating)` — prevents dismissal mid-operation.
- `DisplayNameValidator.validate()` gating enforced.

### ⚠️ Issues

| # | Severity | Issue | Fix |
|---|---|---|---|
| 1 | 🔴 High | No back / "not now" escape for cloud users — trapped at householdSetup | Add "Later" / escape path |
| 2 | 🟠 Medium | Wraps in `NavigationStack` but never pushes — empty nav chrome | Remove outer `NavigationStack` |
| 3 | 🟠 Medium | "Join Household" disabled for guests with no CTA to upgrade to iCloud | Add "Sign in to join →" route |
| 4 | 🟡 Low | `Form` without `.scrollDismissesKeyboard(.interactively)` — abrupt keyboard dismissal | Add modifier |

---

## Cross-cutting issues

| # | Severity | Issue |
|---|---|---|
| A | 🟠 Medium | No animation between auth states inside `SignInView` — jarring transitions |
| B | 🟠 Medium | `HouseholdSetupLoadingView` is a plain spinner with no timeout/retry |
| C | 🟡 Low | All 3 screens use `Spacer()` heavily — not adaptive to landscape or iPad split view |

---

## Proposed carousel content — 5 slides

### Rationale

Current 4 slides have vague benefits ("Clear Your Mind", "Make It Yours"). The carousel is the **only moment before auth** where users learn what the app does. Each slide should map to an actual app feature.

### Proposed slides

| # | Icon | Title | Subtitle | Maps to |
|---|---|---|---|---|
| 1 | `house.and.flag.fill` | Your Home, Organized | One shared space for everything your household needs to remember. | Overall value prop |
| 2 | `cart.fill` | Smart Shopping | Shared lists, one-tap restock, and saved bundles for recipes or weekly essentials. | Shopping tab + Bundles |
| 3 | `checklist` | Tasks That Get Done | Assign who does what, set due dates, and track progress — no nagging needed. | Tasks tab |
| 4 | `lightbulb.fill` | Ideas for Later | A parking lot for future plans. When you're ready, promote an idea into a task. | Ideas/Backlog tab |
| 5 | `person.2.fill` | Better Together | Invite your household. Changes sync instantly to every phone. | Sync/collaboration |

### Icon alternatives considered

| Slot | Current pick | Alternative | Verdict |
|---|---|---|---|
| 1 | `house.and.flag.fill` | `house.fill` | `house.and.flag.fill` — more visually interesting |
| 2 | `cart.fill` | `basket.fill` | `cart.fill` — universally recognized |
| 3 | `checklist` | `checkmark.circle.badge.person.crop` | `checklist` — simpler, cleaner at 48pt |
| 4 | `lightbulb.fill` | `archivebox.fill`, `tray.and.arrow.down.fill` | `lightbulb.fill` — more inviting for "ideas" |
| 5 | `person.2.fill` | `shared.with.you`, `icloud.fill` | `person.2.fill` — warmer, human |

---

## Proposed Aurora palettes — 5 palettes (currently 3)

### Current palettes

| Palette | Light colors | Vibe |
|---|---|---|
| `.calmSync` | Indigo-300, Blue-300, Sky-200 | Calm, tech |
| `.freshAction` | Emerald-300, Teal-300, Green-100 | Fresh, active |
| `.warmDreams` | Orange-300, Rose-300, Amber-200 | Warm, home |

### Proposed mapping

| Slide | Title | Palette | Vibe |
|---|---|---|---|
| 1 | Your Home, Organized | 🔵 `.calmSync` (existing) | Calm intro |
| 2 | Smart Shopping | 🟢 `.freshAction` (existing) | "Go", active list |
| 3 | Tasks That Get Done | 🟠 `.warmDreams` (existing) | Routine, home |
| 4 | Ideas for Later | 🟣 `.dreamerPurple` (**NEW**) | Creativity, planning |
| 5 | Better Together | 🩵 `.togetherCyan` (**NEW**) | Connection, sync |

### New palette colors

**`.dreamerPurple`**:

| Mode | Color 1 | Color 2 | Color 3 |
|---|---|---|---|
| Light | `#C4B5FD` (Violet-300) | `#DDD6FE` (Violet-200) | `#E9D5FF` (Purple-200) |
| Dark | `#4C1D95` (Violet-900) | `#581C87` (Purple-900) | `#3B0764` (Fuchsia-950) |

**`.togetherCyan`**:

| Mode | Color 1 | Color 2 | Color 3 |
|---|---|---|---|
| Light | `#67E8F9` (Cyan-300) | `#A5F3FC` (Cyan-200) | `#99F6E4` (Teal-200) |
| Dark | `#164E63` (Cyan-900) | `#134E4A` (Teal-900) | `#0E7490` (Cyan-700) |

---

## Implementation plan

### Files to modify

1. **`FamilyTodo/Views/Onboarding/AuroraBackground.swift`**
   - Add `.dreamerPurple` and `.togetherCyan` cases to `AuroraPalette`
   - Add light/dark color arrays for each
   - Update `AnimatedAuroraBackground.body` — add 2 more `AuroraBackground` layers with opacity
   - Update `palette` computed property — map 5 slides

2. **`FamilyTodo/Views/Onboarding/OnboardingCarouselView.swift`**
   - Replace `slides` array with 5 new slides (titles, subtitles, icons)

### Files unchanged

- `OnboardingState.swift` — no state changes needed
- `OnboardingView.swift` — separate screen, not part of carousel
- `SignInView.swift` — separate screen

### Verification

- Run `pre-commit run --all-files`
- Visual check in Xcode Preview for all 5 palettes (existing `#Preview` blocks + 2 new)
- Verify on device: all 4 themes × 5 slides
