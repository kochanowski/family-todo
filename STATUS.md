# STATUS

Last updated: 2026-02-15

## Implemented (current redesign branch)

### Core shell
- 4-tab app shell: Shopping, Tasks, Backlog, More
- Custom floating tab bar
  - iOS 26+: Liquid Glass transition path (`GlassEffectContainer` + matched transition)
  - iOS 17-25: material fallback
- Onboarding flow: carousel -> sync choice -> household setup -> main app
- Sign in with Apple + guest mode
- CloudKit sync + SwiftData offline-first cache

### Shopping
- Rapid entry with stable keyboard behavior
- Custom keyboard accessory `Done` pill (matching CTA metrics)
- Recently Purchased:
  - one-tap restore to shopping list
  - swipe delete per title
  - clear all with confirmation
- Header actions: clear To Buy with confirmation, open Recently Purchased

### Tasks (backlog-first)
- `TasksView` is execution board (no manual intake button)
- Sections: `NEXT`, `BACKLOG`, `COMPLETED`
- Strict rules:
  - `NEXT` requires assignee
  - WIP limit = 3 per assignee
- Inline blocked-action feedback banner (assignee/WIP)
- Backlog -> Next start flow with assignee picker for multi-member households
- Task detail edit sheet (status, assignee, due date, notes)
- Recurring tasks are shown in `Tasks.BACKLOG` with recurring badge

### Backlog
- Categories CRUD + reorder/rename support in management
- Items CRUD per category
- Promote to task flow with atomic behavior:
  - backlog item removed only when task create succeeds
  - typed promotion result (`success`, `assigneeRequired`, `wipLimitReached`, `failed`)
- Multi-member assignee flow before promotion

### More / Settings
- Profile, member management, household management actions
- Categories management wired to real `BacklogStore`
- Repetitive Tasks manager with Daily/Weekly/Monthly/Custom (Every N days)
- Settings:
  - appearance + notification toggles
  - real sign out flow
  - defensive bottom inset to avoid chrome overlap
- Detail screens request hidden app tab bar via `appTabBarVisibility(false)`

### Recurring engine
- `RecurringChoreStore` CRUD active
- `ChoreScheduler` runs on app launch/foreground path and generates tasks with:
  - `status = .backlog`
  - `taskType = .recurring`
  - `recurringChoreId` linked to source chore

## Product decisions now active
- Backlog-only task intake (no direct add in Tasks)
- `Tasks.BACKLOG` is a general staging area (promoted + recurring)
- Rooms/Areas removed from product UI (data compatibility fields remain temporarily)

## In progress / to verify
- On-device visual verification of iOS 26 glass transition strength/contrast
- Additional tests for promotion atomicity and recurring metadata consistency

## Known constraints
- `HPCloudKitEnabled` defaults to `NO` for local UI iteration
- Cloud sharing tests require explicit sync-enabled profile
- Build/test loop is primarily via GitHub Actions + physical iPhone validation
