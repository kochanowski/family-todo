# Family To-Do - Task Specifications

This document expands each task from `TODO.md` into implementation-level specs.
Use it together with the one-task-at-a-time workflow.

## Current Implementation Snapshot (2026-03-11)

- Production households start empty; sample/demo data is limited to explicit UI-test launch arguments.
- Household leave/delete is local-first, with pending remote cleanup replay and stale CloudKit recovery suppression.
- Shopping Bundles are implemented end to end, including quick add, management UI, curated icon sets, and `Save & Add to List`.
- Contextual TipKit onboarding is live with per-context reset logic, Shopping and Ideas sequences, and Tasks first-run routing to Ideas.
- Retro Dark, Retro Light, and Paper typography support has been expanded broadly; new UI is expected to honor theme fonts during initial implementation.
- Notification UX has moved beyond the original plan: optional task due time, `Default reminder time`, and a daily digest that fires only when tasks are due.

## MVP 1.0 Readiness

## Immediate 2026-03-25 Priorities

## <a id="i10"></a>I1.0 Multi-Device Sync Stabilization
- Objective: finish hardening owner/participant sync so shared household collaboration is trustworthy on physical devices before further polish work.
- Background:
  - current sync model is intentionally asymmetric:
    - owner uses `ownerPrivate`
    - participant uses `participantShared`
  - the near-term goal is not to migrate owner to shared DB, but to make app behavior feel close to symmetric
  - see `docs/current/owner-participant-sync-plan.md`
  - detailed next-step refactor plan: `docs/current/2026-03-25-big-sync-refactor-plan.md`
- In scope:
  - continue phase-2 hardening of the current model
  - verify remote push intake, dedupe, and follow-up refresh behavior for:
    - `Shopping`
    - `Tasks`
    - `Ideas`
    - `Household` metadata
    - `Member` metadata
  - keep owner-side follow-up refresh for participant-originated changes and tighten it using measured device feedback
  - ensure visible screens always refresh the full dependency set required for rendering:
    - `Tasks`: tasks + members + categories
    - `Ideas`: items + categories + members
    - `Shopping`: items + bundles
  - ensure non-list shared metadata also flows through the same durable path:
    - household name
    - household icon
    - member display names
  - keep device-first validation as the source of truth for success, not only unit tests
- Likely files:
  - `FamilyTodo/Stores/HouseholdStore.swift`
  - `FamilyTodo/Services/AppDelegateBridge.swift`
  - `FamilyTodo/Managers/CloudKitSubscriptionManager.swift`
  - `FamilyTodo/Views/TasksView.swift`
  - `FamilyTodo/Views/ShoppingListView.swift`
  - `FamilyTodo/Views/BacklogView.swift`
- Out of scope:
  - migrating owner to `sharedCloudDatabase` as the default model
  - a full sync-engine rewrite before phase-2 hardening is exhausted
- Validation:
  - two physical devices remain in sync in both directions without pull-to-refresh
  - `participant -> owner` is no longer dramatically slower than `owner -> participant`
  - remote changes do not require “kick” actions such as unrelated shopping edits to appear
  - household name/icon and member names sync with the same reliability as tasks and shopping
  - no duplicate or misleading notification copy is produced during sync storms


### Current 2026-03-31 diagnosis
- Latest real-device state after the recent refactor cuts:
  - `owner -> participant` is now much better and often lands in roughly `5-15s` for `Shopping`, with initial household hydration working correctly after join.
  - `participant -> owner` is still the main blocker:
    - owner often does not see `Shopping`, `Ideas`, or `Tasks` changes at all,
    - when changes do appear, they may require minutes or unrelated later triggers.
- The most likely current root cause is no longer record save or join bootstrap.
- Current strongest hypothesis from code inspection:
  - participant writes are landing through the shared-zone save path,
  - owner-side follow-up retry depends on `RemoteCloudChangeContext.databaseScope == .private`,
  - `AppDelegateBridge` currently reads `databaseScope` only from `CKDatabaseNotification`,
  - owner also uses `CKRecordZoneSubscription`,
  - for `CKRecordZoneNotification`, the current app path can leave `databaseScope == nil`,
  - that prevents owner-specific `participantToOwner` follow-up retries from starting,
  - result: owner often performs only one early pass and then stops waiting for delayed participant data.

### Current 2026-03-31 implemented refactor baseline
- Already landed and should be treated as the current baseline:
  - central `HouseholdSyncCoordinator`
  - `HouseholdSyncContext` and `HouseholdSyncContextFactory`
  - `HouseholdRemoteSyncExecutor` seam
  - `HouseholdCloudSnapshotLoader`
  - `HouseholdRepository`
  - early `HouseholdZoneResolver`
  - owner-side target-zone reads before exhaustive fallback
  - same-account recovery split from real invited-member flow
  - iPad/universal layout baseline
- Important constraint for follow-up work:
  - do not restart from a new architecture idea,
  - continue from this baseline and tighten the remaining owner-side trigger/fetch path.

### Next implementation cut: owner push-context normalization
- Goal:
  - make owner treat `participant -> owner` pushes as `private` shared-sync triggers even when the system delivers them as `record-zone` notifications without a declared database scope.
- Production changes:
  - In `FamilyTodo/Services/AppDelegateBridge.swift`:
    - add a tiny inference seam that resolves effective CloudKit database scope from:
      - notification type,
      - declared system scope if present,
      - current `HouseholdSyncContext` when declared scope is missing.
    - keep declared scope authoritative when it exists.
    - infer:
      - `ownerPrivate -> .private`
      - `participantShared -> .shared`
      - only for `recordZone` notifications when scope is missing.
  - In `FamilyTodo/FamilyTodoApp.swift`:
    - inject a current-sync-context provider into `AppDelegateBridge`,
    - source it from `householdStore.currentSyncContext(userId:)`.
  - In `FamilyTodo/Stores/HouseholdStore.swift`:
    - add a defensive fallback so owner-side remote sync still resolves to:
      - `databaseScope = .private`
      - `direction = .participantToOwner`
      - owner follow-up retry delays,
      when the incoming context is `recordZone` with missing scope and the current household belongs to the current user.
    - keep this as backup logic, not the main source of truth.
