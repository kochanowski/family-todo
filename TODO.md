# TODO (next Codex session)

## Completed
- [x] Sign in with Apple authentication (AuthenticationService, UserSession, SignInView)

## Next Steps (MVP Implementation)
1. **SwiftData offline cache** - lokalny cache zgodnie z ADR-002 (offline-first)
2. **CloudKit queries** - fetchAllTasks, fetchTasksByStatus, countTasksInNext
3. **TaskListView** - główny widok z Kanban (Next/Backlog/Done)
4. **TaskDetailView** - tworzenie/edycja tasków

## Infrastructure
- Add App Store Connect + TestFlight secrets in GitHub repo settings (see docs/2026-01-15_testflight-setup.md)
- Verify `deploy-testflight` job succeeds on push to `main`
- Confirm bundle identifier matches App Store Connect app and provisioning profile

## Reference
- Full analysis: docs/2026-01-16_project-analysis.md
- Run `pre-commit run --all-files` after code changes
