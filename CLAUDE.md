# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Family To-Do App** - An iOS application designed for shared household task management. The core value proposition is providing a single source of truth for household tasks with natural sharing, minimal cognitive overhead, and conflict reduction through clear assignments and gentle reminders.

**Critical Principle**: This is NOT a project management tool like Jira. It's "home Agile lite" - designed to help people remember and plan without micromanagement, scoring, or pressure.

## Product North Star

Before implementing any feature, ask: **"Does this decision make it easier for two people to live together and remember household tasks, without feeling controlled or pressured?"**

If the answer isn't clearly "yes" - simplify or reject the decision.

## Core Design Principles (DO NOT VIOLATE)

1. **Shared-first**: Sharing is core, not an add-on. Household (shared space) exists from the start.
2. **Simplicity over power**: Max 3-5 concepts users need to understand. If a feature complicates onboarding/UX, simplify or remove it.
3. **No micromanagement**: No ratings, points, penalties, or pressure.
4. **Gentle nudges, not nagging**: Notifications are rare, predictable, and configurable.
5. **One source of truth**: Every task has clear status, owner, and change history.

## Domain Model

### Core Entities

**Household**
- Shared data space containing members, tasks, shopping items, and backlog
- Single source of truth for the family
- Supports guest mode (local-only) and cloud sync mode

**Members**
- Users assigned to Household
- Minimal roles: Owner, Member
- Each member has "My Tasks" perspective

**Tasks**
- Minimal fields:
  - `title` (verb + effect)
  - `assignee` (who does it)
  - `status`: backlog, next, done
  - `due_date` (optional)
  - `type`: one-off or recurring
  - `areaId` (optional, legacy field)

**Shopping Items**
- Shared shopping list for household
- Fields: title, quantity, unit, isBought
- Supports restock functionality (bought items become suggestions)

**Backlog Categories**
- Long-term storage containers for ideas and projects
- Replaces old Areas/Boards concept
- Contains multiple Backlog Items

**Backlog Items**
- Individual items within a category
- For storage and future planning, not active daily tasks
- Can be promoted to Tasks when ready to work on

## Workflow Patterns

### Minimal Kanban
Statuses only:
- Backlog
- Next (Now)
- Done

### WIP Limit
**CRITICAL**: Each user can have max 3 tasks in "Next". This is a key focus mechanism.

### Definition of Done
Tasks must be formulated to be unambiguously checkable. Always promote precise naming.

### Priorities (No Numbers)
Only use:
- Today
- This Week
- Someday

## Relational Mechanics

**Proposal vs Assignment**
- Tasks can be added as "proposals"
- Other person can accept them to their "Next"
- No automatic assignment without consent (unless user explicitly sets it)

**Neutrality**
- App doesn't "judge" or compare users

## Gentle Celebration (Not Gamification)

**CRITICAL**: Traditional gamification (points, leaderboards, streaks) creates competition and pressure - exactly what we're avoiding.

**What we DON'T do:**
- ❌ Points, badges, or scores
- ❌ Leaderboards or comparisons between members
- ❌ Streak counters that create pressure
- ❌ "You vs Partner" competition mechanics

**What we DO (Duolingo-style gentle rewards):**
- ✨ **Micro-celebrations**: Simple, playful acknowledgment when completing tasks
  - "Nice! Kitchen is sparkling ✨"
  - "Bathroom sorted! 🧼"
  - Emoji based on area/task type
- 🎉 **Milestone moments**: Celebrate shared achievements (non-comparative)
  - "10 tasks done this week! Home is happy 🏡"
  - "First full week with empty Next! Take a break ☕"
- 📊 **Neutral progress**: Show household progress, not individual scores
  - "8/12 weekly tasks done"
  - "Living room: all sorted ✓"
- 🌟 **Occasional surprises**: Rare, delightful moments (not predictable rewards)
  - After completing all recurring chores: "Weekend earned! 🎈"
  - Random positive messages (max once per week)

**Design principles:**
1. Celebrations are **private** (shown to person who completed task, not broadcast to partner)
2. **No pressure**: Optional, can be disabled in settings
3. **Relationship-first**: Never create competition between partners
4. **Genuinely helpful**: Reinforces good habits without manipulation