- Do not change in this cut:
  - record save mapping
  - zone rewrite logic
  - `HouseholdRepository` fetch semantics
  - `HouseholdZoneResolver` behavior
  - schema or invite model

### Tests to add in the next session
- Add focused tests before production edits:
  - `AppDelegateBridge` inference seam:
    - owner sync context + `recordZone` + missing scope -> `.private`
    - participant sync context + `recordZone` + missing scope -> `.shared`
    - declared scope still wins over inference
  - owner-side remote sync path:
    - owner household + `recordZone` push with missing scope still runs `participantToOwner` follow-up hydration
    - delayed shared content appearing on the second hydration pass must still produce `.newData`
- Prefer adding these to existing test files instead of creating a new test target/file set unless needed:
  - `FamilyTodoTests/HouseholdSyncCoordinatorTests.swift`
  - `FamilyTodoTests/HouseholdRemoteSyncTests.swift`

### Device validation immediately after that cut
- Use fresh apps, separate Apple IDs, fresh household, QR join.
- Test only the current blocker path first:
  - `Tel 2 -> Tel 1` add/edit/delete for:
    - `Shopping`
    - `Tasks`
    - `Ideas`
    - `BacklogCategory`
- Success signal:
  - owner starts seeing participant changes in the same short window as current `owner -> participant` sync,
  - no more “never appears until much later” behavior.
- If `Shopping` improves but `Ideas` / `BacklogCategory` still lag badly:
  - next cut should move to owner-side merge/fetch handling for `WorkItem` and `BacklogCategory`,
  - not back to invite/join or save-path debugging.

### Remaining refactor after the push-context fix
- Continue the larger refactor only after validating the owner push-context fix on devices.
- Next architectural steps after that validation:
  - expand `HouseholdRepository` so `HouseholdStore` owns less cloud transport/recovery logic,
  - continue moving zone prep/fallback decisions out of `CloudKitManager` into `HouseholdZoneResolver`,
  - keep converging on one central sync path:
    - trigger
    - context
    - snapshot fetch
    - cache merge
    - typed events
  - only later evaluate zone-token incremental sync,
  - `CKSyncEngine` remains explicitly deferred until the current custom pipeline is more centralized.

## <a id="i11"></a>I1.1 Remote Update UX Cleanup
- Objective: make remote-sync feedback consistent and low-noise across `Tasks`, `Shopping`, and `Ideas`.
- Background:
  - current state:
    - `Tasks`: inline header pill such as `Tasks updated`
    - `Shopping`: inline header pill while visible, top banner for off-screen additions
    - `Ideas`: no dedicated sync indicator, only refreshed content/animation
  - current analysis is saved in `docs/current/2026-03-25-sync-and-update-ux-analysis.md`
- In scope:
  - unify on-screen remote update UX across the three core tabs
  - strongly prefer an icon-led, short-lived header indicator over text-heavy pills
  - keep top-banner treatment only for off-screen shopping additions where count/navigation matters
  - protect bottom navigation labels from wrapping/truncation on narrow devices
  - consider shortening bottom tab copy from `Shopping` to `Shop` while keeping full header title `Shopping`
- Likely files:
  - `FamilyTodo/Managers/CloudKitSubscriptionManager.swift`
  - `FamilyTodo/Views/ShoppingListView.swift`
  - `FamilyTodo/Views/TasksView.swift`
  - `FamilyTodo/Views/BacklogView.swift`
  - `FamilyTodo/Views/Components/SyncStatusPill.swift`
  - `FamilyTodo/Views/Components/NewItemsBanner.swift`
  - `FamilyTodo/ContentView.swift`
  - `FamilyTodo/Views/Components/FloatingTabBar.swift`
  - `FamilyTodo/Utilities/TabBarTypographyManager.swift`
- Out of scope:
  - inventing a new global notification system unrelated to remote sync
  - putting live sync counts into the bottom tab bar
- Validation:
  - on-screen sync feedback is consistent across all three tabs
  - `Shopping` tab label never breaks into awkward wrapped text
  - remote updates remain visible enough to reassure users without filling headers with copy

## <a id="i12"></a>I1.2 Notification Permission Gating by Household Size
- Objective: request notification permission only when notifications can provide real shared-household value.
- Current problem:
  - permission prompt appears too early
  - prompt can be surfaced around `Add Item` even when the user is alone in the household
- In scope:
  - gate notification permission behind multi-member relevance
  - do not request notification permission for solo households during early item-creation flows
  - choose a better trigger such as:
    - after the second active household member joins
    - or the first moment a shared notification could realistically help
  - keep the prompt logic aligned with the real notification strategy in the product
- Likely files:
  - `FamilyTodo/Services/NotificationService.swift`
  - `FamilyTodo/Stores/HouseholdStore.swift`
  - invite/join flow views where member-count transitions are already handled
- Out of scope:
  - redesigning all notification copy in the same task
- Validation:
  - solo users are not prompted prematurely
  - shared households still receive the permission prompt at a meaningful moment
  - prompt is shown once, not repeatedly around member-count changes

## <a id="i13"></a>I1.3 Welcome Carousel Refresh
- Objective: refresh the first-launch carousel using the already-prepared product and HIG analysis.
- Source:
  - `onboarding-flow-claude-analysis.md`
- In scope:
  - update carousel slides to map more directly to actual app value:
    - household organization
    - shopping
    - tasks
    - ideas
    - sync/together
  - fix the layout issues called out in the analysis
  - refresh palette mapping and supporting visual hierarchy where needed
  - keep theme and typography support intact
- Likely files:
  - `FamilyTodo/Views/Onboarding/OnboardingCarouselView.swift`
  - `FamilyTodo/Views/Onboarding/AuroraBackground.swift`
- Out of scope:
  - full redesign of auth or household-setup screens inside this task
- Validation:
  - carousel copy reflects actual MVP value
  - layout remains stable on narrow screens and wider contexts
  - no hardcoded or deprecated screen-size assumptions remain

## <a id="i14"></a>I1.4 Invite Screen Remodel
- Objective: redesign the invite screen so household sharing feels clear, lightweight, and confidence-inspiring.
- In scope:
  - simplify invite screen hierarchy
  - make the main call-to-action obvious
  - present invite code / QR / share behavior in a way that matches the real underlying flow
  - preserve the existing code-based invite mechanism rather than inventing a new transport
