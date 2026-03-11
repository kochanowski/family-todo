# AGENTS.md

Last updated: 2026-03-11

This file is the practical source of truth for Codex and other AI agents working in this repository. Follow it precisely — when it contradicts the code, code wins; when in doubt, prefer simplicity and follow existing patterns.

---

## 1) Product North Star

Family To-Do is household task management in "home Agile lite" style:
- Minimum friction, clear ownership, shared household
- No gamification based on rankings or pressure
- Target question: **"Does this make it easier for two people to live together and remember tasks, without feeling controlled?"** — if not, simplify or reject

---

## 2) Core Design Principles (DO NOT VIOLATE)

1. **Shared-first** — Sharing is core, not an add-on. Household exists from the start.
2. **Simplicity over power** — Max 3-5 concepts users need. If a feature complicates onboarding/UX, simplify or remove it.
3. **No micromanagement** — No ratings, points, penalties, or pressure.
4. **Gentle nudges, not nagging** — Notifications are rare, predictable, and configurable.
5. **One source of truth** — Every task has clear status, owner, and change history.
6. **Theme support is mandatory** — Every new UI element must support the app's typography themes out of the box. New buttons, labels, section headers, sheet titles, toolbar titles, picker text, and other visible text controls must be wired to Retro/Paper theme fonts wherever SwiftUI allows native styling.

**Celebrations (Duolingo-style, NOT gamification):**
- Private micro-celebrations on task completion (toast messages, emoji)
- Household milestone moments (non-comparative)
- Max 1 surprise message per week via `CelebrationManager`
- No leaderboards, no streaks creating pressure, no "You vs Partner"
- Optional — can be disabled in Settings (`ThemeStore.celebrationsEnabled`)

---

## 3) Domain Model

| Entity | Key Fields | Notes |
|--------|-----------|-------|
| `Household` | name, ownerId, members[] | Single source of truth, supports guest/cloud modes |
| `Member` | userId, displayName, role (owner/member), isActive | CloudKit identity via `recordName` |
| `Task` | title, assigneeId, status (backlog/next/done), dueDate, areaId | WIP limit: max 3 per assignee in `.next` |
| `ShoppingItem` | title, quantity, unit, isBought, restockCount | Restock = bought items become suggestions |
| `BacklogCategory` | name | Long-term storage container |
| `BacklogItem` | title, notes, categoryId | For planning, not active tasks |

**Status flow**: backlog → next → done (no skipping, no going backwards arbitrarily)

**WIP Limit**: CRITICAL — max 3 tasks per assignee in `.next`. Enforced in `TaskStore`, not UI.

---

## 4) Architecture

### 4.1 Navigation

**Custom Floating Tab Bar** (`FloatingTabBar.swift`) — NOT native TabView:
- **Shopping** 🛒 — Shopping list with restock/suggestions
- **Tasks** ✓ — Active tasks (Next/Done + assignee filters)
- **Backlog** 📦 — Long-term categories + items
- **More** ⋯ — Settings, household, profile, member management

Tab bar uses Liquid Glass on iOS 26+ (`GlassEffectContainer` + `.glassEffect()`) with material fallback on iOS 17-25. Hides on keyboard show.

**CRITICAL**: `glassEffect()` must be the LAST modifier — no `.overlay` or `.shadow` after it.

### 4.2 Offline-First Data Flow

All stores follow the same 3-phase pattern:
1. **Load from SwiftData cache** (instant UI)
2. **If `.cloud` mode** → fetch from CloudKit, merge
3. **Writes**: optimistic UI update → SwiftData cache → CloudKit sync

SwiftData is source of truth. CloudKit is for sync only.

### 4.3 Stores

| Store | Responsibility |
|-------|---------------|
| `TaskStore` | Task CRUD, WIP limit enforcement, notifications |
| `ShoppingListStore` | Shopping CRUD, restock, suggestions |
| `BacklogStore` | Category + item CRUD |
| `HouseholdStore` | Household CRUD, CKShare, local-first exit flows, recovery guards |
| `MemberStore` | Member CRUD, role management |
| `ThemeStore` | Appearance (Light/Dark/System), celebrations/suggestions toggles |

### 4.4 Sync Modes

- **Guest Mode (`.localOnly`)** — SwiftData only, no CloudKit. Production households start empty; sample/test seeding is allowed only behind explicit UI-test launch arguments.
- **Cloud Mode (`.cloud`)** — Full CloudKit sync, requires Sign in with Apple.

### 4.5 CloudKit Constraints

