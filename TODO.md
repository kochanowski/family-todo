# HousePulse - Master Action Plan

## Rules of Engagement
1. Strictly Sequential: implement EXACTLY ONE task at a time.
2. No Scope Creep: do not modify code outside the current task scope.
3. Verify & Commit: after each task, run regression checks, commit, then mark `[x]`.
4. CloudKit Safety First: if sync behavior is uncertain, stop and validate before continuing.

## Bugfixes & Polish (High Priority)

- [x] **Fix Shopping List Input Padding**
Description: When typing a new item in the Shopping list, the `TextField` padding/alignment doesn't match the saved items. It lacks the empty circle placeholder, causing the text to shift left and break the vertical alignment.
Acceptance Criteria: The `TextField` row must have the exact same leading spacing/layout (e.g., an invisible circle or matching padding) as the saved items so the text perfectly aligns vertically.

- [x] **Optimize Tasks "Clear All" Performance**
Description: In Tasks -> Completed, tapping "Clear All" deletes tasks very slowly (one by one with individual animations).
Acceptance Criteria: Mass deletion must be instant. Optimize the deletion loop (e.g., remove per-item animation, use a single batch delete, or wrap the state update in a single `withAnimation` block).

- [x] **Remove redundant "(+)" in Idea Categories**
Description: In `More -> Idea Categories`, the "New category" button has a built-in plus icon, but the text also says `(+) New category`.
Acceptance Criteria: Change the text string from `(+) New category` to just `New category`.

- [x] **Fix Invite Token wipe on Dev Deploy**
Description: Every time we deploy to the dev environment, the Invite Token gets deleted/wiped. This was supposed to be fixed but is still breaking.
Acceptance Criteria: Investigate the token storage/generation or deployment scripts and ensure the Invite Token persists across deployments.

## Phase 1: Data Integrity & CloudKit (High Priority)

