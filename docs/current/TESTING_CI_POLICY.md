# TESTING_CI_POLICY

Last updated: 2026-02-15

## Why this policy exists
Build time on macOS runners must stay short for rapid UI iteration on phone. Because of that, tests are intentionally split between fast CI and full nightly/manual regression.

## CI behavior
- `ios-ci.yml` (PR/push):
  - runs build (no signing),
  - runs SwiftLint,
  - does not run XCTest by default.
- `nightly.yml`:
  - runs full `xcodebuild test` suite,
  - is scheduled nightly,
  - can also be triggered manually (`workflow_dispatch`).

## Temporary test toggling
- If you need extra confidence on a branch, run `nightly.yml` manually.
- Keep PR CI test steps disabled unless there is a high-risk refactor.
- Re-enable selected PR tests temporarily only when debugging a regression that cannot wait for nightly.

## Expected usage
- Daily development loop: PR build+lint only.
- Regression loop: nightly + manual dispatch before bigger merges/releases.

## Manual iPhone checklist
- Scroll Shopping/Tasks and confirm floating tab bar keeps visible glass behavior.
- Confirm `+ Add item` in Shopping is always visible above tab bar.
- Confirm rapid entry flow: show row -> submit multiple items -> tap outside to commit/dismiss.
- Confirm smoke paths: app launch, tab switching, shopping add/restock, task add/complete.