- Likely files:
  - invite/share related views in onboarding or household settings flow
  - any supporting components that present code and QR affordances
- Out of scope:
  - backend invite-token redesign in the same task
- Validation:
  - owners immediately understand how to send an invite
  - the screen does not imply unsupported share-link behavior
  - visual hierarchy feels modern and consistent with the rest of the app

## <a id="i15"></a>I1.5 Invite Guidance / "How to Invite" UX
- Objective: make it obvious to a user how to invite someone else to a household and what the other person must do.
- In scope:
  - add clear just-in-time explanatory copy around invite creation
  - explain that the invite is code/QR-based
  - clarify the expected next step for the invited person
  - place this help where users need it, not buried in settings-only text
- Likely files:
  - invite flow screens
  - onboarding household-setup screens
  - possibly `More` / household settings helper text
- Out of scope:
  - long-form FAQ or help center infrastructure
- Validation:
  - first-time users can invite another person without guessing
  - guidance is concise enough to scan quickly
  - invite completion rate should improve during manual testing

## <a id="i16"></a>I1.6 Payments Rollout Readiness
- Objective: prepare the app for monetization only after collaboration fundamentals are stable.
- Preconditions:
  - multi-device sync is reliable
  - invite/join flow is understandable
  - onboarding no longer misleads about product value
- In scope:
  - finish the household-level premium foundation already identified in MVP tasks
  - confirm entitlement resolution is household-first, not user-first
  - prepare the implementation seam for payment integration and release gating
  - define the minimal post-stability rollout plan for enabling payments
- Useful existing roadmap dependencies:
  - `M1.5 Household-Level Premium Schema Foundation`
  - `M1.6 Premium Inheritance Rules (Household Scope)`
  - `M1.7 RevenueCat Preparation Layer`
- Out of scope:
  - shipping billing before sync and invite reliability are acceptable
- Validation:
  - premium state can be introduced without reworking sync architecture
  - collaboration UX is stable enough that monetization does not sit on top of broken core flows

## <a id="i17"></a>I1.7 Member-Driven Invites
- Objective: allow every active household member to invite additional people, not only the owner.
- Background:
  - this fits the shared-first product direction better than routing all growth through one owner-only action
  - invite creation still needs to respect the existing code/QR invite model
- In scope:
  - make invite-entry UI available to all active members
  - ensure any active member can generate or access a valid invite token/code
  - preserve household safety rules where still required:
    - membership validation
    - active-member checks
    - invite revocation/expiration rules
- Likely files:
  - invite-related views in onboarding / household settings
  - `FamilyTodo/Stores/HouseholdStore.swift`
  - `FamilyTodo/Managers/CloudKitManager.swift`
  - invite-token handling code and tests
- Out of scope:
  - redesigning the underlying invite transport away from code/QR
  - broad role-management redesign in the same task
- Validation:
  - owner can still invite
  - non-owner active member can also invite
  - redeemed invite joins the same household correctly
  - household safety and token lifecycle behavior do not regress

## <a id="i18"></a>I1.8 Per-User Recommended Task Limit
- Objective: enforce the recommended/WIP task limit per assignee rather than across all tasks globally.
- Background:
  - the product rule is household coordination, not shared blocking between unrelated members
  - one user's active-task load must not prevent another user from taking work
- In scope:
  - audit current recommended-task / WIP counting logic
  - count only tasks assigned to the relevant user when evaluating the limit
  - keep unassigned-task behavior explicit and documented
  - align any UI explanation with store-side enforcement
- Likely files:
  - `FamilyTodo/Stores/TaskStore.swift`
  - `FamilyTodo/Views/TasksView.swift`
  - task-related tests
- Out of scope:
  - redesigning the overall WIP philosophy
- Validation:
  - one member reaching the limit does not block another member
  - per-user counting is correct for `.next` / active-task logic
  - tests cover mixed-assignee households

## <a id="i19"></a>I1.9 Shared Household Metadata Editing
- Objective: allow every active household member to rename the household and change its icon.
- Background:
  - the household is shared space, so basic non-destructive metadata edits should not require owner-only bottlenecks
  - this must sync cleanly through the same pipeline as other household data
- In scope:
  - remove owner-only restrictions from household name/icon updates where appropriate
  - ensure these updates work from any active member account
  - keep local-first UI update and cloud sync behavior
  - confirm remote devices refresh household metadata without stale cache
- Likely files:
  - `FamilyTodo/Stores/HouseholdStore.swift`
  - `FamilyTodo/Managers/CloudKitManager.swift`
  - `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
  - household settings / edit views
- Out of scope:
  - broader role/permission redesign
  - destructive household actions such as delete/transfer ownership
- Validation:
  - owner can still edit household metadata
  - non-owner active member can edit household metadata
  - household name and icon sync correctly to all devices

## <a id="m10"></a>M1.0 Live Shopping Mode / Last-Minute Alert
- Objective: solve the “I’m at the store, add anything last minute now” household coordination problem with a lightweight shared-presence mode in Shopping.
- Current architecture fit:
  - Good fit for shared state: `Household` is already local-cache + CloudKit synced and participates in household bootstrap/recovery.
  - Good fit for real-time refresh: CloudKit remote notifications already trigger shared-data refresh paths.
  - Partial fit for push: current notification pipeline can surface generic shared updates, but not yet targeted “`<Name>` is at the store” payloads.
  - Important constraint: the current household metadata edit path is owner-only and only updates `name` / `iconSymbol`, so this feature needs a separate presence update path that any active member can use.
- In scope:
  - Add nullable `activeShopperId` to the full `Household` chain:
    - domain model,
    - SwiftData cache model,
    - CloudKit mapping,
    - schema/validator.
  - Add a dedicated `HouseholdStore` flow for shopping presence:
    - `startShopping(userId:)`
    - `finishShopping(userId:)`
    - local-first update of `currentHousehold` + cache,
    - CloudKit sync afterward.
  - Do **not** reuse owner-only `updateCurrentHousehold(...)` metadata editing for this feature.
  - Shopping tab top banner states:
    - idle: full-width CTA `🛒 I'm going shopping!`
    - active shopper: highlighted `🛒 You are shopping right now` banner with `Finish`
    - other member active: informational `🛒 <Name> is shopping right now! Add items quickly.`
  - Resolve shopper display name from current active members; fall back gracefully if member metadata is stale.
  - Bonus UX:
    - disable screen idle timer while the current user is the active shopper,
    - always re-enable it on finish, clear-list reset, and view teardown.
  - Reset rules:
    - explicit `Finish`,
    - `Clear shopping list`,
    - defensive cleanup when the marked shopper leaves the household or the household changes.
  - Notifications:
    - when a user starts shopping, notify all other household members with:
      - title: `🛒 <User Name> is at the store!`
      - body: `Quick, add any last-minute items to the shopping list now.`
    - no notification when finishing shopping unless product explicitly changes this later.
  - Shopping anti-spam:
    - this presence notification is a distinct event and should not be batched together with generic shopping-item changes,
    - normal shopping-item notifications should still remain batched/rate-limited separately.