**Examples:**
```
✓ Task completed: "Dishes done"
  → Show: "✨ Clean kitchen! Next: Take out trash"

✓ All recurring chores this week done
  → Show: "🎉 Weekly chores complete! Home looks great"

✓ Partner completed their Next 3
  → Show to other: "💙 [Partner] cleared their Next!"
```

## Notification Policy

- 1 daily digest max
- Deadline notifications only for real deadlines
- No hourly reminders
- Complete silence option available

## MVP Scope

### In MVP:
- ✅ Household + invitations (CKShare)
- ✅ Guest mode with demo data seeding
- ✅ Tasks with assignee and status (WIP limit: max 3 in "Next")
- ✅ Shopping list with restock suggestions
- ✅ Backlog categories and items (long-term storage)
- ✅ Tab navigation: Shopping, Tasks, Backlog, More
- ✅ Sign in with Apple
- ✅ CloudKit sync with offline-first architecture
- ✅ Basic notifications (daily digest + deadlines)

### Removed from MVP (simplified):
- ❌ Areas/Boards (replaced by Backlog Categories)
- ❌ Recurring Chores (deferred to post-MVP)
- ❌ Projects (can be represented as Backlog Categories)

### Out of MVP (optional):
- Templates
- Activity feed
- Attachments
- Advanced projects with dependencies

## Future Features (Post-MVP)

These features are documented and planned for implementation after MVP launch. Each has dedicated documentation in `docs/` with implementation guides, cost estimates, and trade-offs.

### Analytics & Metrics
- **What:** App Store Connect analytics (downloads, active users, retention, crashes)
- **Documentation:** [Analytics Guide (archived)](docs/old/docs/2026-01-10_analytics-explained.md)
- **Status:** Not implemented
- **Priority:** Medium (after MVP launch with 10+ users)
- **Effort:** 0h (App Store Connect is automatic)
- **Cost:** $0 (free with Apple Developer Account)
- **When:** Post-MVP, when you want to measure growth

### Monetization
- **What:** In-app purchases / subscriptions (StoreKit 2)
- **Model:** Freemium recommended (free: 2 members, paid: 3+ members)
- **Pricing:** $4.99/mo or $39.99/yr
- **Documentation:** [Monetization Guide (archived)](docs/old/docs/2026-01-10_monetization-explained.md)
- **Status:** Not implemented
- **Priority:** High (required for sustainability after product-market fit)
- **Effort:** 8-12h (App Store Connect setup + StoreKit 2 code + PaywallUI)
- **Revenue estimate:** $5,000-10,000 year 1 (conservative)
- **When:** After MVP validation (100+ active users, positive feedback)

### Localization (i18n)
- **What:** Multi-language support (Polish, German, Italian, Spanish, Chinese, Japanese)
- **Approach:** DIY with AI assistance (ChatGPT/Claude) + native review
- **Documentation:** [Localization Guide (archived)](docs/old/docs/2026-01-10_localization-explained.md)
- **Status:** English only
- **Priority:** Medium (expand user base internationally)
- **Effort:** ~15-20h for 3 languages (PL, DE, IT)
- **Cost:** $45-75 (native review per language: $15-25)
- **Rollout plan:**
  - v1.0: English only (MVP)
  - v1.1: + Polish (main market)
  - v1.2: + German (large market)
  - v2.0: + Italian, Spanish, Chinese, Japanese
- **When:** v1.1 (after MVP in English is stable)

### Automated Testing
- **What:** Unit tests, UI tests, integration tests
- **Framework:** XCTest (built-in)
- **Documentation:** [Testing Strategy (archived)](docs/old/docs/2026-01-10_testing-strategy.md)
- **Status:** Partially implemented (GitHub Actions CI configured, no tests yet)
- **Priority:** High (code quality, refactoring confidence)
- **Recommended approach:** Level 1 (Unit tests only) for MVP
- **Effort:**
  - Level 1 (Unit only): 10-15h initial + 30min/feature
  - Level 2 (Unit + UI): 20-30h initial + 1.5h/feature
  - Level 3 (Full): 40-60h initial + 3h/feature
- **Coverage target:** 60-70% for MVP
- **When:** Start with MVP (unit tests for critical logic)

