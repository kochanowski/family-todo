# TESTING_CI_POLICY

Last updated: 2026-04-11

## Why this policy exists
Build time on macOS runners must stay short for rapid UI iteration. Tests are split between fast CI and full nightly/manual regression.

## CI behavior

### `ios-ci.yml` (PR/push + manual)
- Build (no signing)
- SwiftLint
- XCTest (`FamilyTodoTests`)
- Supports `cloud_sync_profile` override (`preview-local` / `sync-enabled`)
- The XCTest step tolerates the known runner case where `xcodebuild` exits `65`
  even though `xcresult` and the test log both show zero failed tests
- For release/TestFlight branches, runs CloudKit schema gate before deploy:
  - validate schema contract
  - apply Development schema
  - verify Production schema contract coverage (record types)

### `nightly.yml` (scheduled + manual)
- Full `xcodebuild test` suite
- Scheduled nightly
- Can also be triggered manually (`workflow_dispatch`) for an extra regression pass

## Test toggling
- Default confidence comes from `ios-ci.yml`, which runs `FamilyTodoTests`.
- Need extra confidence on a branch? Run `nightly.yml` manually.
- Use nightly for broader reruns, regression sweeps, and flaky-test debugging.

## Expected usage
- **Daily:** PR build + lint + `FamilyTodoTests`
- **Regression:** nightly + manual dispatch before merges/releases
- **Release/TestFlight:** schema gate must be green before deploy job starts

## Manual iPhone checklist (physical device — iPhone 15, iOS 26.2.1)

### Core flows
- [ ] First launch: onboarding carousel -> sync selection -> main app shell
- [ ] iCloud path: choose iCloud -> Sign in with Apple -> auto household setup gate
- [ ] Guest path: choose guest -> auto household setup gate
- [ ] Create household (cloud + guest local)
- [ ] Join household by pasted iCloud invite link
- [ ] Join household by scanned QR invite
- [ ] Deep link accept from iMessage/Mail before login, then finish after login
- [ ] Sign out -> return to SignInView and no stale household context

### Collaboration
- [ ] Owner opens Member Management -> Invite Member (UICloudSharingController)
- [ ] Owner opens Invite QR and second account joins via scan
- [ ] Joined account sees shared updates in Shopping/Tasks/Ideas

### Existing product smoke
- [ ] Shopping interactions (add, buy/unbuy, recently purchased)
- [ ] Tasks board section behavior (`NEXT`, `IDEAS`, `COMPLETED`)
- [ ] Ideas backlog category/item CRUD
- [ ] More/Profile member management and household actions