- **`CKQuerySubscription` does NOT work in shared DB** (Apple QA1917) — use `CKDatabaseSubscription` instead.
- CloudKit schema: `Household`, `Member`, `Task`, `ShoppingItem`, `BacklogCategory`, `BacklogItem`
- Private DB: owner's data. Shared DB: household members' view.
- CloudKit schema changes: see `docs/2026-01-11_cloudkit-schema.md` and `cloudkit/schema/`

---

## 5) Development Environment

| Item | Detail |
|------|--------|
| Platform | Linux (Manjaro) — development machine |
| Build/Test | GitHub Actions (macOS runner) — `xcodebuild` is NOT available locally |
| Physical testing | iPhone 15, iOS 26.2.1 |
| Swift | 5.9+ |
| iOS target | 17+ (26+ for Liquid Glass) |
| CI | `.github/workflows/ios-ci.yml`, `.github/workflows/nightly.yml` |

**There is no `xcodebuild` locally.** Do not run `xcodebuild` commands on the local machine. All builds and test runs happen via GitHub Actions on push.

---

## 6) Linting and Code Quality

### SwiftLint via Docker (ALLOWED)

You are permitted to run SwiftLint using Docker for any Swift files:

```bash
docker run --rm -v "$PWD":"$PWD" -w "$PWD" ghcr.io/realm/swiftlint:latest lint
```

Preferred fast command (especially for CI-style local checks):

```bash
docker run --rm -v "$PWD":"$PWD" -w "$PWD" ghcr.io/realm/swiftlint:latest lint --quiet *
```

To lint specific files or paths:
```bash
docker run --rm -v "$PWD":"$PWD" -w "$PWD" ghcr.io/realm/swiftlint:latest lint FamilyTodo/Views/TasksView.swift
```

### Pre-commit Hooks

Always run before committing (after any code change):
```bash
pre-commit run --all-files
```

Checks include: YAML syntax, merge conflicts, large files, trailing whitespace, SwiftLint, SwiftFormat.

If SwiftFormat modifies files, run `pre-commit run --all-files` a second time to verify the formatted files also pass.

---

## 7) Git Workflow and Permissions

### What agents ARE allowed to do autonomously:
- `git add <specific-files>`
- `git commit -m "..."`
- `git push` (only when explicitly requested by the user, or when a standing instruction says to always push after commit)
- `gh run list`, `gh run view` (check CI status)
- Run `pre-commit run --all-files` and fix errors
- Run SwiftLint via Docker (see Section 6)

### What agents MUST NOT do without explicit user instruction:
- `git merge`, `git rebase`
- Force push, history rewrite
- Close or merge pull requests

### Post-push CI ownership (required when push happens)

If the task includes push:
1. Monitor GitHub Actions every ~60s until workflow completion.
2. If any job fails, inspect failed logs immediately.
3. Fix root cause in all repeated code patterns (not only one occurrence).
4. Commit + push fix and continue monitoring until all required jobs are green.

### Documentation-only changes

If a change touches **only documentation files** (`.md`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `STATUS.md`, `docs/`, etc.) and no Swift source files:
- Commit the change (`git add` + `git commit`)
- **Do NOT push** — wait for user to push manually

### Commit message format

```
<type>(<scope>): <short description>

- Point 1
- Point 2

[Optional: related context]
```

Types: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`

Example:
```
feat(tasks): add conversational filter chips for assignee filtering

- Add TaskFilter enum (all/mine/member)
- Add FilterChip component with Capsule shape
- Wire filteredActiveTasks computed property
```

---

## 8) After Implementation — Required Handoff Summary

**Every time you finish implementing a feature or fix**, you MUST print a brief summary in the following format before stopping:

```
## What I changed (Task IDs)
- [1-3 bullet points describing the changes made]
- [Include exact task IDs when applicable, e.g. P1.1, P1.2]

## Files changed
- `FamilyTodo/Views/TasksView.swift` — [what changed]
- `FamilyTodo/Stores/TaskStore.swift` — [what changed]

