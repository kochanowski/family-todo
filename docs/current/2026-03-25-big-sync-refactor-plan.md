# Big Sync Refactor Plan

Last updated: 2026-03-25

## Why this plan exists

Phase-2 hardening improved some paths, but real-device tests still show one major problem:

- `participant -> owner` is slow but generally converges
- `owner -> participant` is still too random, especially for `Tasks` and `Ideas`

That strongly suggests the remaining issue is no longer just retry tuning. The app still has too many distributed sync decisions spread across stores, views, notifications, and remote refresh helpers.

This plan defines the next-step refactor: one central household sync pipeline.

## Current problem statement

Today the app reacts to sync changes through a mix of:

- `AppDelegateBridge`
- `CloudKitSubscriptionManager`
- `HouseholdStore`
- view-level refresh logic in `ShoppingListView`, `TasksView`, and `BacklogView`
- per-store cache rehydrate helpers

That creates several failure modes:

- different behavior per domain (`Shopping` vs `Tasks` vs `Ideas`)
- different behavior per direction (`owner -> participant` vs `participant -> owner`)
- partial refreshes where one dependency updates but another stays stale
- UI feedback that is calculated in more than one place
- too much dependence on which screen is currently open

## Scope of the refactor

This refactor covers all shared household data that should feel live across devices:

- `Household`
  - `name`
  - `iconSymbol`
  - future shared household metadata
- `Member`
  - `displayName`
  - role / membership state
- `ShoppingItem`
- `ShoppingBundle`
- `WorkItem`
  - task-like items
  - idea-like items
- `BacklogCategory`

This means the sync engine must treat household metadata and member metadata as first-class synced state, not as side concerns.

## Target architecture

One pipeline:

`CloudKit signal -> HouseholdSyncCoordinator -> fetch snapshot/delta -> merge cache -> compute typed diff -> publish domain events -> UI reacts`

Rules:

- one active sync pass per household
- one source of truth for remote diffs
- one place that decides whether a follow-up refresh is needed
- one event model for UI, notifications, and telemetry

## Main new component

### `HouseholdSyncCoordinator`

New responsibility:

- accept sync triggers
- serialize and deduplicate sync work
- perform household-level fetch
- merge to local cache
- produce typed sync events
- expose sync diagnostics

Expected inputs:

- `remotePush`
- `appDidBecomeActive`
- `manualRefresh`
- `localMutationFollowUp`
- `householdJoined`
- `householdSwitched`

Expected outputs:

- updated SwiftData cache
- typed sync events for UI
- notification intents
- telemetry/diagnostics payloads

## Data model for the refactor

### `HouseholdSyncReason`

Purpose:

- classify why the sync is running
- help telemetry and retry strategy

Suggested cases:

- `remotePush(databaseScope:notificationType:)`
- `appBecameActive`
- `manualPullToRefresh`
- `localMutationFollowUp`
- `householdJoined`
- `householdSwitched`
- `debugRepair`

### `HouseholdSyncSnapshot`

This is the fetched household graph for one sync pass.

Minimum contents:

- `household`
- `members`
- `shoppingItems`
- `shoppingBundles`
- `workItems`
- `backlogCategories`

Optional:

- legacy fallback records if still required during transition

Important:

- the snapshot must represent one coherent fetch result
- views should not have to re-fetch dependent models on their own

### `HouseholdVisibleStateSnapshot`

Purpose:

- represent the user-visible state after cache merge
- drive one diff source of truth

Minimum tracked state:

- household metadata:
  - `householdID`
  - `name`
  - `iconSymbol`
  - `updatedAt`
- member metadata:
  - `memberID`
  - `displayName`
  - `role`
  - `isActive`
  - `updatedAt` if available, otherwise a stable signature
- shopping item visible state
- shopping bundle visible state
- work item visible state
- backlog category visible state

### `HouseholdSyncEvent`

Purpose:

- one typed event contract for UI and notification logic

Suggested domains:

- `householdMetadataChanged`
- `membersChanged`
- `shoppingAdded`
- `shoppingUpdated`
- `shoppingRemoved`
- `shoppingBundlesChanged`
- `tasksChanged`
- `ideasChanged`
- `backlogCategoriesChanged`
- `fullRefresh`

Shared payload:

- `householdID`
- `batchID`
- `source`
- `reason`
- `timestamp`
- changed IDs
- direction if inferable:
  - `ownerToParticipant`
  - `participantToOwner`
  - `unknown`

## Detailed implementation phases

## Phase A: Create the coordinator without changing product behavior

Goal:

- introduce the new central sync surface while keeping existing behavior alive

Tasks:

- create `HouseholdSyncCoordinator`
- give it one serial execution path per active household
- move remote push entry from `AppDelegateBridge` to the coordinator
- move foreground repair entry to the coordinator
- keep old downstream refresh logic temporarily, but trigger it only through the coordinator

Files likely involved:

- `FamilyTodo/Services/AppDelegateBridge.swift`
- `FamilyTodo/Stores/HouseholdStore.swift`
- new sync coordinator file(s) under `FamilyTodo/Services` or `FamilyTodo/Stores`

Success criteria:

- no parallel household sync passes race each other
- remote push and app-active refresh now enter through one gateway

## Phase B: Create one household-level fetch contract

Goal:

- replace domain-by-domain fetch assumptions with one coherent household graph fetch

Tasks:

- define `HouseholdSyncSnapshot`
- implement one fetch path that always retrieves:
  - `Household`
  - `Member`
  - `ShoppingItem`
  - `ShoppingBundle`
  - `WorkItem`
  - `BacklogCategory`
