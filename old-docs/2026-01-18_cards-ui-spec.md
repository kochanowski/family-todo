# Cards UI Spec (Book-Style Pager)

**Date:** 2026-01-18
**Project:** Family To-Do App
**Purpose:** Define the visual design and interaction model for the new card-based home screen.

## Overview

The default post-login screen is a horizontal card pager with a "book" edge effect. Cards overlap by 25pt so edges remain visible and tappable. Navigation uses interactive swipe gestures with spring animations and haptics.

## Cards (Current Set)

1. **Shopping List** (purple)
2. **Todo** (green, default)
3. **Backlog** (yellow)
4. **Recurring** (orange)
5. **Household** (blue)

## Colors

| Card | Gradient Start | Gradient End | Active Dot |
|------|----------------|--------------|------------|
| Shopping List | `#E9D5FF` | `#DDD6FE` | `#C084FC` |
| Todo | `#DCFCE7` | `#BBF7D0` | `#4ADE80` |
| Backlog | `#FEF9C3` | `#FEF08A` | `#FACC15` |
| Recurring | `#FFEDD5` | `#FED7AA` | `#FB923C` |
| Household | `#DBEAFE` | `#BFDBFE` | `#60A5FA` |

## Book-Style Edge Effect

- Cards overlap by **25pt** (visible edge width).
- Edges are full height (behind header/footer) and **tappable**.
- Up to 3 edges are visible per side; closest cards are shown.

## Navigation & Gestures

- Swipe left/right to change cards (threshold: **50pt**).
- Interactive drag follows the finger.
- Neighbor cards fade in proportionally during drag.
- **Spring animation:** response `0.3`, damping `0.7`.
- Haptics:
  - `.light` when swipe begins.
  - `.medium` when snap completes.

## Header (Glass)

- Glass morphism: `.ultraThinMaterial`.
- Height ~60pt, with bottom separator.
- Left: **Tasks** (semibold).
- Right: Settings button (gear icon) with glass circle background.

## Footer (Glass)

- Glass morphism with top separator.
- Dot indicators for each card:
  - Inactive: 8x8, secondary color.
  - Active: 24x8 capsule, card accent color.
  - Spring animation: response `0.4`, damping `0.75`.
  - Dots are tappable with `.light` haptic.

## Card Layout

- Header: title (28pt bold) + subtitle (14pt) with remaining count.
- Task list: scrollable `LazyVStack` with glass rows.
- Row styling: ultra-thin material + white overlay + subtle shadow.
- Checkbox: 26pt circle with pulse animation on toggle.
- Delete: red X button + swipe-to-delete action.
- Input: glass container with text field + add button (shimmer).

## Empty State

- Backlog empty message: **"Everything is done!"**
- Confetti particle effect (optional, enabled by default).

## Data (In-Memory)

- State is in-memory only (no persistence).
- Sample items:
  - Shopping: Milk, Bread, Sugar
  - Todo: Fix the faucet, Take down the Christmas tree
  - Backlog: empty
  - Recurring: Take out trash every Monday, Vacuum living room weekly
  - Household: Kitchen, Bathroom, Garden
