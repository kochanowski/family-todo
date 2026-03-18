# AGENTS.md

Last updated: 2026-03-14

This file is the practical source of truth for coding agents working in this repository. Follow it closely. If it conflicts with the current code, the code wins.

---

## 1) Product North Star

HousePulse is household task coordination in “home Agile lite” form:
- shared-first,
- low-friction,
- clear ownership,
- no pressure mechanics.

Before implementing anything, ask:

**“Does this make it easier for two people living together to remember, plan, and coordinate without feeling controlled?”**

If not, simplify or reject it.

---

## 2) Core Product Rules

1. **Shared-first** — household collaboration is core, not an add-on.
2. **Simplicity over power** — keep the mental model small.
3. **No micromanagement** — no points, ratings, penalties, or pressure loops.
4. **Gentle nudges only** — reminders must be predictable, rare, and configurable.
5. **One source of truth** — every visible item must have a clear owner/state/history.
6. **Theme support is mandatory** — every new visible UI element must support theme typography out of the box wherever SwiftUI allows native styling.
7. **English only for v1.0** — new copy, labels, comments, and docs should stay in English unless the user explicitly asks otherwise.

### Celebration policy

Allowed:
- private micro-celebrations on completion,
- neutral household milestones,
- optional settings-controlled delight.

Not allowed:
- leaderboards,
- streak pressure,
- points,
- member-vs-member competition.

---

## 3) Current Product State

As of now, the repo already includes:
- Shopping, Tasks, Backlog, More
- Sign in with Apple
- Guest mode and CloudKit mode
- contextual TipKit onboarding
- Retro Dark, Retro Light, Paper, and System theme support
- local-first household exit flows
- hard reset button in Settings for local state reset

Currently deferred:
- `Live Shopping Mode / Last-Minute Alert` is postponed to **v2.0**
- recurring rotation flows remain deferred
- monetization is planned but not yet wired into schema/runtime

Current stability focus before MVP:
- multi-user household sync,
- join/bootstrap reliability,
- CloudKit shared graph consistency,
- on-device validation of real household collaboration.

---

## 4) Domain Model Truth

| Entity | Notes |
|---|---|
| `Household` | Core household metadata: `name`, `iconSymbol`, `ownerId`, timestamps |
| `Member` | **Real source of truth for membership**; includes `userId`, `displayName`, `role`, `isActive` |
| `Task` | Execution item with `status` in `backlog / next / done` |
| `ShoppingItem` | Shared shopping entry with bought/restock behavior |
| `ShoppingBundle` | Saved quick-add bundle for shopping |
| `BacklogCategory` | Long-term planning container |
| `BacklogItem` | Planning item that can be promoted into `Task` |

Important:
- `Household.members[]` in the model is **legacy/test-helper only**. Do not treat it as the authoritative membership source.
- Membership truth lives in `Member` records and cached `CachedMember`.
- `Task` items in `Tasks` must stay assigned.
- `BacklogItem` in `Ideas` may be unassigned.

### Status and WIP rules

- Canonical flow: `backlog -> next -> done`
- No arbitrary backward skipping without explicit UX
- WIP limit is **3 tasks per assignee in `.next`**
- WIP enforcement belongs in `TaskStore`, not only in UI

---

## 5) Architecture

### Navigation

The app uses a **custom floating tab bar**, not a stock `TabView` shell:
- Shopping
- Tasks
- Backlog
- More

For iOS 26+ it uses Liquid Glass. For older supported iOS versions it falls back to materials.

**Rule:** `glassEffect()` must be the last modifier.

### Offline-first data flow

All stores follow the same broad pattern:
1. Load SwiftData cache first for instant UI
2. If cloud mode is active, fetch CloudKit and merge
3. Mutations are local-first, then cached, then synced to CloudKit

SwiftData is the local source of truth for UI responsiveness.
CloudKit is sync/transport, not the first paint.

### Core stores

| Store | Responsibility |
|---|---|
| `TaskStore` | task CRUD, WIP limit, reminders |
| `ShoppingListStore` | shopping CRUD, restock, recent items |
| `ShoppingBundleStore` | saved bundles |
| `BacklogStore` | categories, ideas, promotions |
| `HouseholdStore` | household CRUD, create/join/leave/delete, recovery |
| `MemberStore` | member CRUD and household member state |
| `ThemeStore` | themes, typography, accent behavior |