- Likely files:
  - `FamilyTodo/Models/Household.swift`
  - `FamilyTodo/Models/CachedHousehold.swift`
  - `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
  - `FamilyTodo/Managers/CloudKitManager.swift`
  - `FamilyTodo/Stores/HouseholdStore.swift`
  - `FamilyTodo/Views/ShoppingListView.swift`
  - `FamilyTodo/Managers/CloudKitSubscriptionManager.swift`
  - `cloudkit/schema/housepulse-schema.json`
  - `scripts/cloudkit/validate_schema.sh`
- Out of scope:
  - navigation redesign outside the Shopping banner area,
  - geofencing / auto-detecting store arrival,
  - server-side push provider beyond current CloudKit-driven notification path,
  - multi-shopper simultaneous mode for v1.0.
- Validation:
  - Starting shopping as any active member updates local UI instantly on the acting device.
  - Other household members see the presence banner after CloudKit sync/notification refresh.
  - Non-owner members can start/finish shopping successfully.
  - If another member is already active shopper, the current user sees the informational banner, not the CTA.
  - `Clear shopping list` resets `activeShopperId` to `nil`.
  - Idle timer is disabled only for the active shopper and is always restored afterward.
  - Push copy is specific to the shopping-presence event and does not spam repeatedly during ordinary list edits.

## Phase 1 - Data Integrity & CloudKit

## <a id="p11"></a>P1.1 Replace Silent SwiftData Saves
- Objective: eliminate silent local persistence failures.
- In scope:
  - Replace `try? modelContext.save()` with a shared helper per store.
  - Helper should log source location and set store `error` where appropriate.
- Likely files: `TaskStore.swift`, `ShoppingListStore.swift`, `BacklogStore.swift`, `HouseholdStore.swift`, `MemberStore.swift`, and any helper file used by stores.
- Out of scope: changing business behavior of create/update/delete.
- Validation:
  - Search shows no `try? modelContext.save()` in target stores.
  - Injected save failure surfaces in logs and UI error state.

## <a id="p12"></a>P1.2 Replay Pending Sync Mutations
- Objective: prevent records from staying in `pendingUpload`/`pendingDelete` forever.
- In scope:
  - Add `flushPendingSync()` (or equivalent) in relevant stores.
  - Replay pending uploads/deletes on load/reconnect.
  - Mark synced/remove tombstones on success.
- Likely files: `TaskStore.swift`, `ShoppingListStore.swift`, `BacklogStore.swift`, optionally `MemberStore.swift`.
- Out of scope: full generic outbox model migration.
- Validation:
  - Offline create/update/delete survives restart and syncs after reconnect.

## <a id="p13"></a>P1.3 Add Conflict Policy in Merge (LWW)
- Objective: avoid stale local pending data overwriting fresher cloud data.
- In scope:
  - Update merge paths to compare `updatedAt` for cloud vs pending records.
  - Keep local in-flight mutation priority only while mutation is active.
- Likely files: `TaskStore.swift`, `ShoppingListStore.swift`, `BacklogStore.swift`.
- Out of scope: manual conflict resolution UI.
- Validation:
  - Two-device concurrent edit test keeps newest `updatedAt` result.

## <a id="p14"></a>P1.4 Align Cache Delete Semantics
- Objective: keep tombstone handling consistent across stores.
- In scope:
  - Ensure cache loaders filter `pendingDelete` in all list stores.
  - Confirm merge logic never reintroduces tombstoned records from cache.
- Likely files: `ShoppingListStore.swift` (primary), plus parity checks in `TaskStore.swift` and `BacklogStore.swift`.
- Out of scope: server-side delete policy changes.
- Validation:
  - Deleted entries do not reappear after cold start offline.

## <a id="p15"></a>P1.5 Remove N+1 Cache Sync Queries
- Objective: reduce local DB overhead during sync.
- In scope:
  - Refactor `syncToCache` to single batched fetch + in-memory dictionary merge.
  - Preserve protection for pending local statuses.
- Likely files: `TaskStore.swift`, `ShoppingListStore.swift`, `BacklogStore.swift`.
- Out of scope: query micro-optimizations unrelated to sync.
- Validation:
  - Profiling/logging confirms one fetch per batch, not one per item.

## <a id="p16"></a>P1.6 Add CloudKit Query Pagination
- Objective: avoid missing records when query result exceeds a single page.
- In scope:
  - Add paginated query helper(s) in CloudKit manager.
  - Apply to core fetch paths and invite token lookup queries.
- Likely files: `CloudKitManager.swift`.
- Out of scope: changing record schema or indexes in this task.
- Validation:
  - Dataset > `resultsLimit` is fully returned with cursor loop.

## <a id="p17"></a>P1.7 Move Member Color Migration Off Hot Path
- Objective: stop migration writes on every `fetchMembers()`.
- In scope:
  - Move migration to one-time bootstrap/migration step.
  - Keep fetch path read-focused.
- Likely files: `CloudKitManager.swift`, possibly `HouseholdStore.swift` or app startup flow.
- Out of scope: redesigning member color system.
- Validation:
  - Member fetch performs no per-record migration writes during normal operation.

## <a id="p18"></a>P1.8 Harden Invite Security
- Objective: reduce brute-force and abuse risk in invite flow.
- In scope:
  - Increase invite code length to 8.
  - Add usage/attempt controls and conflict-safe counter updates.
  - Update InviteToken security role constraints in schema scripts/contracts.
- Likely files: `CloudKitManager.swift`, `InviteToken.swift`, `cloudkit/schema/housepulse-schema.json`, `scripts/cloudkit/validate_schema.sh`.
- Out of scope: redesigning invite UX screens.
- Validation:
  - Create/redeem/revoke still works for link/QR/code.

## <a id="p19"></a>P1.9 Complete Push E2E Bridge
- Objective: close the loop from APNs callback to app sync/banner response.
- In scope:
  - Add remote notification callback in `AppDelegateBridge`.
  - Forward payload into `CloudKitSubscriptionManager`.
  - Ensure handling path updates app state/banners and avoids self-noise.
- Likely files: `AppDelegateBridge.swift`, `CloudKitSubscriptionManager.swift`.
- Out of scope: replacing subscription model.
- Validation:
  - Foreground/background push triggers expected refresh behavior.

## <a id="p110"></a>P1.10 Targeted Bulk CloudKit Operations
- Objective: reduce round trips for high-volume writes.
- In scope:
  - Introduce batched `CKModifyRecordsOperation` in selected bulk paths.
  - Keep per-record flows where atomic UX requires it.
- Likely files: `CloudKitManager.swift`, possibly specific store callsites.
- Out of scope: global rewrite of all save paths.
- Validation:
  - Bulk workflows use fewer network operations without correctness regressions.

## Phase 2 - Core Features & UX

## <a id="p21"></a>P2.1 Engaging Empty States
- Objective: deliver first-run-friendly and returning-user empty states across core tabs.
- In scope:
  - Implement two-tier empty states in Shopping, Tasks Active, and Ideas:
    - Tutorial state for first-time empty list.
    - Standard `ContentUnavailableView` after tutorial dismissal/learning.
  - Persist tutorial visibility with `@AppStorage` flags:
    - `hasSeenShoppingTutorial`
    - `hasSeenTasksTutorial`
    - `hasSeenIdeasTutorial`
  - Tutorial CTA buttons mark the respective tutorial as seen.
  - Auto-mark tutorial as seen when list becomes non-empty (user discovered the flow naturally).
  - Keep Tasks empty-state branching:
    - Active + no completed -> "No Tasks Yet".
    - Active empty + completed exists -> "All Caught Up!".
    - Completed empty tab -> "No Completed Tasks".
  - Keep all empty states centered with consistent optical positioning.
- Likely files:
  - `FamilyTodo/Views/ShoppingListView.swift`
  - `FamilyTodo/Views/TasksView.swift`
  - `FamilyTodo/Views/BacklogView.swift`
- Out of scope: full-screen coach marks/overlays and data-layer changes.
- Validation:
  - First launch shows tutorial states when lists are empty.
  - Tapping tutorial CTA permanently switches that tab to standard empty state.
  - Adding first item/task/idea auto-sets tutorial flag.
  - Empty/non-empty transitions do not break list rendering or tab layout.

## <a id="p22"></a>P2.2 Conversational Task Filter Chips
- Objective: improve assignee filtering UX with language-first chips.
- In scope:
  - Introduce conversational filter chips:
    - `All tasks`
    - `My tasks`
    - `[Name]'s tasks`
  - Keep filter state ID-based (`.all`, `.mine`, `.member(UUID)`), independent from display names.
  - Apply filtering consistently to both Active and Completed task tabs.
  - Hide `My tasks` when current member cannot be resolved from session/member list.
  - Prevent duplicate representation of the current user in chip list.
  - Show filtered empty states only when base dataset is non-empty.