- [x] **P1.1 Replace Silent SwiftData Saves** ([Details](TODO_DETAILS.md#p11))
Description: Replace `try? modelContext.save()` with a shared `saveContextOrSetError(...)` pattern in all stores.
Acceptance Criteria: No silent save calls remain in target stores; failures are logged and surfaced via store error state.
Regression Risk: Local writes may fail visibly; verify create/edit/delete still works for Tasks, Shopping, Backlog.

- [x] **P1.2 Replay Pending Sync Mutations** ([Details](TODO_DETAILS.md#p12))
Description: Add `flushPendingSync()` in stores to replay `pendingUpload` and `pendingDelete` after load/reconnect.
Acceptance Criteria: Offline-created/edited/deleted records sync successfully after reconnect/app restart.
Regression Risk: Duplicate operations or resurrection of deleted records; test offline -> restart -> reconnect flows.

- [x] **P1.3 Add Conflict Policy in Merge (LWW)** ([Details](TODO_DETAILS.md#p13))
Description: Update merge logic to compare `updatedAt` instead of unconditional local overwrite.
Acceptance Criteria: Newer cloud changes are not overwritten by stale local pending data.
Regression Risk: Unexpected task/item state flips on multi-device edits; test concurrent edits on two devices.

- [x] **P1.4 Align Cache Delete Semantics** ([Details](TODO_DETAILS.md#p14))
Description: Ensure cache loads filter tombstones consistently (`pendingDelete`) across stores, including Shopping.
Acceptance Criteria: Deleted items do not reappear from cache during offline or cold start.
Regression Risk: Missing records due to over-filtering; verify restore and recent-item behaviors.

- [x] **P1.5 Remove N+1 Cache Sync Queries** ([Details](TODO_DETAILS.md#p15))
Description: Refactor `syncToCache` to single/batched fetch + in-memory merge (Task/Shopping/Backlog).
Acceptance Criteria: Sync path no longer runs per-record fetch loops.
Regression Risk: Partial cache updates; verify large sync snapshots apply correctly.

- [x] **P1.6 Add CloudKit Query Pagination** ([Details](TODO_DETAILS.md#p16))
Description: Add paginated query helpers (`resultsLimit` + cursor loop) and apply to key fetch paths.
Acceptance Criteria: Full dataset is returned beyond single-page limits for Tasks/Shopping/Backlog/Members and invite lookup queries.
Regression Risk: Missing pages or duplicates; test with seeded large datasets.

- [x] **P1.7 Move Member Color Migration Off Hot Path** ([Details](TODO_DETAILS.md#p17))
Description: Remove write-side migration from every `fetchMembers()` and run one-time migration bootstrap.
Acceptance Criteria: Member fetch no longer performs migration writes on normal path.
Regression Risk: Color defaults/regression in old records; test existing households on upgrade.

- [x] **P1.8 Harden Invite Security** ([Details](TODO_DETAILS.md#p18))
Description: Increase invite code entropy (length 8), enforce usage/attempt controls, update role constraints for InviteToken.
Acceptance Criteria: Invite create/redeem/revoke still works; security exposure reduced.
Regression Risk: Invite flow breakage; test link/QR/code redemption on two accounts.

- [x] **P1.9 Complete Push E2E Bridge** ([Details](TODO_DETAILS.md#p19))
Description: Add `didReceiveRemoteNotification` forwarding in AppDelegateBridge and close CloudKitSubscriptionManager handling loop.
Acceptance Criteria: Remote notifications trigger app refresh/banner pipeline.
Regression Risk: Notification spam or self-notify regressions; test foreground/background behavior.

- [x] **P1.10 Targeted Bulk CloudKit Operations** ([Details](TODO_DETAILS.md#p110))
Description: Add batched `CKModifyRecordsOperation` for high-volume write paths (seeding/reorder/bulk updates).
Acceptance Criteria: Bulk operations use fewer round trips and maintain correctness.
Regression Risk: Partial-save edge cases; test failure handling and rollback expectations.

## Phase 2: Core Features & UX (Medium Priority)

- [x] **P2.1 Engaging Empty States** ([Details](TODO_DETAILS.md#p21))
Description: Implement two-tier FTUX empty states (tutorial + standard) for Shopping, Tasks Active, and Ideas, plus standard Completed-empty handling in Tasks.
Acceptance Criteria: `@AppStorage` flags control tutorial visibility, tutorial CTA buttons persist "seen" state, and standard `ContentUnavailableView` copy/icons render for returning users.
Regression Risk: Empty-state branching may hide real data or show wrong copy; test first-run vs returning-user flows and tab switches.

- [x] **P2.2 Conversational Task Filter Chips** ([Details](TODO_DETAILS.md#p22))
Description: Add conversational assignee chips (`All tasks`, `My tasks`, `[Name]'s tasks`) with ID-based filter state and integration with Active/Completed tabs.
Acceptance Criteria: Chips filter both task tabs correctly, `My tasks` appears only when current member is resolvable, and no duplicate current-user chip is shown.
Regression Risk: Filter desync during member/session changes; test toggle cycles, member list updates, and filtered empty states.

- [x] **P2.3 Poke Data Model & Mapping** ([Details](TODO_DETAILS.md#p23))
Description: Add `lastPokedAt` through the full persistence chain (domain model, SwiftData cache, CloudKit mapping, schema, validator).
Acceptance Criteria: `lastPokedAt` round-trips `Task -> CachedTask -> CloudKit -> Task`, including nil-safe behavior when the field is absent.
Regression Risk: Schema drift or mapping decode failures; validate via CI schema gate and model round-trip tests.

- [x] **P2.4 Poke Logic & Cooldown UX** ([Details](TODO_DETAILS.md#p24))
Description: Implement poke store logic (`canPoke`, `pokeTask`) and leading swipe UX with once-per-day cooldown and anti-multitap guards.
Acceptance Criteria: Poke action is visible only for tasks assigned to other members, same-day repeat poke is blocked, and successful poke persists locally and through sync.
Regression Risk: Duplicate poke mutations or false cooldown lockouts; test self-assigned/unassigned tasks, rapid taps, and day-boundary behavior.

- [x] **P2.5 Gentle Rewards Expansion** ([Details](TODO_DETAILS.md#p25))
Description: Expand `CelebrationManager` with deterministic decision tiers (milestone > surprise > fallback), weekly surprise cap, and Tasks completion integration.
Acceptance Criteria: Completion celebrations use tier priority, weekly surprise limit is enforced, and UI triggers respect `celebrationsEnabled`.
Regression Risk: Celebration spam or missing feedback on completion; test milestone (5/10), surprise eligibility window, and disabled-celebrations mode.

- [ ] **P2.6 Round-Robin Recurring Task Rotation** ([Details](TODO_DETAILS.md#p26))
Description: Build a fully functional recurring engine first (completion -> next task generation by frequency), then apply round-robin assignment with persistent `nextAssigneeIndex` and recurring UI cues.
Acceptance Criteria: Completing a recurring task immediately creates the next instance as `.backlog` with the next due date; with rotation enabled it assigns the next person (A->B->A...), advances cursor safely, and UI shows multi-assignee rotate controls + rotation indicators.
Regression Risk: Duplicate generation, schedule drift, or cursor desync; test idempotency, day boundaries, assignee list edits, and offline/cloud merge.

- [ ] **P2.7 Shopping Bundles End-to-End** ([Details](TODO_DETAILS.md#p27))
Description: Implement ShoppingBundle domain/cache/store/cloud plus polished UX: header bundles icon, long-press quick add, management screens, and feedback toast.
Acceptance Criteria: Bundle CRUD works with `itemsJSON` persistence, bundles are accessible from Shopping header, long-press on `+ Add Item` opens native bundle picker, and selecting bundle shows confirmation (`Added <Bundle> (<N> items)`).
Regression Risk: Serialization mismatch, duplicate inserts, or hidden affordances; test repeated quick-add, discoverability, and local/cloud parity.

- [ ] **P2.8 Activity Log End-to-End** ([Details](TODO_DETAILS.md#p28))
Description: Implement ActivityLog model/cache/store/view with timeline-style UI, clear navigation placement, and store-level action logging.
Acceptance Criteria: Logs are recorded with required actor fields, More tab shows `Activity Log` above technical settings, timeline rows include actor avatar/initials + readable action + relative time, and empty state is friendly.
Regression Risk: Missing attribution, noisy duplicates, or unreadable feed layout; test multi-user ordering, relative-time rendering, and empty/logged states.

- [ ] **P2.9 Push Message Enrichment via Activity Log** ([Details](TODO_DETAILS.md#p29))
Description: Enrich push/in-app updates from ActivityLog with personalized copy and non-invasive in-app banner behavior.
Acceptance Criteria: System pushes are explicit and personalized (`<Name> completed...` / `<Name> bought...`), in-app top banner appears for remote partner actions and auto-dismisses in ~3s, and self-noise + dedup rules remain enforced.
Regression Risk: Duplicate/stale notifications or intrusive in-app UX; test lock-screen copy, foreground banners, and two-device sync storms.

- [ ] **P2.10 Contextual Onboarding (TipKit)** ([Details](TODO_DETAILS.md#p210))
Description: Implement iOS 17 TipKit using native visuals and contextual tips aligned to bundles, idea promotion, and recurring-task guidance.
Acceptance Criteria: Tips use native TipKit look, align with app accent color, appear under explicit state rules (Shopping long-press bundles, Ideas promote, Tasks recurring/sweep guidance), dismiss gracefully, and never block primary actions.
Regression Risk: Layout shifts or tip fatigue; ensure safe `Tips.configure()` startup and precise placement/trigger rules.

## Phase 3: Polish & Future (Low Priority)

- [ ] **P3.1 Versioned SwiftData Schema Framework** ([Details](TODO_DETAILS.md#p31))
Description: Introduce `VersionedSchema` + migration plan scaffolding.
Acceptance Criteria: App boots with explicit schema versioning path.
Regression Risk: Migration boot regressions; test upgrade from existing local stores.

- [ ] **P3.2 Evaluate Relationship/Cascade Migration** ([Details](TODO_DETAILS.md#p32))
Description: Assess and optionally introduce relationship-based cascade delete strategy.
Acceptance Criteria: Decision documented and, if implemented, orphan records are eliminated safely.
Regression Risk: Data loss from aggressive cascades; test household/category deletion paths.

- [ ] **P3.3 Evaluate Zone-Scoped Subscriptions** ([Details](TODO_DETAILS.md#p33))
Description: Reassess DB-wide subscription vs zone-specific subscriptions for future multi-household support.
Acceptance Criteria: Technical decision captured with rollout constraints.
Regression Risk: Notification blind spots if switched incorrectly.

- [ ] **P3.4 Sharing Role UX Enhancements** ([Details](TODO_DETAILS.md#p34))
Description: Add concrete household role UX: visible role badges and owner-only management actions for role change/transfer/remove.
Acceptance Criteria: Member rows show role chips (`Owner`, `Member`, `Read-only`), owner gets action sheet (`Change Role`, `Transfer Ownership`, `Remove from Household`), and destructive actions require explicit red confirmation alerts.
Regression Risk: Permission leaks or accidental destructive actions; test owner/member guardrails and confirmation flows.

- [ ] **P3.5 Guest Data Protection Hardening** ([Details](TODO_DETAILS.md#p35))
Description: Evaluate and apply stronger on-device data protection for guest/local storage mode.
Acceptance Criteria: Protection policy documented and enabled where feasible.
Regression Risk: Startup/access regressions on locked device states.

- [ ] **P3.6 Remaining UX Polish** ([Details](TODO_DETAILS.md#p36))
Description: Close remaining UX quality gaps across empty states, haptics, and dark-mode readability.
Acceptance Criteria: Every empty tab has polished icon + encouraging copy, key actions emit consistent haptics (success/light/rigid), and tags/categories keep readable contrast in dark mode and custom themes.
Regression Risk: Theme-specific regressions and inconsistent tactile feedback; run cross-tab, cross-theme smoke validation.

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
