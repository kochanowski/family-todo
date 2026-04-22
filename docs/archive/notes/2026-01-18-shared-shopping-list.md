# Shared Shopping List (Global Household)

**Date:** 2026-01-18
**Status:** Planned (MVP extension)
**Scope:** One shared list per household

## Summary

A single, household-wide shopping list with two states:
- **To Buy**: active items that need to be purchased.
- **Bought**: a permanent, shared "basket" of previously purchased items used for quick re-adding and suggestions.

Items never expire. Clearing the list only removes items from **To Buy**.

## Goals

- Reduce friction when adding recurring groceries.
- Keep the list shared-first and conflict-free.
- Provide fast re-add via the Bought basket, without gamification.
- Keep the UX minimal and understandable in under 60 seconds.

## Non-Goals

- Categories, favorites, or pinned items.
- Personal or private shopping lists.
- Auto-expiring items.
- Scores, points, or streaks.

## UX Overview

- New bottom tab: **Shopping** (household-wide).
- Two sections on one screen:
  - **To Buy** (active list)
  - **Bought** (library of past items)
- Add bar with inline suggestions from **Bought**.
- Each item shows **name + quantity** (number + optional unit string).
- Actions: check to mark bought, edit name/quantity, delete, clear To Buy.

## User Flows

### Add item
1. Type a product name.
2. Suggestions appear from the **Bought** basket.
3. Select suggestion or submit new name.
4. Item appears in **To Buy**.

### Mark as bought
1. Check an item in **To Buy**.
2. Item is removed from **To Buy**.
3. Item is added or updated in **Bought** with fresh metrics.

### Re-add from Bought
1. Tap an item in **Bought** or choose it from suggestions.
2. A new **To Buy** entry is created.

### Edit
- **To Buy**: edit name and quantity.
- **Bought**: edit name only.
- Renaming updates the canonical item name used for suggestions.

### Delete
- **To Buy**: removes the active entry.
- **Bought**: removes the item from the shared basket (and suggestions).

### Clear list
- Clears **To Buy** only. **Bought** remains intact.

## Suggestions & Sorting

- **Source:** items in **Bought**.
- **Default limit:** 20 suggestions.
- **Configurable range:** 5–50.
- **Sorting:**
  1. `purchaseCount` (desc)
  2. `lastPurchasedAt` (desc)
  3. `name` (asc)

## Data Model (Proposed)

### ShoppingItem (Bought basket)
- `id: UUID`
- `householdId: UUID`
- `name: String`
- `purchaseCount: Int`
- `lastPurchasedAt: Date?`
- `createdAt: Date`

### ShoppingListEntry (To Buy list)
- `id: UUID`
- `householdId: UUID`
- `itemId: UUID` (references `ShoppingItem`)
- `quantityValue: Double?`
- `quantityUnit: String?` (free text, e.g. "L", "kg")
- `addedByMemberId: UUID?`
- `createdAt: Date`
- `updatedAt: Date`

## Settings

- **Suggestion limit** (5–50, default 20).
- **Clear To Buy** action.

## Localization

- UI is English by default.
- UI language follows app language settings.
- Item names are user-provided and not auto-translated.

## Edge Cases & Rules

- If an item already exists in **To Buy**, focus it and offer to update quantity instead of duplicating.
- **Bought** is a permanent library unless manually deleted.
- No personal lists; the shopping list is shared from first use.