- preserve fallback handling only where still needed for compatibility
- remove assumptions that `Tasks` or `Ideas` can refresh independently of members/categories

Files likely involved:

- `FamilyTodo/Managers/CloudKitManager.swift`
- `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
- `FamilyTodo/Stores/HouseholdStore.swift`
- new coordinator file(s)

Success criteria:

- one sync pass can fully reconstruct a consistent household graph
- household name/icon and member names refresh through the same pass as tasks and shopping

## Phase C: Centralize merge and diff

Goal:

- one place merges cloud data into local cache and computes what changed

Tasks:

- move post-fetch merge responsibility into the coordinator or one dedicated merge helper
- compute `before` and `after` `HouseholdVisibleStateSnapshot`
- produce a single typed diff from those snapshots
- stop deriving banner counts, inline feedback, and animation batches from separate ad hoc logic

Files likely involved:

- `FamilyTodo/Stores/HouseholdStore.swift`
- `FamilyTodo/Managers/CloudKitSubscriptionManager.swift`
- new snapshot/diff helper file(s)

Success criteria:

- one remote batch produces one diff
- shopping/task/idea/household/member changes all flow from the same diff engine

## Phase D: Typed event publication

Goal:

- replace loose refresh notifications with typed domain events

Tasks:

- define `HouseholdSyncEvent`
- publish events from the coordinator after merge
- keep a compatibility bridge for any old `NotificationCenter` names during transition
- make notification/banner logic consume typed events instead of rebuilding state independently

Files likely involved:

- new sync event types
- `FamilyTodo/Managers/CloudKitSubscriptionManager.swift`
- `FamilyTodo/Services/NotificationService.swift`
- `FamilyTodo/ContentView.swift`

Success criteria:

- UI and notifications react to explicit events such as `shoppingAdded` or `householdMetadataChanged`
- fewer places need to interpret raw CloudKit push context

## Phase E: Thin-view migration

Goal:

- remove per-screen mini sync engines

Tasks:

- migrate `ShoppingListView` to:
  - read local cache/store state
  - react only to typed sync events for:
    - inline update indicator
    - animation
    - optional banner/navigation affordance
- migrate `TasksView` the same way
- migrate `BacklogView` the same way
- remove view-owned decisions like:
  - full refresh vs cache rehydrate
  - extra remote retry logic
  - domain-specific diff recreation

Files likely involved:

- `FamilyTodo/Views/ShoppingListView.swift`
- `FamilyTodo/Views/TasksView.swift`
- `FamilyTodo/Views/BacklogView.swift`
- `FamilyTodo/Views/Components/SyncStatusPill.swift`
- `FamilyTodo/Views/Components/NewItemsBanner.swift`

Success criteria:

- open screen no longer changes sync correctness
- views become presentation layers over already-merged state

## Phase F: Direction-aware repair logic

Goal:

- keep repair logic centralized and measurable

Tasks:

- move retry/follow-up policy into the coordinator
- support both directions:
  - `owner -> participant`
  - `participant -> owner`
- for participant path, add a short bounded repair window if the first pass produces an incomplete visible diff
- for owner path, keep the current concept of follow-up refresh but under the same policy engine

Important:

- retry policy must be driven by one place
- views and secondary managers should not own retry timing

Success criteria:

- `owner -> participant` is no longer random
- repair logic is deterministic and traceable

## Phase G: Sync diagnostics

Goal:

- make it obvious where time is lost

Diagnostics to record:

- last push received timestamp
- last sync start
- last sync finish
- fetch duration
- merge duration
- event publication time
- visible-screen refresh time if measurable
- resulting domain counts / changed IDs
- direction classification when inferable

Possible UI:

- debug log only at first
- optional hidden diagnostics section in `Settings`

Success criteria:

- a slow sync can be explained as:
  - push delay
  - fetch delay
  - merge delay
  - UI reaction delay

## Migration order

Recommended execution order:

1. create coordinator shell
2. route push and foreground sync through coordinator
3. add household-level fetch snapshot
4. centralize merge + visible-state diff
5. publish typed sync events
6. migrate `Tasks`
7. migrate `Ideas`
8. migrate `Shopping`
9. clean up old refresh code paths
10. add diagnostics and targeted device verification

Why this order:

- `Tasks` and `Ideas` are currently the least trustworthy paths
- `Shopping` works best today, so it should migrate after the core pipeline is proven

## Explicit non-goals

Do not do these in the same refactor:

- migrate owner to `sharedCloudDatabase`
- introduce a new backend
- redesign product permissions unrelated to sync
- redesign the full notification product
- combine with monetization changes

## Device validation matrix

The refactor is not complete until these pass on two physical devices:

- `owner -> participant`
  - add/edit/remove shopping item
  - bought/unbought
  - bundle changes if relevant
  - add/edit/assign/complete/reopen task
  - add/edit/promote/remove idea
  - rename household
  - change household icon
  - rename member / update member-visible metadata
- `participant -> owner`
  - the same matrix

Also verify:

- open `Shopping` screen
- open `Tasks` screen
- open `Ideas` screen
- app foreground on another tab
- app resumed from background
- several rapid changes in one burst

## Success criteria

- `owner -> participant` and `participant -> owner` are close in observed behavior
- no domain depends on screen-specific refresh tricks
- household name/icon and member names sync through the same durable path as tasks and shopping
- one remote batch yields one coherent UI reaction
- notification/banner logic no longer rebuilds a different version of the truth