### Marketing & Growth Strategy
- **What:** App Store Optimization (ASO), paid advertising, launch strategy, organic growth
- **Target market:** Global English-speaking (USA, UK primarily)
- **Budget:** $50-200/month (bootstrap phase)
- **Channels:**
  - **Primary:** Apple Search Ads ($100-150/month recommended)
  - **Secondary:** Facebook/Instagram Ads ($50-100/month)
  - **Organic:** Product Hunt launch, Reddit engagement, X/Twitter #BuildInPublic
- **Launch strategy:** Aggressive Day 1 post-MVP
- **Documentation:** [Marketing Strategy Guide (archived)](docs/old/docs/2026-01-11_marketing-strategy-explained.md)
- **Status:** Planned (execute post-MVP)
- **Priority:** High (user acquisition critical for validation)
- **Effort:** 5-10h/week (monitoring ads, content creation, community engagement)
- **Expected results (Month 1):** 160-425 downloads, 3-10 paying users, $15-50 revenue
- **Break-even timeline:** 6-12 months realistic
- **When:** Day 1 after MVP approval (ASO setup), Week 1 (paid ads start)
- **Key metrics:** CPI <$3, conversion to paid >2%, 4.5+ star rating
- **ASO priorities:** Keywords, screenshots with value props, first 3 lines of description

### Implementation Prerequisites
- **Getting Started:** See [Getting Started Checklist (archived)](docs/old/docs/2026-01-10_getting-started-checklist.md)
- **Required:** Xcode project setup, CloudKit capability, GitHub repo
- **Estimated first working prototype:** 2-3 weeks (4-6 sessions × 4h)

## Technical Stack

- **Platform**: iOS 17+ (iOS 26+ for Liquid Glass effects)
- **UI Framework**: SwiftUI
- **Architecture**: Offline-first with background sync (ADR-002)
- **Auth**: Sign in with Apple
- **Backend**: CloudKit (see `docs/2026-01-10_adr-001-cloudkit-backend.md`)
- **Local Storage**: SwiftData (for offline caching)
- **CI/CD**: GitHub Actions
- **Testing**: XCTest
- **Active branch**: `rebuild/swiftui-clean-impl`
- **Development**: Linux (user) → GitHub Actions (build/test) → iPhone 15 (iOS 26.2.1, physical testing)

## Architecture & Implementation

### Sync Modes

The app supports two sync modes:

1. **Guest Mode (`.localOnly`)**
   - No CloudKit sync
   - All data stored locally in SwiftData
   - Demo data automatically seeded on household creation:
     - 1 owner member
     - 8 tasks (3 next, 4 backlog, 1 done)
     - 5 shopping items (4 active, 1 bought)
     - 2 backlog categories with 5 items
   - Ideal for trying the app without Sign in with Apple

2. **Cloud Sync Mode (`.cloud`)**
   - Full CloudKit synchronization
   - Requires Sign in with Apple
   - Household sharing via CKShare
   - Background sync with offline support

### Navigation Structure

**Custom Floating Tab Bar** (`FloatingTabBar.swift`) — not native TabView:
1. **Shopping** 🛒 - Shared shopping list with restock
2. **Tasks** ✓ - Active tasks (max 3 per person in "Next")
3. **Backlog** 📦 - Long-term storage (categorized)
4. **More** ⋯ - Settings, household, profile

Tab bar uses Liquid Glass effect on iOS 26+ (`GlassEffectContainer` + `.glassEffect()`) with material fallback on iOS 17-25. Hides on keyboard show.

### Codebase Structure

