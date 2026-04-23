# HousePulse Repo Status

Last updated: 2026-03-14

## Current repo snapshot

### Branches
- `main` currently points to `09003e2`
- active stabilization branch is `feature/multi-user-sync-fixes`
- this branch contains additional CloudKit / onboarding / recovery work that is **not fully validated yet**

### Overall state
- Core app structure exists and is usable: `Shopping`, `Tasks`, `Ideas`, `More`
- Theme system is broad and active: `System`, `Retro Dark`, `Retro Light`, `Paper`
- TipKit onboarding is implemented and contextual
- CloudKit household sharing exists, but multi-user reliability is still under active stabilization
- Recent recovery/reset work is only **partially successful** and must not be treated as finished

---

## What is currently working

### Main app structure
- Main tabs render and route correctly
- Local-first store pattern exists across core features
- Guest mode and signed-in cloud mode both exist
- `Ideas -> Tasks` promotion flow exists
- Settings, household management, and theme switching are implemented

### Theme / UI system
- Broad Retro/Paper typography support has been added across many screens
- `Retro Light` exists as a supported theme
- Empty states, Settings, and onboarding have had multiple typography passes

### Onboarding / session architecture
- Launch routing distinguishes onboarding, auth, household setup, and main app
- Signed-in users are supposed to require a confirmed display name before cloud household setup
- A visible `Hard Reset App` action now exists in `Settings`

### CloudKit architecture
- App uses CloudKit, not Firestore / Supabase
- `Member` records are the real household membership source of truth
- Multi-user sync hardening work has been added on the feature branch:
  - explicit scope usage in stores
  - shared/private subscription handling
  - shared graph repair work
  - code-based join flow cleanup
  - zombie-household recovery guards

### CI / delivery
- `pre-commit` is part of the standard workflow
- GitHub Actions build / lint / TestFlight deploy pipeline is active
- `feature/multi-user-sync-fixes` is wired into `ios-ci.yml` and deploys to TestFlight

---

## What is currently NOT reliable / NOT finished

### 1) Full fresh-start reset is still broken

This is the most important current blocker from the latest round of changes.

Observed behavior from real testing:
- after using `Hard Reset App`, the app still does **not** behave like a true fresh install
- after sign-in, the app still skips the “What is your name?” step
- user can create a new household while the old confirmed display name is still effectively remembered

What this means:
- the latest reset/onboarding fix is **not done**
- the current branch must not claim that full local reset + fresh first-run onboarding is working

Most likely practical interpretation:
- some part of the signed-in profile/display-name recovery path still restores enough state to bypass the intended name prompt
- the visible reset button is present, but the full session/name reset contract is not yet truly enforced end-to-end

### 2) Multi-user household sync is still under stabilization

This branch contains major sync work, but it is still an active stabilization branch, not a fully closed problem.

Previously observed real-device issues included:
- household name/icon visible, but missing members/tasks/shopping/ideas for the joined user
- newly created shared data disappearing
- inconsistent remote refresh
- shared graph repair edge cases

Several fixes were added for these, but this branch still requires more physical-device validation before it can be called finished.

### 3) Household owner bootstrap after reset/reinstall needs re-validation

Related to the reset issue:
- owner/member bootstrap after a “fresh” start is still not trustworthy enough
- this must be re-tested from scratch after the reset/name problem is fixed

### 4) Recent sync/recovery fixes should be treated as partially landed

The code contains significant work for:
- join-by-code cleanup,
- zombie-household escape,
- reference predicate safety,
- mixed-zone repair,
- member validation,
- hard reset.

But the user-reported behavior shows that at least part of this series is still incomplete in practice.

---

## Latest change series on `feature/multi-user-sync-fixes`

### `e3305af`
`fix(sync): harden household multi-user refresh`

Intent:
- improve household/member refresh after remote changes

### `17244bd`
`fix(sync): stabilize shared household multi-user sync`

Intent:
- start deeper multi-user sync stabilization work

