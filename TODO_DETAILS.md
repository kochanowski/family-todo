# HousePulse - Task Specifications

This document expands each task from `TODO.md` into implementation-level specs.
Use it together with the one-task-at-a-time workflow.

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
- Objective: complete empty-state UX in key tabs.
- In scope:
  - Add/align `ContentUnavailableView` in Shopping, Tasks Active, Ideas.
  - Ensure CTA behavior is actionable.
- Likely files: `ShoppingListView.swift`, `TasksView.swift`, `BacklogView.swift`.
- Validation: empty/non-empty transitions work without layout regressions.




**Context:**
We are working on task P2.1 from our TODO.md. We need to implement engaging empty states for our main lists using iOS 17's `ContentUnavailableView`.

**Action:**
Please update the following views to show a `ContentUnavailableView` when their respective data arrays are empty.

**1. ShoppingListView (when items array is empty):**
- Icon: `cart.badge.plus`
- Title: "Your List is Empty"
- Description: "Time to restock! Add groceries or household items you need to buy."

**2. TasksView - Active Tab (when active tasks array is empty):**
- Icon: `sparkles`
- Title: "All Caught Up!"
- Description: "The house is looking great. Enjoy your free time or create a new task."

**3. TasksView - Completed Tab (when completed tasks array is empty):**
- Icon: `checkmark.circle`
- Title: "No Completed Tasks"
- Description: "Tasks you finish will appear here."

**4. IdeasView (when ideas array is empty):**
- Icon: `lightbulb`
- Title: "No Ideas Yet"
- Description: "Capture home improvement projects, wishlists, or future plans here."

**Implementation Details:**
- Use the standard `ContentUnavailableView(title: String, systemImage: String, description: Text)` initializer.
- Ensure the empty state is centered on the screen and replaces the `List` or `ScrollView` when the data is empty.
- Do not modify any CloudKit or data saving logic. Focus purely on the UI layer.

## Task: Execute P2.1 - Two-Tier Engaging Empty States (Tutorial vs Standard)

**Context:**
We are working on task P2.1. Instead of just a simple empty state, we want a "Two-Tier" approach for our main tabs (Shopping, Tasks, Ideas) to improve the First-Time User Experience (FTUX).

**Logic Requirements:**
1. Use `@AppStorage` flags for each tab (e.g., `hasSeenShoppingTutorial`, `hasSeenTasksTutorial`, `hasSeenIdeasTutorial`) defaulting to `false`.
2. If the list is empty AND the flag is `false`, show the **Tutorial Empty State** (with a button to dismiss it).
3. If the list is empty AND the flag is `true`, show the **Standard Empty State** (using `ContentUnavailableView`).
4. When the user taps the button in the Tutorial state, set the respective `@AppStorage` flag to `true`. (Also, automatically set it to `true` if the list is no longer empty, meaning they figured out how to add an item).

**Content for Shopping:**
- **Tutorial State:**
  - Icon: `cart.fill.badge.plus`
  - Title: "Welcome to Shopping!"
  - Description: "Add groceries and household items here. Once bought, they save to your history for quick re-adding later!"
  - Button: "Got it!" (Sets flag to true)
- **Standard State:** `ContentUnavailableView("Your List is Empty", systemImage: "cart.badge.plus", description: Text("Time to restock!"))`

**Content for Tasks (Active):**
- **Tutorial State:**
  - Icon: `checkmark.square.fill`
  - Title: "Master Your Chores"
  - Description: "Keep your home organized. Add daily chores, assign them, or convert your big Ideas into actionable tasks."
  - Button: "Let's Go!" (Sets flag to true)
- **Standard State:** `ContentUnavailableView("All Caught Up!", systemImage: "sparkles", description: Text("The house is looking great."))`

**Content for Ideas:**
- **Tutorial State:**
  - Icon: `lightbulb.fill`
  - Title: "Your Home's Brainstorming Hub"
  - Description: "Planning a renovation? Want a new sofa? Drop your ideas here. When ready, turn them into Tasks."
  - Button: "Start Dreaming" (Sets flag to true)
- **Standard State:** `ContentUnavailableView("No Ideas Yet", systemImage: "lightbulb", description: Text("Capture home improvement projects or wishlists here."))`

**Action:**
Please implement this two-tier empty state logic for ShoppingListView, TasksView (Active tab), and IdeasView. Keep the UI clean and native-looking.






