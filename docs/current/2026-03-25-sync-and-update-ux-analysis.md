# Sync and Update UX Analysis

Last updated: 2026-03-25

## Why this file exists

This note captures the current state of multi-device sync and the current UI for remote updates so we can return to it after the cross-device sync work is stable.

Primary rule:

- do not polish remote-update UI until household sync is reliable on physical devices in both directions

## Current sync reality

HousePulse still operates on an asymmetric CloudKit model:

- owner reads and writes through `ownerPrivate`
- participant reads and writes through `participantShared`

That platform asymmetry is real. The product goal is not to hide it in architecture diagrams, but to make it feel close to symmetric in real usage.

Current working direction:

- keep `ownerPrivate` / `participantShared`
- harden the current model first
- only consider a larger sync-engine refactor if phase-2 hardening still leaves obvious latency or correctness problems

Relevant background:

- `docs/current/owner-participant-sync-plan.md`

## Current remote-update UI behavior

### Tasks

Current behavior:

- visible `Tasks` screen shows a temporary inline header pill such as `Tasks updated`
- this uses `SyncStatusPill`
- there is no large top banner for task updates

Observed downside:

- the text pill is informative, but slightly noisy for a fast-moving board
- it consumes horizontal space in the header

### Shopping

Current behavior:

- visible `Shopping` screen shows a temporary inline header pill such as `Shopping updated` or `3 items added`
- off-screen shopping additions show a top in-app banner with count

Observed downside:

- `Shopping` is the noisiest sync surface because it has both inline and banner states
- on smaller devices, the bottom tab label `Shopping` is too long and can wrap/truncate visually
- sync-related chrome must not make the bottom navigation feel unstable

### Ideas

Current behavior:

- `Ideas` has no dedicated sync text indicator today
- users mainly see refreshed content and row/card animation

Observed downside:

- the three main tabs are inconsistent:
  - `Tasks` has inline text feedback
  - `Shopping` has inline text + top banner
  - `Ideas` has no dedicated sync status affordance

## Recommended UI direction after sync is stable

### 1. On-screen remote updates

Recommended default:

- replace text pills like `Tasks updated` and `Shopping updated` with a small icon-led sync indicator in the header
- keep it subtle, short-lived, and visually stable
- use the same pattern for `Tasks`, `Shopping`, and `Ideas`

Reasoning:

- users mostly need reassurance that sync happened
- they usually do not need to read a sentence every time
- icon-first feedback reduces header clutter and avoids jitter

### 2. Off-screen shopping additions

Recommended default:

- keep one top banner for off-screen shopping additions only
- this remains the one place where explicit text and count are useful

Reasoning:

- shopping additions are the clearest case where a user may need a navigational prompt
- a top banner makes sense there because the user may be on another tab

### 3. Bottom tab bar stability

Recommended default:

- never place sync count or sync UI in the tab bar
- keep bottom tab titles stable and short
- strongly consider changing the tab label from `Shopping` to `Shop`
- keep the full screen title `Shopping` in the screen header

Reasoning:

- tab bar labels should never wrap into awkward split text such as `Shop` / `ping`
- the bottom navigation should prioritize recognizability and stability over descriptive length

### 4. Ideas consistency

Recommended default:

- give `Ideas` the same icon-only, header-level sync feedback as `Tasks` and `Shopping`
- do not introduce a separate banner for ideas

Reasoning:

- keeps the three collaboration tabs visually consistent
- avoids making `Ideas` feel like a second-class synced surface

## Notification permission gating

Current problem:

- notification permission is being surfaced too early
- asking during `Add Item` is too aggressive when the user is still alone in the household

Recommended default:

- do not ask for notification permission while the household has only one active member
- ask only once the household has more than one active member and there is a believable shared-value moment

Good trigger moments:

- after the second active member successfully joins
- or the first time a meaningful shared notification can actually happen

Bad trigger moments:

- first `Add Item`
- early solo-user setup flow

## Decision summary

Do now:

- finish cross-device sync hardening first
- keep remote-update polish scoped and conservative until device tests are stable

Do right after sync is stable:

- move `Tasks` and `Shopping` from text pill to icon-led header feedback
- add the same pattern to `Ideas`
- keep the shopping top banner only for off-screen additions
- shorten bottom tab label from `Shopping` to `Shop`
- gate notification permission on multi-member households

## Open questions to revisit later

- should the icon-only sync indicator have a tiny pulse animation or stay static
- should `Shopping` ever show text on-screen for additions, or should that also become icon-only
- should there be a hidden debug/support action such as `Repair Household Sync State`
- after sync is stable, do we still need to revisit `Phase 3 -> Evaluate Zone-Scoped Subscriptions`
