# Plan: Fix Backlog Category Flicker and First-Use Promote Blocking

## Summary
- `Idea Categories` are still using a weaker sync contract than `BacklogItem` and `Task`, so a background refresh can temporarily drop a just-created local category before CloudKit echoes it back.
- The first-use `Promote to Task` freeze is most likely a race between two things that happen right after the first assignment:
  - the assignment flow still awaits remote work before fully finishing its tutorial progression
  - the promote TipKit popover can become active immediately on the newly shown promote control
- The fix is to make category mutations and idea assignment fully local-first, then gate TipKit so it never sits on top of a freshly interactive promote control.

## Implementation Changes
1. Strengthen the category sync contract in `BacklogStore`.
- Make `addCategory`, `updateCategory`, and `reorderCategories` return after the local SwiftData save, not after CloudKit finishes.
- Treat category cache rows the same way as items:
  - `pendingUpload` after local create/update/reorder
  - `awaitingCloudEcho` after remote write succeeds
  - `synced` only after a matching cloud echo is observed
- Stop `flushPendingSync()` from marking category uploads as `synced` immediately after `saveBacklogCategory`; use `awaitingCloudEcho` instead.
- Add a category echo matcher, similar to item/task stale protection, so cloud data can replace a local pending/awaiting category only when `id`, `title`, `colorHex`, `sortOrder`, and `updatedAt` match the local mutation.
- Add category-specific mutation protection so `performLoadDataPass()` cannot republish a stale cloud category list over a freshly created/edited local category.

2. Make idea assignment fully local-first.
- Refactor the assignee-changing path in `BacklogStore.updateItem(...)` into a local-commit-first helper:
  - update the visible `items` array immediately
  - upsert the matching `CachedBacklogItem`
  - mark it `pendingUpload`
  - save `ModelContext`
  - return control to the UI immediately
  - replay CloudKit in the background
- Cloud failure must leave the locally assigned idea visible and promotable; only local save failure may roll the UI back.
- Trigger `AppTips.donateIdeasOwnerAssigned()` immediately after the local save succeeds, not after remote save finishes.

3. Prevent TipKit from intercepting the first promote interaction.
- Extend `BacklogView` / `AppTipVisibility.ideasTip(...)` with an explicit transient-interaction gate, for example:
  - assignment sheet currently presented
  - assignment sheet just dismissed
  - assignment local commit in progress
  - promotion already in progress
- Use a short grace window after assignment completion before the promote tip is allowed to appear.
- Move the promote tip anchor off the promote button itself and onto a nearby non-critical anchor, such as the row's trailing actions container. The tip can still point at the control area, but it must not sit directly on the tappable button.
- Keep the current onboarding sequence intact: `create category -> add idea -> assign owner -> promote`, but only show each tip when the screen is interaction-idle.

4. Keep reload behavior local-first for category visibility.
- Reuse the same backlog rehydrate contract already used for item/task cross-domain fixes:
  - local cache paints first
  - remote refresh is background-only
- Ensure any backlog-local mutation that changes categories or items can force a local rehydrate without waiting for cloud notifications.

## Internal API / Behavior Changes
- `BacklogStore` category operations become local-save-first APIs.
- Add category stale-echo protection helper and category mutation tracking, parallel to the existing item/task protections.
- `AppTipVisibility.ideasTip(...)` gains a transient-interaction suppression input.
- `BacklogView` owns a small `tips suppressed until` / `assignment transition active` state so TipKit timing is deterministic.

## Test Plan
- Store tests:
  - creating a category keeps it visible during a background refresh that returns an empty or stale cloud category list
  - updating/reordering a category stays visible while cache row is `awaitingCloudEcho`
  - cloud echo with stale category metadata does not overwrite the local pending version
  - assigning an idea updates local cache immediately without waiting for CloudKit
- UI tests:
  - fresh household: create first category, create first idea, assign owner, immediately tap promote; the button responds right away
  - fresh household with onboarding tips enabled: promote remains tappable even when the promote tip becomes eligible
  - creating a category never causes it to disappear and reappear during sync
- Device validation:
  - repeat the first-category / first-idea / first-assignment flow on slow network
  - verify the same flows still behave correctly in `System`, `Retro Dark`, `Retro Light`, and `Paper`

## Assumptions
- We keep TipKit onboarding for promote; we are delaying/suppressing and re-anchoring it, not removing it.
- No CloudKit schema change is required.
- The category fix should apply everywhere `BacklogStore` category APIs are used, not only on the Ideas tab.
