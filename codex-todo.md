- Keep the existing local-first data layer intact and fix the remaining issues in the UI/state layer.
  - Treat the “Move to Ideas” bug as a view-state regression first: store-level demotion is already covered by tests, so the plan will preserve category assignment and also stop the Ideas screen from hiding a legitimately demoted item.
  - Reuse the existing TipKit types where possible instead of inventing new onboarding flows.
  - Add one small cross-screen notification for the Tasks tab bounce cue; everything else stays local to existing views/stores.

  - Task -> Ideas visibility
      - Keep TaskStore.moveTaskToIdeas local-first, but harden destination resolution so it never removes the task unless a concrete local category ID has been resolved from task.backlogCategoryId, the loaded backlog categories, or cached backlog categories in that
        order.
      - Fix the remaining UI regression in BacklogView: the current hiddenPendingPromotionIds session suppression can hide a demoted item when the store reuses the original idea lineage. Replace that permanent hide behavior with lineage-aware suppression that is cleared
        when a local demotion for that logical item succeeds.
      - Have the demotion path explicitly clear the Ideas-side promotion suppression for the returned lineage as part of the local notification flow, so switching to Ideas shows the item immediately.
      - Keep the existing fallback behavior when no category exists locally: do not auto-create a category; keep the task visible and return the existing failure result/banner.
  - Shopping quick-add bundle TipKit
      - Reuse ShoppingBundleQuickAddTip and keep its copy unchanged.
      - In ShoppingListView, make the quick-add tip eligibility react to bundle availability becoming non-empty while the Shopping screen is visible, not only to passive steady-state conditions.
      - Re-arm the add-button tip anchor when bundle count transitions from 0 -> >0, including both return paths:
          - back-navigation from Bundles management/editor to Shopping
          - Save & Add to List from the new-bundle editor
      - Keep the tip hidden during transient blockers already used elsewhere on the screen: active quick-add sheet, keyboard/rapid-entry, and active toast.
      - Do not mark the tip as completed on bundle creation; only mark it complete when the user actually uses quick add/long press.
  - Ideas promote cue + Tasks tab bounce
      - Keep the existing IdeaPromotionTip; it is already implemented but currently suppressed at the wrong moment.
      - Remove the post-assignment suppression window that delays the promote tip after assigning an owner, so the tip can appear immediately when the arrow becomes available.
      - Add a lightweight notification such as tasksTabPromotionCueRequested; BacklogView.completePromotion posts it only after a successful promotion.
      - In MainAppView, add a local bounce token for the Tasks tab and apply .symbolEffect(.bounce, value: token) to the Tasks tab icon label so the bottom Tasks icon visibly reacts when promotion succeeds.
      - Do not auto-switch tabs; the cue is informational only.
  - Members list immediate profile refresh
      - Keep MemberStore.updateCurrentUserProfile as the source of the local profile-change notification.
      - Change ProfileView / Household Settings notification handling from “async reload only” to “immediate local cache rehydrate first, optional background cloud refresh second”.
      - On .memberProfileDidChange, call markLocalSnapshotStale() plus rehydrateVisibleSnapshotFromCache() synchronously so the Members section updates before leaving/re-entering the screen.
      - Preserve the background cloud refresh in cloud mode so remote reconciliation still happens after the local-first UI update.

  ### Important Interface / State Additions

  - Add one new internal notification name for the tab cue, e.g. Notification.Name.tasksTabPromotionCueRequested.
  - Add one local tab-bounce state token in MainAppView to drive .symbolEffect.
  - Convert Ideas promotion hiding from a raw “hide this ID for the session” behavior into a lineage-aware suppression model that can be explicitly cleared on demotion success.
  - Keep existing TipKit structs and progress keys; no new persisted tip progress keys are needed.

  ### Test Plan

  - Extend task/backlog coverage to prove that promote-then-demote of the same logical item does not leave the item hidden in Ideas after local notifications.
  - Add AppTip visibility tests for:
      - quick-add tip becoming eligible when bundles transition from none to at least one
      - quick-add tip remaining suppressed while bundle chooser/toast/transient sheet is active
      - promote tip being eligible immediately after assignment once the item has an assignee
  - Add a ContentView/Main shell test or focused state test for the promotion cue notification incrementing the Tasks tab bounce token without changing the selected tab.
  - Add/update member/profile tests to verify the local profile-change notification causes immediate members-list rehydration without waiting for a cloud fetch.

  ### Assumptions and Defaults

  - The demotion failure is primarily a UI suppression issue, not a missing local write; store tests already show the local backlog item is persisted.
  - The app should not create a new category automatically when moving a task back to Ideas.
  - The Tasks icon cue should bounce even if the Tasks tab is not currently selected; it is meant to answer “where did it go?”.
  - The existing tip copy remains the product-approved wording unless you later want to revise the text separately.