```
FamilyTodo/
├── FamilyTodoApp.swift          # App entry, schema, environment setup
├── ContentView.swift             # Auth gate → MainAppView (tab switcher)
├── Models/
│   ├── Task.swift                # status: backlog/next/done, assigneeId, dueDate, notes, areaId, recurringChoreId
│   ├── ShoppingItem.swift        # title, quantity, unit, isBought, restockCount
│   ├── Household.swift           # name, ownerId, members[], areas[]
│   ├── Member.swift              # userId, displayName, role (owner/member), isActive
│   ├── BacklogCategory.swift     # + BacklogItem (title, notes, categoryId)
│   ├── Cached*.swift             # SwiftData @Model versions of all above
│   └── LegacyStubs.swift         # ⚠️ Area, RecurringChore models + stub views/stores
├── Views/
│   ├── ShoppingListView.swift    # ✅ Full: rapid entry, buy/unbuy, RestockSheet, suggestions
│   ├── TasksView.swift           # ⚠️ Basic CRUD only — no detail/edit sheet
│   ├── BacklogView.swift         # ✅ Categories + items CRUD
│   ├── MoreView.swift            # ⚠️ Hub with partial sub-screens (see below)
│   ├── SignInView.swift          # Sign in with Apple UI
│   ├── OnboardingView.swift      # ⚠️ Legacy? May be unused
│   ├── MemberManagementView.swift # ✅ Full CRUD + roles + context menus
│   ├── ShareInviteView.swift     # ✅ UICloudSharingController wrapper
│   ├── ThemeStore.swift          # 4 presets: Journal, Pastel, Soft, Night
│   ├── Components/
│   │   ├── FloatingTabBar.swift  # Custom glass tab bar
│   │   ├── AppBackgroundView.swift
│   │   ├── GuidedEmptyStateView.swift
│   │   ├── NewItemsBanner.swift
│   │   └── ToastView.swift
│   └── Onboarding/
│       ├── OnboardingCarouselView.swift
│       ├── CreateHouseholdView.swift  # ⚠️ joinHousehold() is TODO
│       ├── SyncSelectionView.swift
│       └── AuroraBackground.swift
├── Stores/
│   ├── ShoppingListStore.swift   # ✅ Full: CRUD, restock, suggestions, CloudKit sync
│   ├── TaskStore.swift           # ✅ CRUD + WIP limit + notifications
│   ├── BacklogStore.swift        # ✅ Categories + items CRUD
│   ├── HouseholdStore.swift      # ✅ Create/load/share + guest seeding
│   └── MemberStore.swift         # ✅ CRUD + roles (⚠️ no role validation enforcement)
├── Managers/
│   ├── CloudKitManager.swift     # Full CloudKit CRUD for all record types
│   ├── CloudKitManager+Mapping.swift  # CKRecord ↔ Model mapping
│   └── CloudKitSubscriptionManager.swift
├── Services/
│   ├── AuthenticationService.swift    # Sign in with Apple + CloudKit identity
│   ├── UserSession.swift              # Session state, sync mode, household ID
│   ├── NotificationService.swift      # Task reminders + daily digest
│   └── OnboardingState.swift
└── Utilities/
    ├── AppColors.swift
    ├── Color+Pastel.swift
    ├── HapticManager.swift
    └── InteractionTokens.swift        # AppChromeMetrics, Tab enum, etc.
```

### Data Models (SwiftData Cache)

Current schema:
- `CachedHousehold` - Household metadata
- `CachedMember` - Household members with roles
- `CachedTask` - Tasks with status, assignee, dates
- `CachedShoppingItem` - Shopping list items
- `CachedBacklogCategory` - Category containers
- `CachedBacklogItem` - Items within categories
- `CachedArea` - Legacy, in LegacyStubs (unused but in schema)
- `CachedRecurringChore` - Legacy, in LegacyStubs (unused but in schema)

### Store Pattern

All stores follow the same offline-first pattern:
1. Load from SwiftData cache first (instant UI)
2. If `syncMode == .cloud` → fetch from CloudKit
3. Update cache + UI
4. Writes: optimistic UI update → cache → CloudKit sync

Stores:
- `HouseholdStore` - Household CRUD + CKShare + guest seeding
- `TaskStore` - Task management with WIP limit (3 per assignee in .next)
- `ShoppingListStore` - Shopping list with restock/suggestions logic
- `BacklogStore` - Category and item management
- `MemberStore` - Member CRUD + role management
- `ThemeStore` - Appearance (Light/Dark/System) + celebrations/suggestions toggles

### CloudKit Schema

See `docs/2026-01-11_cloudkit-schema.md` for full schema details.

Record types: Household, Member, Task, ShoppingItem, BacklogCategory, BacklogItem

## User Mental Model

Users think in terms of:
- "what needs to be done at home"
- "who will do it"
- "is this for now or later"
- "is this one-time or recurring"

Design UI language, structures, and flows to match this thinking.

## Current Implementation Status (2026-02-15)

