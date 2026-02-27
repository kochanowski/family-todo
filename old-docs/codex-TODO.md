# Plan v6 — Backlog-First Tasks, Strict WIP, Settings/Glass Fix, Recurring Finalization

Last updated: 2026-02-15

## Decisions (locked)
1. Backlog-only intake for tasks: no manual add in `TasksView`.
2. `NEXT` requires assignee (strict rule).
3. WIP limit stays hard at 3 per assignee with blocked action + inline banner.
4. Backlog promotion is atomic: backlog item is removed only after task create success.
5. `Tasks.BACKLOG` is general staging area (promoted + recurring tasks).
6. Rooms/Areas are removed from product UI/flows (data compatibility fields stay in models for now).
7. Recurring scheduler creates tasks with:
   - `status = .backlog`
   - `taskType = .recurring`
   - `recurringChoreId = chore.id`
8. iOS 26 tab transition uses Liquid Glass matched transition; iOS 17-25 uses material fallback.

## Implementation Status

### P0 blockers
- [x] Settings detail overlap mitigation:
  - `appTabBarVisibility(false)` on detail screens
  - defensive bottom inset in `SettingsView`
- [x] Backlog-only intake in Tasks:
  - removed manual `+ Add task` flow
- [x] Strict `NEXT` validation in `TaskStore`:
  - assignee required
  - typed validation result (`NextTransitionValidation`)
- [x] Atomic promotion in `BacklogStore` with typed `PromotionResult`
- [x] Promote/start assignee flow:
  - single-member household => auto-assign
  - multi-member household => assignee picker
- [x] Inline feedback banners for WIP/assignee blocks in `TasksView` and `BacklogView`

### P1 simplification + polish
- [x] Remove Rooms/Areas from More UI entrypoints
- [x] Repetitive Tasks: `Custom = Every N days` UI
- [x] Scheduler recurring semantics to `Tasks.BACKLOG` with recurring metadata
- [x] Backlog add-row style aligned with Shopping inline pattern
- [x] iOS 26 tab bar refactor:
  - `GlassEffectContainer`
  - `glassEffectID(..., in:)`
  - `glassEffectTransition(.matchedGeometry)`

### Validation and test hardening
- [x] Updated baseline `TaskStore` unit test for new strict assignee rule
- [ ] Add dedicated tests for:
  - promotion atomicity on failure
  - multi-member assignee picker path (UI smoke)
  - recurring generated task metadata
- [ ] Manual iPhone validation after CI build:
  - glass transition visibility
  - Sign Out placement
  - strict WIP block behavior

## Open Follow-ups (post-v6)
1. Add recurring badge explanation in Task detail/help copy.
2. Introduce richer assignee quick-pick chips in `TasksView` backlog section.
3. Add explicit analytics events for blocked WIP actions and promotion success/failure.
4. Consider deprecating legacy `AreaStore`/`CachedArea` internals after schema migration plan.