### `5734afb`
`fix(sync): update join sheet follow-up`

Intent:
- join-flow follow-up/fix after first sync pass

### `0d8bb96`
`fix(sync): harden mixed-zone shared graph repair`

Intent:
- handle shared household graphs spread across legacy/private/custom zones more safely

### `01a977c`
`fix(sync): stabilize code-based household join and shared graph loading`

Intent:
- simplify join UI to code flow
- improve shared graph bootstrap after join

### `1bae93a`
`fix(onboarding): enforce confirmed display names for household setup`

Intent:
- require confirmed display name before create/join household
- ensure owner member bootstrap during household creation

### `5f5f436`
`fix(sync): recover from zombie households and add hard reset`

Intent:
- avoid trapping users in stale households without membership
- add a local hard reset utility and settings action

### `c83eedb`
`fix(onboarding): expose hard reset and prevent idea ghosting`

Intent:
- make hard reset visible outside DEBUG
- try to force full onboarding reset
- keep promoted ideas from reappearing in `Ideas`

### `7b4f886`
`docs(agent-guides): refresh AGENTS and rewrite CLAUDE`

Intent:
- documentation refresh only

---

## Important reality check for the latest changes

### What was implemented in code
- `Hard Reset App` button was added visibly in `Settings`
- local reset utility clears SwiftData and app defaults
- onboarding reset method was made callable in all builds
- signed-in display-name gating was added
- owner bootstrap validation and zombie recovery guards were added

### What is still not true in real behavior
- reset still does **not** reliably force the name prompt
- creating a new household after reset still reuses previously remembered name context in practice

### Conclusion
- the reset/onboarding series is **partially implemented but functionally unresolved**
- STATUS must treat it as broken until re-tested successfully on device

---

## Where the next debugging pass should start

### Start here first
1. **Reproduce the reset bug from scratch**
   - use `Hard Reset App`
   - sign in again
   - verify exactly which screen appears first
   - inspect whether `confirmedMembershipDisplayName` is rehydrated from a path other than plain `UserDefaults`

2. **Trace signed-in name restoration**
   - start with `UserSession`
   - verify:
     - `preferredDisplayName`
     - `hasConfirmedDisplayName`
     - `confirmedMembershipDisplayName`
     - auth-state restoration after sign-in

3. **Verify onboarding routing after reset**
   - inspect:
     - `OnboardingState`
     - `FamilyTodoApp.swift`
     - `SignInView`
     - `ContentView`
   - confirm which component is skipping the required display-name step

4. **Only after reset/name gating is truly fixed**
   - re-test owner bootstrap for freshly created household
   - then continue multi-user sync validation

### Files to inspect first
- `FamilyTodo/Services/UserSession.swift`
- `FamilyTodo/Services/OnboardingState.swift`
- `FamilyTodo/FamilyTodoApp.swift`
- `FamilyTodo/Views/SignInView.swift`
- `FamilyTodo/Views/SettingsView.swift`
- `FamilyTodo/Stores/HouseholdStore.swift`

---

## Recommended immediate priority order

1. Fix the real “fresh start” reset path so it truly asks for the user’s name again
2. Re-validate owner/member bootstrap after fresh household creation
3. Resume physical-device testing of multi-user sync
4. Only then decide which sync bugs are still branch blockers before merge

---

## Current confidence level by area

| Area | Confidence |
|---|---|
| Main tabs / general UI | High |
| Theme / typography system | High |
| TipKit contextual onboarding | Medium |
| Local-first store architecture | High |
| Household create/join/leave edge cases | Medium |
| Multi-user sync on physical devices | Low to Medium |
| Fresh reinstall / hard reset flow | Low |

---

## Summary

The repo is far ahead of the old February status, but the latest recovery/onboarding work must be treated honestly:
- many fixes were implemented,
- CI is green,
- but the latest reset/name-gating behavior is still broken in real testing.

The next task should start from the reset/onboarding path, not from more UI polish or new features.