- Likely files:
  - `FamilyTodo/Views/TasksView.swift`
- Out of scope: avatar-based filter UI.
- Validation:
  - Chips render in horizontal scroll and update selection state reliably.
  - Task subsets for Active/Completed match selected chip.
  - Current user never appears as both `My tasks` and `[Name]'s tasks`.
  - Filter selection normalizes safely when household membership/session changes.

## <a id="p23"></a>P2.3 Poke Data Model & Mapping
- Objective: introduce `lastPokedAt` end-to-end.
- In scope:
  - Add `lastPokedAt: Date?` to domain `Task`.
  - Add `lastPokedAt` to `CachedTask` with full conversion chain (`init/update/toTask`).
  - Add CloudKit record read/write mapping for `Task.lastPokedAt`.
  - Update CloudKit schema and schema validator required map.
- Likely files:
  - `FamilyTodo/Models/Task.swift`
  - `FamilyTodo/Models/CachedTask.swift`
  - `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
  - `cloudkit/schema/housepulse-schema.json`
  - `scripts/cloudkit/validate_schema.sh`
- Out of scope: poke UI and cooldown interaction logic.
- Validation:
  - `Task -> CachedTask -> CloudKit -> Task` preserves `lastPokedAt`.
  - Missing/`nil` `lastPokedAt` is handled gracefully in mapping.
  - CI schema validation passes with the new field contract.

## <a id="p24"></a>P2.4 Poke Logic & Cooldown UX
- Objective: add poke action with one-per-day cooldown and robust UX.
- In scope:
  - Implement `TaskStore.canPoke(task:)` with calendar-based same-day cooldown.
  - Implement `TaskStore.pokeTask(_:)` optimistic update flow:
    - Update in-memory task.
    - Update cached task sync status.
    - Sync mutation to CloudKit through existing task save path.
  - Add leading swipe action in Tasks Active rows:
    - Visible only for tasks assigned to someone else.
    - Enabled poke state (`hand.wave.fill`) vs cooldown disabled state.
  - Add anti-multitap safeguards (pending mutation guard at UI/store boundary).
- Likely files:
  - `FamilyTodo/Stores/TaskStore.swift`
  - `FamilyTodo/Views/TasksView.swift`
- Out of scope: new push-notification strategy for poke events.
- Validation:
  - Same-day second poke is blocked; next-day poke is allowed.
  - Self-assigned/unassigned tasks do not expose poke action.
  - Rapid taps do not create duplicate poke writes.
  - Local cache reflects poke timestamp immediately and stays consistent after sync.

## <a id="p25"></a>P2.5 Gentle Rewards Expansion
- Objective: enrich celebration messaging logic without gamification.
- In scope:
  - Extend `CelebrationManager` decision engine with explicit tiers:
    - `milestone` > `surprise` > `fallback`.
  - Add milestone and surprise message pools with deterministic fallback behavior.
  - Enforce surprise cap at most once per 7 days (persisted in `UserDefaults`).
  - Keep completion-trigger wiring in Tasks flow with weekly completion count input.
  - Respect `ThemeStore.celebrationsEnabled` toggle for all user-facing celebration output.
- Likely files:
  - `FamilyTodo/Services/CelebrationManager.swift`
  - `FamilyTodo/Stores/TaskStore.swift`
  - `FamilyTodo/Views/TasksView.swift`
- Out of scope: points/ranking system.
- Validation:
  - Milestone tier overrides surprise/fallback when threshold is met.
  - Surprise messages never appear more than once per 7 days.
  - Fallback messages are used when milestone/surprise criteria are not met.
  - No celebration toast/confetti appears when `celebrationsEnabled == false`.

## <a id="p26"></a>P2.6 Round-Robin Recurring Task Rotation
- Status: parked on `feature/recurring-tasks`; removed from the active roadmap/runtime scope while work continues on `feature/next-features`.
- Objective: deliver a fully working recurring-task engine first, then layer deterministic round-robin assignment.
- In scope:
  - Core engine first (blocking requirement):
    - When a recurring task is marked `.done`, immediately generate/schedule the next instance from recurrence rules (`daily/weekly/monthly/custom`).
    - Next instance must be created as `.backlog` (not `.next`) to avoid active-list clutter.
    - Update recurring metadata (`lastGeneratedDate`, `nextScheduledDate`) after successful generation.
    - Add idempotency guard (`recurringChoreId + dueDate`) so completion retries never create duplicates.
  - Keep startup scheduler as catch-up/repair path, but do not rely on app launch as the primary generation trigger.
  - Round-robin phase (after core generation is stable):
    - Add persistent cursor `nextAssigneeIndex` to recurring chore domain/cache/cloud mapping.
    - Assign new instance by cursor when rotation is enabled, then advance cursor (`(idx + 1) % count`).
    - Normalize cursor on assignee-list edits: `nextAssigneeIndex = min(cursor, max(0, count - 1))`.
  - UI/UX requirements:
    - Create/edit recurring task UI supports multi-assignee selection (checkmarks / multi-select list).
    - Add `Toggle("Rotate between assignees")`.
    - Task row shows `arrow.triangle.2.circlepath` indicator near assignee for rotating recurring tasks.
    - Task detail shows helper line: `Next up: <Member Name>`.
- Likely files:
  - `FamilyTodo/Models/LegacyStubs.swift` (RecurringChore / CachedRecurringChore / ChoreScheduler / RecurringChoreStore)
  - `FamilyTodo/Stores/TaskStore.swift` (completion hook to generation engine)
  - `FamilyTodo/Views/MoreView.swift` (RepetitiveTasksView multi-assignee + rotate toggle)
  - `FamilyTodo/Views/TasksView.swift` (TaskRow indicator + detail annotation)
  - `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
  - `cloudkit/schema/housepulse-schema.json`
  - `scripts/cloudkit/validate_schema.sh`