### ✅ Fully Working
- Onboarding flow (carousel → sync selection → household creation)
- Guest mode with seeded demo data
- Sign in with Apple authentication
- CloudKit CRUD for all core models + SwiftData cache
- Shopping list: rapid entry, buy/unbuy, recently purchased restock, swipe delete, clear all, suggestions
- Tasks: create, complete/uncomplete, WIP limit (3/assignee), completed section
- Backlog: categories CRUD, items CRUD, swipe delete
- Member management: CRUD, roles (owner/member), context menus
- Household sharing via CKShare (basic)
- Notifications: task reminders (due date), daily digest
- Theme: 4 presets (Journal, Pastel, Soft, Night), appearance mode (Light/Dark/System)
- Floating tab bar with Liquid Glass (iOS 26+) + material fallback
- Keyboard accessory: custom "Done" pill button above keyboard

### ⚠️ Stubs / Partial
- **Task Detail/Edit** → stub "Coming Soon" in `LegacyStubs.TaskDetailView` — no way to edit assignee, due date, notes, area
- **Recurring Chores** → stub "Coming Soon" in `RepetitiveTasksView` — model `RecurringChore` exists but no store/UI
- **Areas/Rooms** → `AreaStore` is empty stub — model `Area` with defaults exists but unused
- **Categories Management (More)** → uses local `@State [String]`, NOT wired to `BacklogStore`!
- **Sign Out** → empty closure in `SettingsView` (line ~346)
- **Notification Settings** → `NotificationSettingsStore` is stub with hardcoded defaults
- **Join Household** → `CreateHouseholdView.joinHousehold()` is TODO
- **Role Guardrails** → `MemberStore` accepts `currentUserId` parameter but doesn't validate it
- **Household Rename/Leave/Delete** → no UI
- **Backlog → Task Promotion** → no flow connecting the two

### 📋 Roadmap
See `claude-codex-TODO.md` for the merged implementation roadmap (Phases 0-9).

### Known Technical Debt
1. `LegacyStubs.swift` contains models (Area, RecurringChore), stub views (TaskDetailView), and stub stores (AreaStore, NotificationSettingsStore) that should be broken out into real implementations
2. `Task.areaId` and `Task.recurringChoreId` exist in the model but have no UI
3. `OnboardingView.swift` (in Views/) may be legacy/unused — investigate
4. `CategoriesManagementView` in MoreView doesn't persist changes
5. Historical docs archived in `docs/old/`; active docs in `docs/current/`



## Development Guidelines

When implementing features:
1. Prioritize simplicity and human relationships
2. Avoid feature creep
3. If multiple options exist, choose the simplest as default, describe others as alternatives
4. Keep UX language aligned with user mental model (see above)
5. Always consider offline-first architecture
6. Ensure all decisions support the "two people living together" use case

## Testing & CI/CD

### Pre-commit Hooks

Always run before committing:
```bash
pre-commit run --all-files
```

Checks:
- YAML syntax
- Merge conflicts
- Large files
- Trailing whitespace
- SwiftLint
- SwiftFormat
- Xcodebuild tests (on GitHub Actions)

### GitHub Actions CI

Workflow runs on every push:
1. Checkout code
2. Select iOS simulator
3. Build app
4. Run unit tests
5. Report results

**Note:** Local development on Linux (Manjaro) uses GitHub Actions for all builds and tests, as Xcode is macOS-only.

### Unit Testing

Current test coverage:
- ✅ `HouseholdTests.swift` - Household creation and guest seeding
- ✅ `MemberTests.swift` - Member model and roles
- ⏸️ TaskStore tests needed (WIP limit enforcement)
- ⏸️ CloudKitManager mock tests needed

Run tests locally (macOS only):
```bash
xcodebuild test -scheme FamilyTodo -destination 'platform=iOS Simulator,name=iPhone 15'
```

Or via GitHub Actions (any platform):
```bash
git push  # Tests run automatically
```

### Manual Testing (Guest Mode)

To verify guest seeding:
1. Fresh install or clear app data
2. Tap "Continue without account"
3. Complete onboarding carousel
4. Select "Continue as Guest"
5. Create household with any name
6. **Verify:**
   - Shopping tab: 5 items (4 active, 1 bought)
   - Tasks tab: 3 "Next" tasks
   - Backlog tab: 2 categories with 5 total items
   - Done section: 1 completed task

## Agent Permissions

When working in this repository, the agent (Claude/Gemini) is allowed to:

