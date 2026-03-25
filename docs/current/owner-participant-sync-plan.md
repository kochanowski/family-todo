# Owner vs Participant Sync Plan

Last updated: 2026-03-24

## Summary

HousePulse uses CloudKit sharing with two different scopes:

- owner reads and writes through `ownerPrivate`
- participant reads and writes through `participantShared`

That asymmetry is real at the platform model level, so the goal is not to pretend it does not exist. The goal is to make the app's observed behavior feel close to symmetric by hardening the sync pipeline and visible-screen refresh behavior.

Recommended execution order:

1. `Migration spike`
2. `Harden current model`
3. `Big refactor` only if phases 1 and 2 still leave too much latency or complexity

## Why Not a User-Facing Migration Button

A user-facing button after the second member joins would only mask sync uncertainty. It would not remove the core architectural difference between owner and participant flows. If a manual action is ever needed, it should be a debug/support tool such as `Repair Household Sync State`, not a required product step.

## Phase 1: Migration Spike

Goal: determine whether the owner can be treated as a practical `shared` reader for the owner's own household.

Tasks:

- validate CloudKit behavior for owner access to household records through `sharedCloudDatabase`
- verify whether owner household hydration can be performed entirely from `shared`
- verify whether owner subscriptions, share metadata, and record fetches remain stable in that mode
- document the result as one of:
  - `supported`
  - `partially supported but fragile`
  - `not supported`

Acceptance criteria:

- the result is evidence-based, not an assumption
- if unsupported, owner migration to shared is closed as a primary architecture path

## Phase 2: Harden Current Model

Goal: keep `ownerPrivate` / `participantShared`, but reduce the observed asymmetry in app behavior.

Tasks:

- use one central household sync coordinator for remote push handling, dedupe, retry, and typed refresh publication
- ensure visible screens refresh all data dependencies needed for rendering:
  - `Tasks`: tasks + members + backlog categories
  - `Ideas`: items + categories + members
  - `Shopping`: items + bundles
- avoid cache-only remote refresh on visible screens when dependent stores would remain stale
- keep owner follow-up refresh for participant-originated changes, but measure and tighten it
- keep notification batching and inline feedback tied to one remote diff source of truth
- add directional telemetry for:
  - `owner -> participant`
  - `participant -> owner`
  - push-to-cache latency
  - cache-to-visible-screen latency

Acceptance criteria:

- both directions update without pull-down refresh
- visible screens never render stale member/category context after remote push
- notification counts and inline feedback stay deduplicated

## Phase 3: Big Refactor

Only start this if phases 1 and 2 still leave too much complexity or asymmetry.

Goal: replace per-screen mini sync flows with one household sync engine.

Detailed execution plan:

- `docs/current/2026-03-25-big-sync-refactor-plan.md`

Tasks:

- create one canonical sync engine for:
  - push intake
  - delta fetch
  - cache merge
  - typed domain events
  - UI refresh publication
- reduce stores to thin cache/view-state adapters instead of separate remote refresh controllers
- unify retry, dedupe, and latency measurement in one place

Acceptance criteria:

- one durable remote sync path across Shopping, Tasks, and Ideas
- fewer screen-specific edge cases
- easier owner/participant regression testing

## Current Working Assumption

Until phase 1 disproves it, the safest assumption is:

- owner should remain modeled through `ownerPrivate`
- participant should remain modeled through `participantShared`
- app behavior should be equalized in the sync engine and screen refresh layer, not by forcing the owner into a participant-style path