- Out of scope:
  - Creating successor recurring tasks directly in `.next`.
  - Full redesign of recurring screens beyond required controls and indicators.
- Validation:
  - Completing recurring task generates exactly one successor task immediately in `.backlog`.
  - Successor due date follows recurrence settings and remains stable across restart/retry.
  - Rotation sequence is deterministic (A->B->A...) and survives app restart + cloud sync.
  - Cursor remains valid after assignee reorder/remove.
  - UI controls are discoverable and reflect data correctly (multi-assignee, toggle, row icon, next-up hint).

## <a id="p27"></a>P2.7 Shopping Bundles End-to-End
- Objective: reusable shopping bundles with quick add.
- In scope:
  - Add `ShoppingBundle` model (`id`, `householdId`, `name`, `icon`, `items`, `createdAt`, `updatedAt`, optional `sortOrder`).
  - Persist bundle items in CloudKit-safe serialized form (`itemsJSON`) to keep schema/validator stable.
  - Add `CachedShoppingBundle` with full conversion chain (`init/update/toModel`) and sync metadata.
  - Add `ShoppingBundleStore` with offline-first load/merge and CRUD operations.
  - Add bundle CloudKit CRUD + mapping + schema/validator entries.
  - Shopping header UX: add bundles icon (`archivebox` or `square.grid.3x3.fill`) in top-right action cluster, between Trash and Recently Purchased, opening `BundlesManagementView`.
  - Quick add UX: long-press on main `+ Add Item` opens native context menu (or sheet fallback) with available bundles; tap adds all bundle items instantly.
  - Post-add feedback: show short success feedback (`Added <Bundle Name> (<N> items)`).
  - `BundlesManagementView`: simple list of bundles; tapping bundle opens detail editor with bundle name field + add/remove item flow similar to regular shopping list ergonomics.
  - Ensure quick add reuses existing shopping create path (normalization/dedup/sync behavior parity).
