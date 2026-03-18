# Plan: Fix Shopping Input, Local-First Flicker, Household Save, and TipKit Reset Regressions

## Summary
- Address the critical local-first regression first, because it affects perceived correctness across Shopping, Tasks, Ideas, and Bundles and will make the other fixes easier to verify.
- Keep scope limited to SwiftUI/state/store/reset behavior. No CloudKit schema changes are needed for these 4 bugs.
- Preserve the product rules already in the repo: local-first UI, owner-only household metadata edits, and hard reset staying local-only.

## Implementation Changes
1. Stabilize local-first rendering and remove flicker
- Update the main list stores so repeated `load*()` calls cannot overlap and republish stale or transient snapshots out of order.
- Treat cache load as first paint and background CloudKit sync as a silent merge, not a reason to clear visible arrays or swap to blank/empty UI.
- Narrow refresh triggers in the subscription layer so self-noise is filtered before notifications are posted, and unknown database events do not refresh every domain at once.
- Reduce eager reloads from tab-change / appear / notification hooks, especially in Tasks, Backlog, Shopping, and Bundles.
- Change the views so empty/loading states only appear when the local snapshot is truly empty; during background refresh, keep the last rendered list visible.

2. Unify shopping item capitalization behavior
- Align Shopping Bundle item entry with the main Shopping list item entry by switching bundle item fields from word capitalization to sentence capitalization.
- Keep the capitalization rule shared across all shopping item entry points so future changes cannot drift again.
- Verify the behavior for bundle existing-item edit, bundle add-item composer, inline shopping edit, inline insert, and rapid entry.

3. Make household editing explicitly draft-driven
- Refactor the Edit Household sheet to derive `trimmedName`, `hasChanges`, and `canSave` from the current draft versus persisted household data.
- Enable Save only when there is a valid change to name or icon; unchanged state stays disabled.
- Rehydrate the editor draft on every presentation so canceled edits cannot survive a dismiss/reopen cycle.
- Use a model-driven sheet identity instead of a plain boolean sheet to avoid stale `@State`.
- Make owner-only edit access explicit in the UI so non-owners do not enter a save flow they cannot complete.

4. Make hard reset fully reset TipKit/onboarding state
- Replace the current development-style TipKit reset call with a dedicated hard-reset API in `AppTips`.
- Have that API clear all relevant local state in one place: TipKit datastore, app tip progress keys, context signature, runtime generation, and onboarding tutorial flags that define "fresh user" behavior.
- Move TipKit reconfiguration/context sync to a deterministic post-reset moment after the new session and household context are established.
- Keep runtime-generation as the mechanism that forces Shopping, Tasks, and Ideas tip anchors to remount after reset.
- Preserve hard reset as local-only; do not couple this fix to remote CloudKit deletion.

## API / Interface Changes
- Add a dedicated internal TipKit reset entrypoint for hard reset, such as `AppTips.resetForHardReset()`.
- Add a shared internal capitalization policy for shopping item text fields.
- Change household edit presentation/state management so the sheet is identity-driven and Save uses an explicit `canSave` rule.

## Test Plan
- Add unit tests proving repeated store refreshes do not blank visible cached data or let stale in-flight results win.
- Add unit tests for the new TipKit hard-reset API clearing progress/context and bumping runtime generation.
- Add unit tests for household edit draft logic: unchanged draft disabled, icon-only change enabled, name-only change enabled, blank name disabled.
- Add UI tests for bundle item capitalization consistency.
- Add UI tests for Edit Household: Save enables on valid change, persists on Save, and canceled drafts do not survive reopen.
- Add an end-to-end UI test for `hard reset -> create/join household -> Shopping and Ideas tips appear again in the same app session`.
- Validate on device that switching tabs and handling remote/local mutations never flashes empty lists in Shopping, Tasks, Ideas, or Bundles.
- Recheck all touched UI in `System`, `Retro Dark`, `Retro Light`, and `Paper`, including one narrow iPhone layout.

## Assumptions
- Household name/icon editing remains owner-only.
- No backend/schema migration is required for these 4 fixes.
- The critical flicker/local-first regression should be implemented first, because it affects verification of the other UI fixes.
