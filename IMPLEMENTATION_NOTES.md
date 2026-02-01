# CI/CD Reconfiguration Notes

## Summary
The TestFlight upload step has been disabled for standard pushes and PRs to avoid hitting Apple's daily upload limits (error 409). A new automated UI smoke test suite has been added to ensure build stability without relying on external deployment validation.

## Changes
1.  **TestFlight Uploads**:
    - Build step `deploy-testflight` is now **conditional**.
    - It ONLY runs when:
        - Triggered manually via GitHub Actions UI (`workflow_dispatch`).
        - A tag starting with `v` is pushed (e.g., `v1.0.1`).
    - It DOES NOT run on standard pushes to `main` or pull requests.

2.  **Automated Testing**:
    - **Unit Tests**: Continue to run on every push/PR.
    - **UI Smoke Tests**: Enabled in `build-and-test` job.
        - Verifies app launch.
        - Verifies tab navigation (Shopping, Tasks, Backlog, More).
        - Verifies critical flows: Rapid Entry (Shopping), Restock Panel.

## How to Deploy to TestFlight
To trigger a new TestFlight build, choose ONE of the following:

### Option A: Manual Trigger (Preferred for ad-hoc)
1.  Go to the "Actions" tab in GitHub.
2.  Select "iOS CI" workflow.
3.  Click "Run workflow".
4.  Select the branch (e.g., `main`).
5.  Click "Run workflow".

### Option B: Release Tag
Push a tag starting with `v`:
```bash
git tag v1.0.1
git push origin v1.0.1
```

## How to Run Tests Locally
```bash
# Unit Tests
xcodebuild test -scheme HousePulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FamilyTodoTests

# UI Tests
xcodebuild test -scheme HousePulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FamilyTodoUITests
```
