# TODO (next Codex session)

## Completed
- [x] Sign in with Apple authentication (AuthenticationService, UserSession, SignInView)
- [x] SwiftData offline cache (CachedTask model)
- [x] CloudKit queries (fetchTasks, fetchNextTasks, countNextTasks)
- [x] TaskListView - Kanban UI (Next/Backlog/Done columns)
- [x] TaskDetailView - create/edit tasks
- [x] TaskStore - offline-first with optimistic UI
- [x] Settings view with sign out

## Next Steps (MVP Implementation)
1. ~~**Household onboarding** - create/join household flow~~ ✅
2. ~~**Areas/Boards** - manage task categories~~ ✅
3. ~~**Recurring chores** - weekly task templates~~ ✅
4. **Basic notifications** - daily digest (optional for MVP)

## Infrastructure
- [x] Migrate CI to Fastlane with API key authentication
- Add App Store Connect API key secrets in GitHub (see docs/2026-01-17_fastlane-setup.md)
- Verify `deploy-testflight` job succeeds on push to `main`

## Reference
- Full analysis: docs/2026-01-16_project-analysis.md
- Run `pre-commit run --all-files` after code changes
