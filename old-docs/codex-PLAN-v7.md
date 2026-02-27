# Plan v7 — Backlog Edit+Assign, Shopping Tap Split, Tab Glass Clarity

## Summary
1. Root causes confirmed in code:
- Backlog store supports update/delete, but UI lacks explicit edit affordance and relies on swipe.
- `BacklogItem` has no `assigneeId`, so backlog-level assignment cannot persist.
- `ShoppingItemRow` is one large toggle button, so tapping title marks item as bought.
- `MainAppView` applies full-screen blur transition on tab switches; tab indicator is rendered per-tab, which weakens visible droplet motion.
2. Locked UX decisions:
- Backlog assignment is optional in backlog and reused on promote.
- Backlog interaction is `tap = edit` plus visible row menu; swipe remains as shortcut.
- Shopping interaction is `tap title = inline edit`; only left circle toggles bought.

## Important API / Data Changes
1. `FamilyTodo/Models/BacklogCategory.swift`
- Add `assigneeId: UUID?` to `BacklogItem` with default `nil`.
2. `FamilyTodo/Models/CachedBacklogItem.swift`
- Add cached `assigneeId: UUID?`; update mapping methods.
3. `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
- Read/write optional `assigneeId` for `BacklogItem`; missing legacy field maps to `nil`.
4. `FamilyTodo/Stores/BacklogStore.swift`
- Extend `addItem` and `updateItem` to handle `assigneeId`.
- Promotion uses item assignee first, then fallback assignee flow.
5. `FamilyTodo/Views/BacklogView.swift`
- Add visible row actions menu (`Edit`, `Assign`, `Promote`, `Delete`).
- Add `BacklogItemEditorSheet` opened by row tap.
- Show assignee badge in each row.
6. `FamilyTodo/Views/ShoppingListView.swift`
- Split `ShoppingItemRow` actions: separate `onToggle` and `onEdit`.
- Add inline edit state in list content and save via `ShoppingListStore.updateItem`.
7. `FamilyTodo/ContentView.swift` and `FamilyTodo/Views/Components/FloatingTabBar.swift`
- Remove full-screen blur transition from tab content switch.
- Refactor to a single moving active indicator layer.
- iOS 26: glass on indicator only; iOS 17-25 fallback remains material.

## Implementation Steps
1. P0: Tab blur and transition fix.
- Remove `tabContent` blur transition path in `MainAppView`.
- Keep tab content switch simple (no global blur remount effect).
- In `FloatingTabBar`, replace per-tab indicator backgrounds with one animated indicator positioned by active slot center.
- Tune light-mode tint/stroke to keep icon/label sharp.
2. P0: Backlog edit/delete discoverability.
- Add explicit trailing row menu and keep swipe actions.
- Add delete confirmation from menu path.
3. P0: Backlog assignment persistence.
- Implement `assigneeId` through model, cache, cloud mapping, and store.
- Add assignee picker in backlog item editor.
- Promotion order: item assignee -> single-member auto assign -> multi-member picker.
4. P0: Shopping tap split.
- Left circle button toggles bought.
- Title tap opens inline edit field.
- Return/Done commits edit; empty value cancels and restores previous title.
5. P1: Polish and regressions.
- Verify tab bar hit-testing after indicator refactor.
- Keep CTA/tab interactions stable when keyboard appears.

## Test Cases and Scenarios
1. `Backlog_Edit_Delete_MenuVisible`
- Row menu is always visible; edit and delete are functional.
2. `Backlog_Assignee_Persist_And_Promote`
- Assigned member persists and is used on promote.
3. `Backlog_Promote_WIP_Block`
- If WIP reached, promote blocked and backlog item remains.
4. `Shopping_RowTap_Edits_NotToggle`
- Title tap edits; checkbox tap toggles bought only.
5. `TabBar_NoGlobalBlur_ClearContent`
- No full-screen blur when switching tabs.
6. `TabBar_Droplet_Animation_Visible`
- Active indicator movement is clearly visible between all tabs.

## Assumptions and Defaults
1. Backlog assignee stays optional.
2. Single assignee per backlog item (`UUID?`) is sufficient for v1.
3. Legacy CloudKit data without `assigneeId` must load as unassigned.
4. Row menu is primary discoverability mechanism; swipe remains secondary.
5. iOS target remains 17; Liquid Glass priority on iOS 26+ with fallback below.