---

## 6) CloudKit Rules

The app is CloudKit-based. Do not introduce Firebase/Supabase assumptions unless explicitly requested.

### Current CloudKit truths

- Owner data lives in the owner’s **private database/custom zone**
- Members consume shared data from the **shared database**
- `Member` records are required for household access and UI membership state
- Invite UI is **code-based** for users; QR encodes the invite code, not a visible share URL
- `CKQuerySubscription` is not usable for shared DB behavior; use `CKDatabaseSubscription`

### Scope rules

When touching CloudKit household graph data:
- never rely on stale mutable global scope assumptions,
- use the store’s current cloud context,
- keep references zone-aware,
- preserve shared-graph repair logic for legacy/mixed-zone households.

### Recovery rules

If a household is restored but the current user has no active `Member`:
- treat it as invalid recovery,
- clear local current-household selection,
- suppress stale recovery,
- route the app back to household setup.

Do not trap the user in a zombie household shell.

---

## 7) Onboarding, Auth, and Session Rules

### Display-name gating

For signed-in CloudKit users:
- iCloud auth alone is **not enough**
- create/join household requires a valid `confirmedMembershipDisplayName`

Do not silently fall back to `"Member"` for cloud create/join.

### TipKit contract

- TipKit is contextual and sequential
- show at most one onboarding tip per screen at a time
- reset TipKit only on meaningful context changes:
  - logout
  - user switch
  - household switch
  - leave/delete household
- do not reset TipKit on every cold start of the same session

### Hard reset

`Settings` now contains a visible `Hard Reset App` action.

It is local-only and should:
- clear SwiftData cache,
- clear app `UserDefaults`,
- clear onboarding/session state,
- clear household selection,
- clear saved display-name confirmation,
- sign the user out locally,
- route back to the first welcome screen.

Do not turn this into a remote CloudKit delete flow unless explicitly requested.

---

## 8) UI / Theme Rules

### Theme typography contract

Every new visible UI element must be checked against `ThemeStore` typography before the task is considered done.

Apply theme-aware fonts to:
- buttons,
- labels,
- toolbar items,
- section headers,
- sheet titles,
- picker text,
- visible form copy,
- CTA text,
- empty states,
- header chips/badges.

If a native SwiftUI component refuses custom fonts:
- keep system rendering,
- do not build a custom replacement unless requested.

### Required theme sanity checks

New UI must be checked in:
- `System`
- `Retro Dark`
- `Retro Light`
- `Paper`

Also verify at least one narrow layout.

### Toolbar rule

If the toolbar becomes crowded:
- move secondary actions into body content
- do not force awkward overflow menus unless the user explicitly wants that pattern

---

## 9) Store Mutation Rules

### Optimistic writes

Prefer local-first UI updates.

### Tombstone behavior

For delete/promotion flows:
- do not rollback UI just because CloudKit delete fails immediately
- keep tombstones/pending delete markers locally
- let background replay finish the remote cleanup

### Ghost-record prevention

When syncing from CloudKit into cache:
- pending local deletes must win over incoming server echoes
- never re-show a locally deleted/promoted idea just because a delayed cloud echo arrived

### Promotion rule

Promoting `BacklogItem -> Task` must:
1. create the task locally,
2. remove the idea locally immediately,
3. keep the backlog tombstone until cloud deletion completes.

The same logical item must never remain visible in both `Ideas` and `Tasks`.

---

## 10) Development Environment

| Item | Value |
|---|---|
| Local OS | Linux |
| Local builds | No `xcodebuild` available |
| CI builds | GitHub Actions on macOS |
| iOS target | 17+ |
| Physical testing | iPhone 15, iOS 26.2.1 |

### Build policy

- Do **not** run `xcodebuild` locally
- Use `pre-commit` locally
- Trust GitHub Actions for real Apple toolchain validation

Current `iOS CI` is effectively:
- SwiftLint
- build-only validation
- TestFlight deploy on selected branches

---

## 11) Linting and Quality

After every code change:

```bash
pre-commit run --all-files
```