- Likely files:
  - New: `FamilyTodo/Models/ShoppingBundle.swift`
  - New: `FamilyTodo/Models/CachedShoppingBundle.swift`
  - New: `FamilyTodo/Stores/ShoppingBundleStore.swift`
  - New: `FamilyTodo/Views/BundlesManagementView.swift`
  - `FamilyTodo/Views/ShoppingListView.swift`
  - `FamilyTodo/Stores/ShoppingListStore.swift`
  - `FamilyTodo/Managers/CloudKitManager.swift`
  - `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
  - `FamilyTodo/FamilyTodoApp.swift`
  - `FamilyTodo/Utilities/SwiftDataContainerFactory.swift`
  - `cloudkit/schema/housepulse-schema.json`
  - `scripts/cloudkit/validate_schema.sh`
- Out of scope: recipe import and automatic bundle generation.
- Validation:
  - Bundle CRUD works in local-only and cloud mode.
  - `itemsJSON` encode/decode round-trip is stable (including empty and multi-item bundles).
  - Quick add inserts every bundle item exactly once per tap.
  - Long-press discovery flow is responsive and does not block regular add-item flow.
  - Header icon placement is clear and consistent with Shopping actions.
  - Quick add always emits confirmation feedback with correct item count.

## <a id="p28"></a>P2.8 Contextual Onboarding (TipKit)
- Objective: guide users to discover advanced features without blocking their workflow.
- In scope:
  - Use native iOS TipKit presentation with safe `Tips.configure()` startup and `.displayFrequency(.immediate)`.
  - Reset TipKit datastore and local onboarding progress only when the effective app context changes (`sessionMode | userId | householdId`), not on every cold start.
  - Shopping onboarding sequence:
    - `first add` tip on the main add control for a truly empty shopping flow.
    - `recently purchased` tip after the first bought item exists.
    - `bundles location` tip after first-item discovery, before bundle quick add has been learned.
    - `bundle quick add` tip as the final Shopping step when bundles exist.
  - Ideas onboarding sequence:
    - `create category`
    - `add idea`
    - `assign owner`
    - `promote`
  - Tasks onboarding is split:
    - empty-state CTA routes users to `Ideas` to create the first task through the intended planning flow,
    - swipe-actions TipKit guidance remains for non-empty Active task lists.
  - Screen-level priority helpers must guarantee only one tip is active per screen at a time.
- Likely files: `FamilyTodoApp.swift`, `ShoppingListView.swift`, `BacklogView.swift`, `TasksView.swift`, `Services/AppTips.swift`.
- Out of scope: full-screen blocking tutorials.
- Validation:
  - Tips render only when matching their state rules and do not overlap on the same screen.
  - Context reset makes onboarding reappear for a new user or new household on the same device.
  - Shopping sequence progresses in order: first add -> recently purchased -> bundles -> quick add.
  - Ideas sequence progresses in order: create category -> add idea -> assign owner -> promote.
  - Tasks empty state routes to `Ideas`, while non-empty Active lists can still teach swipe actions.
  - Tip dismissal is graceful and non-blocking.
  - Tip placement anchors to intended controls without obscuring primary actions.
  - Inline tips do not cause disruptive layout shifts.
  - Startup remains stable with `Tips.configure()`.

## <a id="p29"></a>P2.9 Push Message Enrichment via Activity Log
- Objective: make notifications contextual and useful.
- In scope:
  - Use ActivityLog as primary source for message text in push/in-app update pipeline.
  - Keep `CKDatabaseSubscription` as shared DB foundation (do not rely on query-only path).
  - Build personalized templates by activity type for lock screen readability:
    - "`<Name>` bought: `<item list>`"
    - "`<Name>` completed task: `<task>`"
  - Filter out self events (`activity.userId == current user`) and suppress duplicate deliveries.
  - Add de-dup cache keyed by `activityLog.id` (or equivalent stable identifier).
  - If app is foregrounded and remote action comes from another household member, show non-invasive in-app top banner (auto-dismiss ~3 seconds).
  - Keep generic fallback banner/message when no parseable activity event is available.
- Likely files:
  - `FamilyTodo/Managers/CloudKitSubscriptionManager.swift`
  - `FamilyTodo/Services/AppDelegateBridge.swift` (verification of forwarding path)
  - `FamilyTodo/Stores/ActivityLogStore.swift` (query helpers for latest events)
  - Optional: `FamilyTodo/Views/SettingsView.swift` (partner-updates toggle)
- Out of scope: server-side random notification copy generation.
- Validation:
  - Notifications are contextual ("who did what") for non-self events.
  - No duplicate notification storms from repeated sync callbacks.
  - Foreground/background behavior remains stable on two devices and two accounts.
  - Foreground in-app banner appears only for remote non-self events and disappears automatically.
  - Push copy is understandable on lock screen without opening the app.

## <a id="p210"></a>P2.10 Activity Log End-to-End
- Objective: transparent audit trail for household actions.
- In scope:
  - Add `ActivityLog` model (`id`, `householdId`, `actionType`, `userId`, `userName`, `itemName`, `timestamp`).
  - Add `CachedActivityLog` and offline-first `ActivityLogStore` (`load`, `sync`, `logAction`).
  - Define action mapping contract:
    - `taskCreated` -> `TaskStore.createTask(...)`
    - `taskCompleted` -> `TaskStore.moveTask(_:to: .done)`
    - `shoppingItemAdded` -> `ShoppingListStore.createItem(...)` - czy będziemy logować każdy item w shopping?
    - `shoppingItemBought` -> `ShoppingListStore.toggleBought(...)` on transition to bought - czy będziemy logować każdy item w shopping? trzeba to przemyśleć jeszcze raz - za i przeciw
  - Keep logging calls in stores (single source of truth), not view layer callbacks.
  - Add Activity Log entry point in More tab above technical settings using icon `clock.arrow.circlepath`.
  - Implement `ActivityLogView` as timeline/feed:
    - left: avatar or initials in circle
    - center: readable sentence (actor + action + item)
    - trailing/bottom: relative time (`2h ago`, `Yesterday`)
  - Add friendly empty state with large SF Symbol and text equivalent to "Nothing happened yet".
  - Add CloudKit record type + mapping + schema contract (query by `householdId`, sort by `timestamp`).
- Likely files:
  - New: `FamilyTodo/Models/ActivityLog.swift`
  - New: `FamilyTodo/Models/CachedActivityLog.swift`
  - New: `FamilyTodo/Stores/ActivityLogStore.swift`
  - New: `FamilyTodo/Views/ActivityLogView.swift`
  - `FamilyTodo/Stores/TaskStore.swift`
  - `FamilyTodo/Stores/ShoppingListStore.swift`
  - `FamilyTodo/Views/MoreView.swift`
  - `FamilyTodo/Managers/CloudKitManager.swift`
  - `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
  - `FamilyTodo/FamilyTodoApp.swift`
  - `FamilyTodo/Utilities/SwiftDataContainerFactory.swift`
  - `cloudkit/schema/housepulse-schema.json`
  - `scripts/cloudkit/validate_schema.sh`
- Out of scope: moderation/admin role permissions for log visibility.
- Validation:
  - Correct action type + actor attribution for defined events.
  - Newest-first ordering in UI and cloud-synced data.
  - No missing log entries during offline mutations followed by reconnect.
  - Timeline remains readable on narrow screens and long item names.
  - Empty state is shown only when there are zero log entries.

## Phase 3 - Polish & Future

## <a id="p31"></a>P3.1 Versioned SwiftData Schema Framework
- Objective: introduce formal migration scaffold.
- In scope: define versioned schema baseline and migration plan skeleton.
- Out of scope: full migration of every planned model change in this task.
- Validation: app boots with migration infrastructure enabled.