## What to test on the device
- [Step 1: specific action to take in the app]
- [Step 2: what to verify / what should happen]
- [Step 3: regression check — what existing flow to verify still works]
```

This applies to every code implementation, even small ones. Skip only for pure documentation changes.

Additionally, after each implementation handoff always include:
- **"What we changed"** (concise, high-signal summary)
- **"Regression checklist in app"** (specific taps/flows to validate)

---

## 9) Implementation Patterns

### Theme typography contract
- Every newly added visible UI element must be checked against `ThemeStore` typography before the task is considered complete.
- Apply theme fonts to all new buttons, labels, section headers, toolbar titles, sheet titles, and picker text wherever SwiftUI allows native styling.
- If a native SwiftUI control does not honor custom fonts (for example some Alerts, ContextMenus, or parts of native DatePicker/Picker rendering), leave the system font in place rather than building a custom replacement unless explicitly requested.
- Retro and Paper compatibility must be handled during the initial implementation, not as a later cleanup pass.
- New UI must be sanity-checked in `System`, `Retro Dark`, `Retro Light`, and `Paper`, including at least one narrow-screen layout.

### Onboarding / TipKit contract
- TipKit is contextual and sequential. On a given screen, show at most one onboarding tip at a time.
- Reset TipKit progress only on meaningful context changes (logout, user switch, household switch/leave/delete), not on every cold start of the same session.
- Prefer first-run guidance that teaches the next useful action; do not ship tips that promise behavior not implemented yet.

### Adding a new model (full chain)
1. Define struct in `Models/` (Codable, Identifiable)
2. Create `Cached*` SwiftData @Model with sync metadata
3. Add conversion: `init(from:)`, `update(from:)`, `toModel()`
4. Add to appSchema in `FamilyTodoApp.swift`
5. Implement CloudKit mapping in `CloudKitManager+Mapping.swift`
6. Create store in `Stores/` with `@Observable`
7. Add unit tests in `FamilyTodoTests/`

### Store write pattern (optimistic + rollback)
```swift
let snapshot = items
items.append(newItem)          // optimistic UI
saveToCache(newItem)
do {
    try await cloudKit.save(newItem)
} catch {
    items = snapshot           // rollback UI
    deleteFromCache(newItem.id)
    self.error = error
}
```

### Store delete/promotion pattern (Tombstone + Retry)
When deleting or promoting an item (e.g., Idea -> Task), DO NOT rollback the UI if the initial CloudKit delete fails.
1. Mark local record as `pendingDelete = true` (or delete locally).
2. Create the new item locally (if promoting).
3. Try CloudKit sync in a background task.
4. If CloudKit fails, keep the local tombstone and let `replayPendingMutations` handle the retry later.

### syncToCache pattern (Ghost Record Prevention)
When merging incoming CloudKit records with local SwiftData:
- ALWAYS check if the local record exists and has `pendingDelete == true`.
- If `pendingDelete == true`, IGNORE the incoming CloudKit record. Local tombstones must win against incoming server data until the pending delete is successfully pushed.

### SwiftData query pattern (avoid N+1)
```swift
// GOOD — one query, in-memory merge
let descriptor = FetchDescriptor<CachedTask>(
    predicate: #Predicate { cloudIDs.contains($0.id) }
)
let existing = try modelContext.fetch(descriptor)
let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

