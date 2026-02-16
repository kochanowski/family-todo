# TESTING_CI_POLICY

Last updated: 2026-02-15

## Why this policy exists
Build time on macOS runners must stay short for rapid UI iteration. Tests are split between fast CI and full nightly/manual regression.

## CI behavior

### `ios-ci.yml` (PR/push)
- Build (no signing)
- SwiftLint
- No XCTest by default

### `nightly.yml` (scheduled + manual)
- Full `xcodebuild test` suite
- Scheduled nightly
- Can also be triggered manually (`workflow_dispatch`)
- Future: add `sync-enabled` lane for CloudKit sharing validation

## Test toggling
- Need extra confidence on a branch? Run `nightly.yml` manually.
- Keep PR CI test steps disabled unless high-risk refactor.
- Re-enable selected PR tests temporarily only for regression debugging.

## Expected usage
- **Daily:** PR build + lint only
- **Regression:** nightly + manual dispatch before merges/releases

## Manual iPhone checklist (physical device — iPhone 15, iOS 26.2.1)

### Core flows
- [ ] App launch → onboarding or main app (based on session)
- [ ] Tab switching (all 4 tabs respond)
- [ ] Shopping: rapid entry → submit multiple items → tap outside to dismiss
- [ ] Shopping: buy/unbuy checkbox → item moves between sections
- [ ] Shopping: Recently Purchased → swipe delete individual → Clear All
- [ ] Tasks: add task → appears in Next → tap checkbox → moves to Done
- [ ] Tasks: WIP limit → try adding 4th task to Next → should be blocked
- [ ] Backlog: add category → add items → delete item → delete category
- [ ] More: profile card shows, member list loads

### Chrome & glass
- [ ] Floating tab bar visible while scrolling (glass effect on iOS 26+)
- [ ] Tab bar hides when keyboard appears
- [ ] `+ Add item` button always visible above tab bar
- [ ] "Done" keyboard accessory pill visible and functional

### Settings
- [ ] Appearance mode switch (Light/Dark/System)
- [ ] Theme preset switch (Journal/Pastel/Soft/Night)

## Planned test expansion (Phase 8 of roadmap)

### Unit tests
- `HouseholdStore`: create / join / rename / leave / delete
- `MemberStore`: role guardrails (owner-only operations)
- `TaskStore`: WIP enforcement + backlog promotion
- `BacklogStore`: reorder / rename / promotion
- `RecurringChoreStore`: schedule calculations

### UI tests
- Onboarding create / join household
- Tasks full CRUD + due date + assignee
- Backlog ↔ More categories consistency
- Settings sign out + session reset