## <a id="p32"></a>P3.2 Evaluate Relationship/Cascade Migration
- Objective: assess move from UUID-linked models to relationship-based cascade safety.
- In scope: technical RFC-level evaluation and guarded implementation path.
- Out of scope: broad refactor unless explicitly accepted.
- Validation: documented decision and safe deletion behavior in tested paths.

## <a id="p33"></a>P3.3 Evaluate Zone-Scoped Subscriptions
- Objective: decide if zone-scoped subscriptions are needed for future multi-household usage.
- In scope: design/benchmark against current DB subscription approach.
- Out of scope: forced migration now.
- Validation: explicit technical decision with constraints and migration plan.

## <a id="p34"></a>P3.4 Sharing Role UX Enhancements
- Objective: make household roles visible and safely manageable from UI.
- In scope:
  - Household member list shows subtle gray role badge under each name (`Owner`, `Member`, `Read-only`).
  - Owner-only member actions on tap via action sheet:
    - `Change Role`
    - `Transfer Ownership`
    - `Remove from Household`
  - Destructive actions (`Transfer Ownership`, `Remove`) must be red and require explicit confirmation alert.
  - Non-owner users cannot access privileged role-management actions.
- Out of scope: full RBAC/permission-system redesign.
- Validation:
  - Role badges render correctly for all members.
  - Owner-only action sheet visibility is permission-correct.
  - Destructive confirmations prevent accidental ownership transfer/removal.
  - Membership flows (leave/delete/invite) remain stable after role changes.

## <a id="p35"></a>P3.5 Guest Data Protection Hardening
- Objective: improve data-at-rest protection in guest/local mode.
- In scope: evaluate/apply feasible platform protections and document constraints.
- Out of scope: custom crypto layer unless explicitly required.
- Validation: protection policy is documented and verified on supported devices.

## <a id="p36"></a>P3.6 Remaining UX Polish
- Objective: close remaining visual consistency and tactile-feedback gaps.
- In scope:
  - Empty-state quality pass: each empty tab/screen uses polished icon + supportive copy (no blank white states).
  - Haptics consistency pass:
    - task completion -> success feedback
    - adding shopping item -> light impact
    - deleting item -> rigid impact
  - Dark-mode/theme contrast verification for tags/categories so they neither glow nor blend into background.
  - Preserve existing WIP/sign-out/theme polish tasks where already planned.
- Out of scope: new feature additions unrelated to UX consistency.
- Validation:
  - Empty states are visually complete across Shopping/Tasks/Ideas/Activity Log surfaces.
  - Haptic mapping is consistent across repeated interactions.
  - Dark mode and alternate themes pass readability checks for chips/tags/categories.

## <a id="p37"></a>P3.7 Post-MVP Household Sync Hardening
- Objective: keep the current MVP-acceptable sync behavior stable, then finish the remaining CloudKit sync hardening without reopening the large regressions already fixed.
- Current known state to preserve:
  - `owner -> participant` is healthy on the hot path and now runs `delta-first` after push.
  - `participant -> owner` is acceptable for MVP, but still effectively depends on owner-side fallback cadence because owner runtime logs still do not prove a reliable push-triggered path.
  - full household snapshots are no longer the preferred hot path for shopping-only changes and should remain a safety net, not the default.
- In scope after MVP:
  - Complete the owner push / subscription / remote notification audit using code + runtime logs only:
    - confirm whether owner should ever receive participant-originated remote notifications in the current sharing architecture,
    - verify exact subscription types and target databases/zones per role,
    - verify AppDelegate intake and scope inference for owner-side CloudKit notifications.
  - Finish the delta-first transport architecture:
    - add proper token persistence / reset handling for shared DB and owner private zone change streams,
    - move participant shared path from zone-only delta toward Apple-style shared database changes -> changed zones -> zone changes,
    - keep full snapshot only for bootstrap, token expiration, unresolved zones, explicit repair, or manual debug refresh.
  - Reduce remaining trigger asymmetry:
    - if owner push proves dependable, prefer push-triggered owner refresh,
    - if owner push remains unreliable, formalize owner fallback as a repair mechanism only and tune cadence conservatively.
  - Tighten participant-side follow-up behavior after delta:
    - ensure repeated push bursts do not queue unnecessary extra passes,
    - keep follow-up retries only when they capture real additional changes.
  - Add final observability needed for future sync debugging:
    - clear trigger provenance (`push`, `ownerFallback`, `foregroundRepair`, `appBecameActive`, `manual`),
    - delta token state updates / resets,
    - explicit owner push health indicators in diagnostics UI,
    - startup/join diagnostics that explain `No Household Active` / long `Loading household...` cases.
  - Revisit participant startup / existing-household recovery:
    - prevent transient routing to empty/setup when a trusted local household or pending-join context exists,
    - make join hydration and startup recovery stages diagnosable without reading raw logs.
- Likely files:
  - `FamilyTodo/Managers/CloudKitManager.swift`
  - `FamilyTodo/Managers/CloudKitSubscriptionManager.swift`
  - `FamilyTodo/Services/AppDelegateBridge.swift`
  - `FamilyTodo/Services/CloudKitChangeTokenStore.swift`
  - `FamilyTodo/Services/HouseholdStoreSyncEngine.swift`
  - `FamilyTodo/Services/HouseholdSyncCoordinator.swift`
  - `FamilyTodo/Stores/HouseholdStore.swift`
  - `FamilyTodo/Services/CloudKitDiagnosticsState.swift`
  - `FamilyTodo/Views/Components/CloudKitDiagnosticsBanner.swift`
- Out of scope for MVP:
  - re-architecting collaboration away from CloudKit sharing,
  - aggressive polling as a permanent primary sync design,
  - broad UI rewrites unrelated to trigger/fetch/cache correctness.
- Validation:
  - two real devices, two Apple IDs, existing collaborative household,
  - `shopping items`, `shopping bundles`, `ideas`, and promotion to `tasks` validated in both directions,
  - logs prove whether each sync pass was push-driven or fallback-driven,
  - no routine `delta.fallbackToSnapshot` on shopping-only edits,
  - no return of multi-minute sync tails caused by full hydration snapshots on hot paths,
  - participant startup/update no longer intermittently shows `No Household Active` without a diagnostic explanation.
