# CloudKit Performance Optimization Walkthrough

## What I changed (Task IDs)
- **Bottleneck 1 (Create Household)**: Replaced sequential `await` calls that save the Household and Member records separately with a single `CKModifyRecordsOperation` via `createHouseholdWithMember`.
- **Bottleneck 2 (Generate Invite QR)**: Reversed the token creation order—now it first checks the public DB for an existing valid token *before* executing the heavy `createShare` pipeline, avoiding ~7+ networking round-trips when a token already exists.
- **Bottleneck 3 (Join Household Retry)**: Reduced the aggressive retry backoffs in `fetchAcceptedRootRecord` from 5 steps (worst case 10.5 seconds sleep) to 3 steps (worst case 2.6 seconds sleep).
- **Bottleneck 4 (Redundant Calls)**: Removed double-checks of `ensureHouseholdOwnerZone` inside `saveHousehold` and stripped a redundant `repairSharedHouseholdGraphIfNeeded` call during token generation.
- **CI Fix**: Updated [.github/workflows/ios-ci.yml](file:///home/wkochanowski/code/family-todo/.github/workflows/ios-ci.yml) so that tests systematically run on pushes to the `main` and `fix/tasks-ideas-sync` branches *before* the TestFlight deployment stage. Fixed SwiftLint `line_length` warnings in unrelated files caused by newly configured `swiftformat`.

## Files changed
- [FamilyTodo/Managers/CloudKitManager.swift](file:///home/wkochanowski/code/family-todo/FamilyTodo/Managers/CloudKitManager.swift)
- [FamilyTodo/Stores/HouseholdStore.swift](file:///home/wkochanowski/code/family-todo/FamilyTodo/Stores/HouseholdStore.swift)
- [FamilyTodoTests/HouseholdJoinFlowTests.swift](file:///home/wkochanowski/code/family-todo/FamilyTodoTests/HouseholdJoinFlowTests.swift)
- [.github/workflows/ios-ci.yml](file:///home/wkochanowski/code/family-todo/.github/workflows/ios-ci.yml)
- [FamilyTodo/Services/CelebrationManager.swift](file:///home/wkochanowski/code/family-todo/FamilyTodo/Services/CelebrationManager.swift)
- [FamilyTodo/Utilities/FontRegistrar.swift](file:///home/wkochanowski/code/family-todo/FamilyTodo/Utilities/FontRegistrar.swift)

## What to test on the device

**Regression checklist in app:**

1. **Create Household latency**
   - Tap "Start a new household" or hard reset and create one.
   - *Expected:* The spinner should complete noticeably faster (target: 1-3 seconds instead of 5-20s). The `Household` and `Member` records should be intact.
2. **Generate Invite QR latency**
   - From Settings > Invite to Household, tap to generate a code or QR.
   - Close the sheet, then open it again.
   - *Expected:* The second time you open the sheet, the token loads nearly instantly instead of re-running the full share creation flow.
3. **Join Household latency**
   - On a second device, scan the QR code or manually enter the invite code.
   - *Expected:* After accepting the system iCloud share prompt, dropping into the app and joining should execute significantly faster, as retry backoffs have been trimmed from 10.5s down to 2.6s.
4. **General sync stability**
   - Ensure tasks and ideas still sync normally. None of these changes touched the core delta-sync mechanism (`TaskStore` or `BacklogStore`), but verifying basic CRUD helps ensure the shared graph is unchanged.