1. **Git operations**: Run `git add` and `git commit` autonomously after completing work
2. **GitHub Actions**: Use `gh` CLI to check CI build status and fix failures
3. **Pre-commit**: Always run `pre-commit run --all-files` after implementation and fix any errors
4. **Command approval**: If a command is approved once, it's approved for all future uses

**Workflow after implementation:**
1. Run `pre-commit run --all-files`
2. Fix any linting/formatting errors
3. Run pre-commit again until it passes
4. `git add -A && git commit -m "..."`
5. User will do `git push`

## Language

- Archived product requirements document (`docs/old/root/instructions.md`) is in Polish
- Code, comments, and active documentation should be in English

---

## Quick Reference

### Key Files

| File | Purpose |
|------|---------|
| `CLAUDE.md` | This file — agent guidance |
| `claude-codex-TODO.md` | **Merged implementation roadmap** (Phases 0-9) |
| `claude-PLAN.md` | Antigravity's fix plan (Done button, RestockSheet, Glass) |
| `claude-NOTES.md` | Review notes on Codex implementation |
| `codex-PLAN.md` | Codex's implementation plan |
| `README.md` | Documentation entrypoint |
| `STATUS.md` | Implementation status (may be outdated — check this file instead) |
| `docs/current/ROADMAP.md` | Active roadmap |
| `docs/current/TESTING_CI_POLICY.md` | CI and testing policy |
| `docs/current/CLOUD_SYNC_PROFILES.md` | Cloud sync profile switching |

### Documentation Structure

```
├── CLAUDE.md                    # Agent guidance (this file)
├── claude-codex-TODO.md         # Merged roadmap (source of truth for next steps)
├── claude-PLAN.md               # Fix plan for specific bugs
├── claude-NOTES.md              # Code review notes
├── codex-PLAN.md                # Codex implementation plan
├── README.md                    # Docs entrypoint
├── STATUS.md                    # Implementation status
└── docs/
    ├── current/                 # Active operational docs
    └── old/                     # Archived legacy docs
```

### Common Commands

```bash
# Pre-commit checks
pre-commit run --all-files

# Git workflow
git add <files>
git commit -m "feat: description"
# User does: git push

# Check CI status
gh run list --limit 5

# View test results
gh run view <run-id> --log
```

### Important Constraints

1. **Areas/RecurringChores exist as legacy models** - Models defined in `LegacyStubs.swift`, stores are empty stubs. Planned for future implementation (see Phase 5-6 in roadmap).
2. **Guest seeding is automatic** - Don't manually seed in tests; call `createHousehold()` with `.localOnly` mode.
3. **WIP limit is 3** - Enforce in TaskStore, not UI. UI should disable "Move to Next" when limit reached.
4. **CloudKit sync is optional** - App must work fully in `.localOnly` mode.
5. **SwiftData is source of truth** - CloudKit is for sync only, not primary storage.
6. **iOS 26 Liquid Glass** - `glassEffect()` must be the LAST modifier. No `.overlay` or `.shadow` after it — they block compositing.
7. **Development on Linux** - User develops on Linux/Manjaro. All builds and tests run via GitHub Actions or on physical device (iPhone 15, iOS 26.2.1).

### Useful Patterns

**Creating a new model:**
1. Define struct in `Models/` (Codable, Identifiable)
2. Create `Cached*` SwiftData model with sync metadata
3. Add conversion methods: `init(from:)`, `update(from:)`, `to*())`
4. Add to schema in `FamilyTodoApp.swift`
5. Implement CloudKit mapping in `CloudKitManager+Mapping.swift`
6. Create store in `Stores/` with @Observable
7. Add unit tests in `FamilyTodoTests/`

**Adding a new tab:**
1. Create view in `Views/`
2. Add to `ContentView` tab switcher (custom, not TabView)
3. Add icon to `FloatingTabBar` (if implemented)
4. Update navigation logic

---

## Questions?

If you're uncertain about:
- **Architecture decisions** → Check `docs/2026-01-10_adr-001-cloudkit-backend.md` and `docs/2026-01-12_adr-002-error-handling-offline-first.md`
- **Current roadmap** → Check `docs/current/ROADMAP.md`
- **Current status** → Check `STATUS.md`
- **Archived historical requirements** → Check `docs/old/root/instructions.md` (Polish)

When in doubt, prefer simplicity and follow existing patterns in the codebase.
