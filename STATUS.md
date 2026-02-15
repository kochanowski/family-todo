# STATUS

Last updated: 2026-02-15

## Implemented (new redesign)
- App shell with 4 tabs: Shopping, Tasks, Backlog, More.
- New onboarding flow: onboarding carousel -> sync choice -> household setup -> main app.
- Shopping rapid entry flow (show/hide draft row, submit chain, restock sheet).
- Tasks flow with active/completed split and add-task sheet.
- Backlog categories with in-card item add/delete.
- Offline-first data layer in SwiftData caches + CloudKit store integration.
- Guest vs cloud session modes in `UserSession`.
- CI on GitHub Actions with build and lint on PR/push.

## In progress (this branch)
- Tab bar glass polish for iOS 26 Liquid Glass + fallback for iOS 17-25.
- Dynamic bottom chrome insets to keep CTA buttons visible above floating tab bar.
- Documentation cleanup after redesign.

## Remaining TODO
- Finish manual validation on physical iPhone (glass behavior during scroll, CTA visibility, rapid entry).
- Expand automated tests for critical flows (nightly covers full test suite; PR remains build+lint only).
- Add cloud sharing regression checks when running with sync-enabled profile.

## Known constraints
- `HPCloudKitEnabled` default is `NO` for phone UI-preview workflows.
- Cloud sharing scenarios require explicit sync-enabled profile in CI/manual runs.