## <a id="p22"></a>P2.2 Conversational Task Filter Chips
- Objective: improve assignee filtering UX with language-first chips.
- In scope:
  - Add `All tasks`, `My tasks`, `[Name]'s tasks` chips.
  - Keep filter type ID-based (`.member(UUID)`).
  - Apply to Active and Completed.
- Likely files: `TasksView.swift`.
- Out of scope: avatar-based filter UI.
- Validation: no duplicate current-user chip; filters toggle reliably.

## <a id="p23"></a>P2.3 Poke Data Model & Mapping
- Objective: introduce `lastPokedAt` end-to-end.
- In scope:
  - Add field to domain model, cache model, CloudKit mapping.
  - Update schema JSON and validator contract.
- Likely files: `Task.swift`, `CachedTask.swift`, `CloudKitManager+Mapping.swift`, schema files.
- Validation: round-trip `Task -> cache -> cloud -> Task` preserves value.

## <a id="p24"></a>P2.4 Poke Logic & Cooldown UX
- Objective: add poke action with one-per-day cooldown and robust UX.
- In scope:
  - Implement `canPoke` and `pokeTask` with optimistic update + sync.
  - Add leading swipe action for non-self assigned tasks.
  - Add anti-multitap guard and disabled cooldown state.
- Likely files: `TaskStore.swift`, `TasksView.swift`.
- Validation: same-day repeat poke blocked, cross-day poke allowed.

## <a id="p25"></a>P2.5 Gentle Rewards Expansion
- Objective: enrich celebration messaging logic without gamification.
- In scope:
  - Extend message pools and priority (milestone > surprise > fallback).
  - Enforce surprise cap (max once/week).
  - Keep UI trigger decision in view layer.
- Likely files: `CelebrationManager.swift`, `TaskStore.swift`, `TasksView.swift`.
- Out of scope: points/ranking system.
- Validation: message priority and toggle behavior (`celebrationsEnabled`) are correct.

## <a id="p26"></a>P2.6 Round-Robin Recurring Task Rotation
- Objective: deterministic rotation for recurring chores.
- In scope:
  - Add persistent rotation cursor and generation updates.
  - Normalize cursor when assignee set changes.
- Likely files: recurring chore model/store/scheduler and CloudKit mapping/schema.
- Validation: A->B->A assignment pattern over repeated generations.

## <a id="p27"></a>P2.7 Shopping Bundles End-to-End
- Objective: reusable shopping bundles with quick add.
- In scope:
  - Bundle model/cache/store/cloud mapping.
  - Bundles management UI and long-press quick add from Shopping.
- Likely files: new bundle model/store/view files + shopping/cloud integration.
- Validation: bundle CRUD + one-tap add all items works locally and via cloud sync.

## <a id="p28"></a>P2.8 Activity Log End-to-End
- Objective: transparent audit trail for household actions.
- In scope:
  - ActivityLog model/cache/store/view.
  - Integrate logging in task/shopping actions with required `userId`.
- Likely files: activity log files + `TaskStore.swift` + `ShoppingListStore.swift` + `MoreView.swift`.
- Validation: correct actor/action entries across devices.

## <a id="p29"></a>P2.9 Push Message Enrichment via Activity Log
- Objective: make notifications contextual and useful.
- In scope:
  - Use activity events for user-facing push/in-app messages.
  - Keep de-dup and self-noise suppression.
- Likely files: `CloudKitSubscriptionManager.swift` plus activity log integration points.
- Validation: notifications show "who did what" without duplicate spam.

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
- Objective: improve share-role operations (owner transfer / read-only option).
- In scope: product and UX spec, then implementation if approved.
- Out of scope: permission model overhaul not backed by product decision.
- Validation: role flows do not break leave/delete/member actions.

## <a id="p35"></a>P3.5 Guest Data Protection Hardening
- Objective: improve data-at-rest protection in guest/local mode.
- In scope: evaluate/apply feasible platform protections and document constraints.
- Out of scope: custom crypto layer unless explicitly required.
- Validation: protection policy is documented and verified on supported devices.

## <a id="p36"></a>P3.6 Remaining UX Polish
- Objective: finish deferred UX consistency tasks.
- In scope: WIP hard-enforcement consistency, sign-out overlap fixes, theme polish.
- Out of scope: unrelated feature work.
- Validation: no regressions across tabs/themes and key flows.
