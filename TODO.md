# HousePulse - Master Action Plan

## Rules of Engagement
1. Strictly Sequential: implement EXACTLY ONE task at a time.
2. No Scope Creep: do not modify code outside the current task scope.
3. Verify & Commit: after each task, run regression checks, commit, then mark `[x]`.
4. CloudKit Safety First: if sync behavior is uncertain, stop and validate before continuing.

## Phase 1: Data Integrity & CloudKit (High Priority)

- [ ] **P1.1 Replace Silent SwiftData Saves**
Description: Replace `try? modelContext.save()` with a shared `saveContextOrSetError(...)` pattern in all stores.
Acceptance Criteria: No silent save calls remain in target stores; failures are logged and surfaced via store error state.
Regression Risk: Local writes may fail visibly; verify create/edit/delete still works for Tasks, Shopping, Backlog.

- [ ] **P1.2 Replay Pending Sync Mutations**
Description: Add `flushPendingSync()` in stores to replay `pendingUpload` and `pendingDelete` after load/reconnect.
Acceptance Criteria: Offline-created/edited/deleted records sync successfully after reconnect/app restart.
Regression Risk: Duplicate operations or resurrection of deleted records; test offline -> restart -> reconnect flows.

- [ ] **P1.3 Add Conflict Policy in Merge (LWW)**
Description: Update merge logic to compare `updatedAt` instead of unconditional local overwrite.
Acceptance Criteria: Newer cloud changes are not overwritten by stale local pending data.
Regression Risk: Unexpected task/item state flips on multi-device edits; test concurrent edits on two devices.

- [ ] **P1.4 Align Cache Delete Semantics**
Description: Ensure cache loads filter tombstones consistently (`pendingDelete`) across stores, including Shopping.
Acceptance Criteria: Deleted items do not reappear from cache during offline or cold start.
Regression Risk: Missing records due to over-filtering; verify restore and recent-item behaviors.

- [ ] **P1.5 Remove N+1 Cache Sync Queries**
Description: Refactor `syncToCache` to single/batched fetch + in-memory merge (Task/Shopping/Backlog).
Acceptance Criteria: Sync path no longer runs per-record fetch loops.
Regression Risk: Partial cache updates; verify large sync snapshots apply correctly.

- [ ] **P1.6 Add CloudKit Query Pagination**
Description: Add paginated query helpers (`resultsLimit` + cursor loop) and apply to key fetch paths.
Acceptance Criteria: Full dataset is returned beyond single-page limits for Tasks/Shopping/Backlog/Members and invite lookup queries.
Regression Risk: Missing pages or duplicates; test with seeded large datasets.

- [ ] **P1.7 Move Member Color Migration Off Hot Path**
Description: Remove write-side migration from every `fetchMembers()` and run one-time migration bootstrap.
Acceptance Criteria: Member fetch no longer performs migration writes on normal path.
Regression Risk: Color defaults/regression in old records; test existing households on upgrade.

- [ ] **P1.8 Harden Invite Security**
Description: Increase invite code entropy (length 8), enforce usage/attempt controls, update role constraints for InviteToken.
Acceptance Criteria: Invite create/redeem/revoke still works; security exposure reduced.
Regression Risk: Invite flow breakage; test link/QR/code redemption on two accounts.

- [ ] **P1.9 Complete Push E2E Bridge**
Description: Add `didReceiveRemoteNotification` forwarding in AppDelegateBridge and close CloudKitSubscriptionManager handling loop.
Acceptance Criteria: Remote notifications trigger app refresh/banner pipeline.
Regression Risk: Notification spam or self-notify regressions; test foreground/background behavior.

- [ ] **P1.10 Targeted Bulk CloudKit Operations**
Description: Add batched `CKModifyRecordsOperation` for high-volume write paths (seeding/reorder/bulk updates).
Acceptance Criteria: Bulk operations use fewer round trips and maintain correctness.
Regression Risk: Partial-save edge cases; test failure handling and rollback expectations.

## Phase 2: Core Features & UX (Medium Priority)

- [ ] **P2.1 Engaging Empty States**
Description: Complete empty-state coverage in Shopping/Tasks Active/Ideas with `ContentUnavailableView`.
Acceptance Criteria: Empty states appear correctly with CTA and proper symbols.
Regression Risk: List visibility regressions; test empty and non-empty transitions.

- [ ] **P2.2 Conversational Task Filter Chips**
Description: Add `All tasks`, `My tasks`, `[Name]'s tasks` chips with ID-based filtering.
Acceptance Criteria: Filters work for Active and Completed; no duplicate current-user chip.
Regression Risk: Wrong task subset or filter reset issues; test toggling and state persistence.

- [ ] **P2.3 Poke Data Model & Mapping**
Description: Add `lastPokedAt` to domain/cache/CloudKit schema + validator.
Acceptance Criteria: Field round-trips model -> cache -> cloud -> model without loss.
Regression Risk: Schema gate failures or mapping mismatches; test CI schema validation.

