# CLAUDE.md

Last updated: 2026-03-14

This file is a Claude-oriented working guide for this repository. It is intentionally practical and shorter than historical planning docs. If it conflicts with the code, the code wins.

---

## 1) What This App Is

HousePulse is a shared household organizer:
- shared shopping list,
- active tasks with clear ownership,
- long-term ideas/backlog,
- simple household collaboration.

It is **not** a mini Jira, productivity pressure app, or gamified accountability tool.

### Product question to ask before coding

**Does this reduce friction between people living together without making anyone feel monitored or pressured?**

If the answer is unclear, simplify.

---

## 2) Non-Negotiable Product Rules

1. Sharing is core, not optional.
2. Simplicity beats flexibility.
3. No pressure mechanics: no points, no rankings, no punishment loops.
4. Notifications must be useful, not spammy.
5. Ownership must stay clear.
6. New UI must support Retro/Paper typography wherever SwiftUI allows native styling.
7. English only for v1.0-facing copy unless explicitly asked otherwise.

---

## 3) Current State of the App

Implemented today:
- Shopping, Tasks, Backlog, More
- Sign in with Apple
- Guest mode and CloudKit mode
- contextual TipKit onboarding
- Retro Dark / Retro Light / Paper / System themes
- local-first household leave/delete flows
- Settings-based local hard reset

Still in flight before MVP:
- multi-user shared household sync hardening
- join/bootstrap reliability on physical devices
- CloudKit shared graph repair/recovery edge cases

Deferred:
- Live Shopping Mode moved to **v2.0**
- recurring/rotation flows still deferred
- monetization not wired yet

---

## 4) Architectural Truths

### App shell

The app uses a custom floating tab bar, not a stock `TabView` navigation architecture.

Tabs:
- Shopping
- Tasks
- Backlog
- More

### Data flow

All major features are offline-first:
1. load SwiftData cache,
2. merge CloudKit in background,
3. write locally first,
4. sync CloudKit after.

SwiftData gives instant UI.
CloudKit provides sync.

### Core stores

- `HouseholdStore`
- `MemberStore`
- `TaskStore`
- `ShoppingListStore`
- `ShoppingBundleStore`
- `BacklogStore`
- `ThemeStore`

Business rules belong in stores, not in view-only validation.

---

## 5) Domain Truths You Must Preserve

### Membership

`Member` records are the real source of truth for household membership.

Important:
- `Household.members[]` exists in the model as legacy/test-helper compatibility
- do **not** build new logic around it
- real access and sync assumptions should rely on `Member`

### Task assignment

- `Ideas` / `BacklogItem` may be unassigned
- `Tasks` must remain assigned
- do not add `Unassigned` back into `Tasks` edit flows

### WIP limit

- max **3** active `.next` tasks per assignee
- enforced in `TaskStore`

### Promotion rule

Promoting an idea into a task must:
1. create the task locally,
2. remove the idea locally immediately,
3. keep the local tombstone until cloud delete finishes,
4. never leave the same logical item visible in both places.

---

## 6) CloudKit Rules

This app uses CloudKit, not Firestore.

### Household graph basics

- owner data originates from the owner private DB/custom zone
- household members read shared data via shared DB
- invites exposed to users are code-based
- QR joins should flow through the same code path

### Membership / routing rule

If a household is “restored” but the current user has no active `Member`, that is an invalid zombie state:
- clear current household selection,
- suppress stale recovery,
- route back to household setup.

Do not leave the user trapped in a blank household shell.

### Query/subscription constraints

- `CKQuerySubscription` is not the tool for shared DB updates
- use `CKDatabaseSubscription`
- keep reference predicates CloudKit-safe
- preserve zone-aware references when touching household graph records

---

## 7) Auth / Onboarding Rules

### Display name gating

Being signed into iCloud is not enough.

For cloud household create/join:
- require a valid `confirmedMembershipDisplayName`
- do not silently fall back to `"Member"`

### TipKit

TipKit is:
- contextual,
- sequential,
- one-tip-per-screen,
- reset only on real context changes.

Do not add tips that overlap, compete, or promise not-yet-shipped behavior.

### Hard reset

`Settings` contains `Hard Reset App`.

It is local-only and must:
- clear SwiftData,
- clear app defaults,
- clear saved display name confirmation,
- clear onboarding flags,
- clear household selection,
- sign out locally,
- return to the first welcome screen.

