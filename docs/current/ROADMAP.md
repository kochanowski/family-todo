# ROADMAP

Last updated: 2026-02-15

> Full details: see `claude-codex-TODO.md` (merged implementation plan, Phases 0-9).

## Now (Sprint 1 — P0 foundation)
- **Phase 0:** Session consistency — single source of truth for household, `GuidedEmptyStateView` for empty states
- **Phase 1:** Task Detail Sheet — edit assignee, due date, notes, status
- **Phase 3:** Sign Out — wire `AuthenticationService.signOut()`, Categories → `BacklogStore`
- Tab bar glass effect fix (iOS 26+ `.glassEffect` ordering)

## Next (Sprint 2 — P0 multi-user + backlog)
- **Phase 4:** Join Household flow, household management (rename, leave, delete), role guardrails
- **Phase 2:** Backlog full operations (rename, reorder, edit item) + Promote to Task
- Notification settings UI

## Later (Sprint 3 — P1 automation)
- **Phase 5:** Recurring Chores engine (CRUD + ChoreScheduler + task generation)
- **Phase 6:** Areas / Rooms (CRUD + task/chore integration)
- **Phase 7:** Polish (celebrations, accessibility, tab bar final)
- **Phase 8:** Testing gate (unit + UI tests for critical flows)

## Future (Sprint 4 — P2 delight)
- Quick Search across all lists
- WidgetKit (tasks, shopping)
- Siri / App Intents
- Drag & Drop reorder
- Weekly Home Pulse digest
- Smart Restock suggestions
- Theme customization