If SwiftFormat rewrites files, run it again until clean.

SwiftLint via Docker is allowed:

```bash
docker run --rm -v "$PWD":"$PWD" -w "$PWD" ghcr.io/realm/swiftlint:latest lint --quiet *
```

---

## 12) Git / CI Workflow

### Autonomous actions allowed

- `git add <specific files>`
- `git commit`
- `git push` when explicitly requested or when the standing repo rule says to always push after code changes
- `gh run list`
- `gh run view`
- `pre-commit run --all-files`
- SwiftLint via Docker

### Never do without explicit instruction

- `git merge`
- `git rebase`
- force push
- history rewrite
- merging PRs

### Current standing workflow rule

For code changes in this repo:
1. implement,
2. run `pre-commit run --all-files`,
3. commit,
4. push,
5. monitor GHA until green,
6. report a structured handoff.

### Docs-only exception

If a change touches only documentation:
- commit it,
- **do not push**,
- let the user decide when to push docs.

### CI ownership after push

If push happens:
1. check Actions status,
2. wait for completion,
3. inspect logs on failure,
4. fix root cause,
5. push again,
6. repeat until green.

### Current TestFlight branches

As of now, `ios-ci.yml` includes TestFlight/CI handling for:
- `main`
- `develop`
- `rebuild/swiftui-clean-impl`
- `feature/continue-mvp`
- `appleid-login`
- `features-and-testing`
- `feature/cloudkit-fixes`
- `feature/next-features`
- `feature/multi-user-sync-fixes`

If a new long-lived feature branch must deploy like the previous one, update the workflow accordingly.

---

## 13) Required Final Handoff

For every implementation task, end with:

```md
## What I changed (Task IDs)
- ...

## Files changed
- ...

## What to test on the device
- ...
```

Also always include:
- `What we changed`
- `Regression checklist in app`

Skip this only for pure documentation changes.

---

## 14) Key File Map

| File | Purpose |
|---|---|
| `FamilyTodo/FamilyTodoApp.swift` | app entry, schema, root environment |
| `FamilyTodo/ContentView.swift` | app shell, bootstrap routing |
| `FamilyTodo/Views/ShoppingListView.swift` | Shopping tab |
| `FamilyTodo/Views/TasksView.swift` | Tasks tab |
| `FamilyTodo/Views/BacklogView.swift` | Ideas/Backlog tab |
| `FamilyTodo/Views/MoreView.swift` | More hub |
| `FamilyTodo/Views/SettingsView.swift` | Settings + hard reset |
| `FamilyTodo/Stores/HouseholdStore.swift` | create/join/leave/delete/recovery |
| `FamilyTodo/Stores/BacklogStore.swift` | ideas/categories/promotion |
| `FamilyTodo/Stores/TaskStore.swift` | tasks + WIP |
| `FamilyTodo/Managers/CloudKitManager.swift` | main CloudKit CRUD/recovery logic |
| `FamilyTodo/Managers/CloudKitManager+Mapping.swift` | CKRecord mapping |
| `FamilyTodo/Managers/CloudKitSubscriptionManager.swift` | remote-change subscriptions |
| `FamilyTodo/Services/UserSession.swift` | session mode, display name, household selection |
| `FamilyTodo/Services/AppTips.swift` | TipKit setup and progress |
| `TODO.md` / `TODO_DETAILS.md` | current roadmap and implementation plans |

---

## 15) Known Deferred / Stub Areas

Intentionally deferred unless explicitly requested:
- recurring chores full productization
- areas/rooms beyond compatibility fields
- monetization schema/runtime wiring
- Live Shopping Mode (moved to v2.0)

---

## 16) TL;DR

1. Shared-first, low-friction household app
2. `Member` records are the real membership source of truth
3. Signed-in users need confirmed display name before create/join
4. New UI must support theme fonts from day one
5. Ideas can be unassigned; Tasks cannot
6. Local-first UI, tombstones for delete/promotion
7. TipKit is sequential and context-reset only
8. No local `xcodebuild`
9. After code changes: `pre-commit -> commit -> push -> monitor GHA`
10. Docs-only: commit but do not push

If in doubt, follow the code, prefer the existing pattern, and keep the product simpler rather than more powerful.
