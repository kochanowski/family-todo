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
