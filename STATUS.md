# STATUS

Last updated: 2026-02-15

## Implemented (redesign branch)

### Core Features
- App shell with 4 tabs: Shopping, Tasks, Backlog, More
- Custom floating tab bar with Liquid Glass (iOS 26+) + material fallback (iOS 17-25)
- Onboarding: carousel → sync choice → household setup → main app
- Sign in with Apple + guest mode (local-only with seed data)
- CloudKit sync + SwiftData offline-first cache
- 4 theme presets: Journal, Pastel, Soft, Night + Light/Dark/System appearance

### Shopping List ✅
- Rapid entry (type + enter, chain multiple items)
- Buy/unbuy checkbox
- Recently Purchased sheet with swipe-to-delete and "Clear All"
- Smart suggestions from purchase history
- Custom keyboard accessory ("Done" pill button)

### Tasks ⚠️ (basic)
- Create task (title only)
- Complete/uncomplete with animation
- WIP limit enforcement (max 3 in .next per assignee)
- Next + Done sections
- **Missing:** detail/edit sheet, assignee picker, due date, notes — all fields exist in model but no UI

### Backlog ✅
- Categories CRUD (add, delete)
- Items CRUD within categories (add, delete)
- **Missing:** rename category, reorder, item edit, promote to task

### More / Settings ⚠️ (partial)
- Profile card with household name
- Member management (full CRUD, roles, context menus)
- Household sharing via CKShare (`ShareInviteView`)
- Appearance settings (theme, Light/Dark/System)
- Celebrations + suggestions toggles
- **Stubs:** Sign Out (empty closure), Categories Management (local-only @State), Repetitive Tasks ("Coming Soon"), Notification settings

### Infrastructure ✅
- `CloudKitManager` with full CRUD for all 6 record types
- `NotificationService` — task reminders + daily digest
- `AuthenticationService` — Sign in with Apple + CloudKit identity
- `UserSession` — session state, sync mode, household ID
- GitHub Actions CI: build + lint on PR/push, full tests nightly

## In progress
- Tab bar glass effect fix for iOS 26 (`.overlay`/`.shadow` after `.glassEffect()` issue)
- Dynamic bottom chrome insets

## Stubs requiring implementation
| Stub | Location | Priority |
|------|----------|----------|
| Task Detail/Edit Sheet | `LegacyStubs.TaskDetailView` | P0 |
| Sign Out | `SettingsView` empty closure | P0 |
| Categories → BacklogStore | `CategoriesManagementView` local @State | P0 |
| Join Household | `CreateHouseholdView.joinHousehold()` TODO | P0 |
| Role Guardrails | `MemberStore` no validation | P0 |
| Recurring Chores | `RepetitiveTasksView` + `RecurringChore` model | P1 |
| Areas/Rooms | `AreaStore` empty + `Area` model with defaults | P1 |
| Notification Settings | `NotificationSettingsStore` stub | P1 |
| Household Rename/Leave/Delete | No UI | P1 |
| Backlog → Task Promotion | No flow | P1 |

## Roadmap
See `claude-codex-TODO.md` for merged implementation plan (Phases 0-9).

## Known constraints
- `HPCloudKitEnabled` default is `NO` for local UI iteration
- Cloud sharing tests require explicit `sync-enabled` profile
- Dev on Linux; builds via GitHub Actions or physical device (iPhone 15, iOS 26.2.1)