Do not make it delete remote CloudKit data unless explicitly requested.

---

## 8) UI / Theme Rules

### Typography contract

Every newly added visible text element must be reviewed for theme support:
- buttons,
- labels,
- toolbar items,
- section headers,
- sheet titles,
- form copy,
- picker text,
- empty states.

Where SwiftUI refuses theme fonts for a native component, leave the system font rather than creating a custom control by default.

### Required visual sanity checks

Check new UI in:
- System
- Retro Dark
- Retro Light
- Paper

Also check at least one narrow layout.

### Toolbar rule

If the top bar becomes crowded:
- keep it native and readable,
- move secondary actions into the content body.

---

## 9) Mutation Patterns to Preserve

### Optimistic UI

Prefer local-first UI updates.

### Tombstones

For delete/promotion:
- do not undo the UI just because the first cloud delete failed
- keep a tombstone and replay in background

### Ghost prevention

Incoming cloud data must not resurrect a local item marked pending delete.

If you touch merge logic, preserve this rule carefully.

---

## 10) Local Development Reality

- Local machine is Linux
- `xcodebuild` is not available locally
- real Apple builds happen in GitHub Actions on macOS

Use locally:
- `pre-commit run --all-files`
- SwiftLint via Docker when helpful

Do **not** pretend local Xcode validation is available.

---

## 11) CI / Git Workflow

For code changes in this repo, the standing workflow is:
1. implement,
2. run `pre-commit run --all-files`,
3. commit,
4. push,
5. monitor GitHub Actions until green,
6. report a structured handoff.

For docs-only changes:
1. commit,
2. do **not** push.

Never autonomously:
- merge branches,
- rebase,
- force push,
- rewrite history.

---

## 12) Required Handoff Format

For implementation work, always finish with:

```md
## What I changed (Task IDs)
- ...

## Files changed
- ...

## What to test on the device
- ...
```

Also include:
- `What we changed`
- `Regression checklist in app`

Skip this only for docs-only tasks.

---

## 13) Most Important Files

| File | Why it matters |
|---|---|
| `FamilyTodo/FamilyTodoApp.swift` | app entry, schema, environment wiring, reset helper |
| `FamilyTodo/ContentView.swift` | routing/bootstrap between onboarding and main app |
| `FamilyTodo/Services/UserSession.swift` | auth/session/display-name/household selection |
| `FamilyTodo/Stores/HouseholdStore.swift` | create/join/leave/delete/recovery |
| `FamilyTodo/Stores/BacklogStore.swift` | ideas/promotion/delete/tombstones |
| `FamilyTodo/Stores/TaskStore.swift` | task rules and WIP enforcement |
| `FamilyTodo/Managers/CloudKitManager.swift` | CloudKit CRUD and migration/recovery logic |
| `FamilyTodo/Managers/CloudKitManager+Mapping.swift` | record mapping and references |
| `FamilyTodo/Managers/CloudKitSubscriptionManager.swift` | remote sync triggers |
| `FamilyTodo/Views/ShoppingListView.swift` | Shopping |
| `FamilyTodo/Views/TasksView.swift` | Tasks |
| `FamilyTodo/Views/BacklogView.swift` | Ideas/Backlog |
| `FamilyTodo/Views/SettingsView.swift` | Settings + reset surface |
| `TODO.md` / `TODO_DETAILS.md` | active planning source |

---

## 14) Things Not to “Improve” Without Being Asked

Do not spontaneously:
- replace the current architecture,
- add new analytics frameworks,
- add localization work,
- add monetization scaffolding beyond explicitly requested schema prep,
- revive Live Shopping Mode,
- invent new onboarding flows that compete with current TipKit sequencing,
- remove the hard reset button.

---

## 15) Short Version

- Shared household app, not a pressure app
- `Member` is the real membership source of truth
- `Ideas` can be unassigned; `Tasks` cannot
- New UI must support theme fonts immediately
- Local-first first paint, CloudKit in background
- Tombstones prevent ghost records
- Display name is required before cloud create/join
- No local `xcodebuild`
- Code changes: `pre-commit -> commit -> push -> watch GHA`
- Docs-only: commit but do not push

When uncertain, follow the existing code path and prefer the smaller, safer change.