// BAD — query per item
for task in cloudTasks {
    let found = try modelContext.fetch(FetchDescriptor<CachedTask>(
        predicate: #Predicate { $0.id == task.id }
    ))
}
```

---

## 10) Key Files Reference

| File | Purpose |
|------|---------|
| `FamilyTodo/FamilyTodoApp.swift` | App entry, SwiftData schema, environment setup |
| `FamilyTodo/ContentView.swift` | Auth gate → MainAppView |
| `FamilyTodo/Views/TasksView.swift` | Tasks tab (1194 lines) |
| `FamilyTodo/Views/ShoppingListView.swift` | Shopping tab (937 lines) |
| `FamilyTodo/Views/BacklogView.swift` | Backlog tab (1036 lines) |
| `FamilyTodo/Views/MoreView.swift` | More tab / settings hub |
| `FamilyTodo/Views/ThemeStore.swift` | Theme presets + toggles |
| `FamilyTodo/Views/Components/FloatingTabBar.swift` | Custom glass tab bar |
| `FamilyTodo/Views/Components/ToastView.swift` | Toast notification component |
| `FamilyTodo/Models/LegacyStubs.swift` | ⚠️ Area, RecurringChore + stub views/stores |
| `FamilyTodo/Managers/CloudKitManager.swift` | Full CloudKit CRUD (66KB) |
| `FamilyTodo/Managers/CloudKitManager+Mapping.swift` | CKRecord ↔ Model mapping (522 lines) |
| `FamilyTodo/Managers/CloudKitSubscriptionManager.swift` | Push subscriptions |
| `FamilyTodo/Services/CelebrationManager.swift` | Completion message logic |
| `FamilyTodo/Services/UserSession.swift` | Session state, sync mode, householdID |
| `CLAUDE.md` | Claude-specific agent guidance (more detailed) |
| `FEATURES_claude.md` | Feature implementation plans (Parts 1-8) |
| `CLOUDKIT_claude.md` | CloudKit architecture analysis + recommendations |
| `docs/current/ROADMAP.md` | Active roadmap |
| `docs/2026-01-11_cloudkit-schema.md` | CloudKit schema reference |

---

## 11) Known Stubs and Technical Debt

Do not implement these without explicit instruction — they are intentionally deferred:

| Stub | Location | Status |
|------|----------|--------|
| Task Detail/Edit | `LegacyStubs.TaskDetailView` | "Coming Soon" |
| Recurring Chores | `RepetitiveTasksView`, `LegacyStubs` | Model exists, no store/UI |
| Areas/Rooms | `AreaStore` | Empty stub, `areaId` field exists for compat |
| Role Guardrails | `MemberStore` | No actual validation enforcement |

---

## 12) CI/CD and Branch Policy

- `.github/workflows/ios-ci.yml` — build + SwiftLint + schema gate
- `.github/workflows/nightly.yml` — extended tests
- TestFlight deploys trigger on: `main`, `features-and-testing`, `workflow_dispatch`, tags `v*`
- Schema gate must be green before TestFlight deploy

### CloudKit Schema Bootstrap (one-time, if needed)
If `Cannot create new type cloudkit.share` error appears:
1. CloudKit Console → Development → Private DB → Act As iCloud Account
2. Create custom zone → create Household record → Share Record (creates `cloudkit.share`)
3. Stop Acting As → Deploy Schema: Development → Production

### Quick CI diagnostics
```bash
gh run list --limit 5
gh run view <run-id> --json status,conclusion,jobs
gh run view <run-id> --log-failed
```

### CloudKit InviteToken security roles (operational check)

When InviteToken behavior changes or after schema/deploy operations, verify CloudKit Console security roles for `InviteToken`:
- `_creator` → Read, Write
- `_icloud` → Create, Read
- `_world` → Read

If Development schema loses these settings after deploy, re-apply them in CloudKit Console before closing the task.

---

## 13) Session Learnings (2026-03-04)

### Fast Boot contract (must preserve)
App launch must prioritize instant local UI:
1. Route to UI from local session/cache state immediately.
2. Do not block launch transition on CloudKit initialization or auth status checks.
3. Run CloudKit startup work in background tasks (auth refresh, replay pending mutations, initial cloud fetches).
4. User should see SwiftData-backed content instantly; cloud sync may update afterward.

### Optimistic UI & Tombstones (Ghost Record Prevention)
- UI must update immediately on mutations (e.g., Idea -> Task conversion) without waiting for CloudKit.
- If a CloudKit delete fails, we use the **"Keep task + tombstone"** policy. Do not rollback the UI. Keep the local `pendingDelete` flag and let background retries handle it.
- `syncToCache` MUST respect local tombstones. If a local record is marked `pendingDelete`, ignore incoming CloudKit updates for that record to prevent "ghost records" from reappearing.

### Silent Background Sync
- Do not use blocking full-screen spinners on tab switches (e.g., `TasksView`, `IdeasView`) if local data exists.
- Show local SwiftData immediately via `@Query`.
- CloudKit fetches should happen silently in the background and update the UI reactively.

---

## 14) Rules Summary (TL;DR)

1. English only in code, comments, and this file
2. Push only when explicitly requested or standing instruction allows it; then monitor GHA every ~60s until green
3. For docs-only changes: commit but do NOT push
4. Always run `pre-commit run --all-files` after code changes; fix until green
5. SwiftLint via Docker is allowed (prefer `lint --quiet *`) — see Section 6
6. No `xcodebuild` locally — Linux only; builds run on GitHub Actions
7. After every implementation: print handoff + regression checklist + task IDs (Section 8)
8. WIP limit is 3 tasks per assignee in `.next` — enforce in TaskStore
9. `glassEffect()` is always the last modifier — no modifiers after it
10. Every new UI element must ship with Retro/Paper theme font support wherever SwiftUI natively allows it
11. New UI should be checked in `System`, `Retro Dark`, `Retro Light`, and `Paper`, plus a narrow layout
12. TipKit must stay contextual/sequential: one tip per screen, reset only on real context change
13. If this file contradicts the code, code wins; if uncertain, ask

---

If this file contradicts current code, the code and latest agreements take precedence.