- [ ] **P2.4 Poke Logic & Cooldown UX**
Description: Implement `canPoke`, `pokeTask`, leading swipe action, cooldown disabled state, anti-multitap guard.
Acceptance Criteria: Poke only for other users’ tasks; once per day per task; no duplicate pokes.
Regression Risk: Duplicate writes or wrong eligibility; test edge cases (unassigned/self/rapid taps).

- [ ] **P2.5 Gentle Rewards Expansion**
Description: Extend CelebrationManager with prioritized message selection (milestone > surprise > fallback) and weekly surprise cap.
Acceptance Criteria: Completion toast logic follows priority and respects `celebrationsEnabled`.
Regression Risk: Toast spam or missing celebrations; test milestone and non-milestone completions.

- [ ] **P2.6 Round-Robin Recurring Task Rotation**
Description: Implement persistent rotation cursor for recurring chores and generation logic updates.
Acceptance Criteria: Multi-assignee chores rotate predictably (A->B->A...).
Regression Risk: Assignment drift or duplicate generation; test recurring generation across days.

- [ ] **P2.7 Shopping Bundles End-to-End**
Description: Implement bundle model/store/cloud/UI + long-press quick add.
Acceptance Criteria: Bundle CRUD works and adds all items instantly to list.
Regression Risk: Duplicate shopping items or sync mismatch; test local+cloud behavior.

- [ ] **P2.8 Activity Log End-to-End**
Description: Implement ActivityLog model/store/view and integrate logging in task/shopping actions.
Acceptance Criteria: Logs are created for defined action types with `userId`.
Regression Risk: Missing/incorrect actor attribution; test actions from multiple users.

- [ ] **P2.9 Push Message Enrichment via Activity Log**
Description: Improve push/in-app update messaging using activity events where available.
Acceptance Criteria: Notifications are contextual (“who did what”) and avoid self-noise.
Regression Risk: Notification duplication or stale events; test event de-duplication.

## Phase 3: Polish & Future (Low Priority)

- [ ] **P3.1 Versioned SwiftData Schema Framework**
Description: Introduce `VersionedSchema` + migration plan scaffolding.
Acceptance Criteria: App boots with explicit schema versioning path.
Regression Risk: Migration boot regressions; test upgrade from existing local stores.

- [ ] **P3.2 Evaluate Relationship/Cascade Migration**
Description: Assess and optionally introduce relationship-based cascade delete strategy.
Acceptance Criteria: Decision documented and, if implemented, orphan records are eliminated safely.
Regression Risk: Data loss from aggressive cascades; test household/category deletion paths.

- [ ] **P3.3 Evaluate Zone-Scoped Subscriptions**
Description: Reassess DB-wide subscription vs zone-specific subscriptions for future multi-household support.
Acceptance Criteria: Technical decision captured with rollout constraints.
Regression Risk: Notification blind spots if switched incorrectly.

- [ ] **P3.4 Sharing Role UX Enhancements**
Description: Plan owner-transfer UI and optional read-only sharing mode.
Acceptance Criteria: Clear product decision and UX flow documented/implemented.
Regression Risk: Membership/permission regressions in leave/delete flows.

- [ ] **P3.5 Guest Data Protection Hardening**
Description: Evaluate and apply stronger on-device data protection for guest/local storage mode.
Acceptance Criteria: Protection policy documented and enabled where feasible.
Regression Risk: Startup/access regressions on locked device states.

- [ ] **P3.6 Remaining UX Polish**
Description: Finish deferred UX tasks (WIP hard enforcement consistency, sign-out overlap fixes, theme polish).
Acceptance Criteria: Known UI regressions closed.
Regression Risk: New visual regressions; run smoke tests across tabs/themes.

## Implementation Steps for This Consolidation Task
1. Replace current `TODO.md` content with the master structure above.
2. Delete `CLOUDKIT_codex.md`.
3. Delete `FEATURES_codex.md`.
4. Run quick doc sanity checks:
- headings present
- all tasks have Description/Acceptance Criteria/Regression Risk
- phase ordering follows integrity -> features -> polish
5. Commit docs-only change locally (no push).

## Test Cases and Scenarios (for consolidation task itself)
1. `TODO.md` exists and is the only planning source file.
2. `CLOUDKIT_codex.md` and `FEATURES_codex.md` no longer exist.
3. Every task is check-boxed and sequenced under exactly one phase.
4. Rules of Engagement are at the top and explicitly enforce one-task-at-a-time.
5. No CloudKit or app code changed as part of this consolidation.

## Assumptions
1. Existing `TODO.md` historical notes are intentionally replaced by the new master plan.
2. Language for master plan is English to match requested template.
3. “One task at a time” applies globally across CloudKit and feature work.
4. Docs-only workflow follows your rule: no push unless explicitly requested.
