# I1.8 Per-User Recommended Task Limit — Spec

## Problem

The WIP limit is supposed to be per-assignee, but the UI computes zones and badge counts against the global active-task list:

1. **`wipZone(for index:)` uses a global list index.** When "All tasks" is shown, a member's task at global position 3 is marked `.warning` even if that member has only 1 active task.
2. **`TasksWIPBadge` shows `filteredActiveTasks.count`** (all visible tasks) vs the per-user limit — misleading when unfiltered.
3. **The over-limit separator** is inserted at `index == normalizedWipLimit` in the global list — meaningless when multiple assignees are interleaved.
4. **No tests** cover mixed-assignee WIP correctness.

## Domain Rule (from CLAUDE.md)

> max 3 active `.next` tasks per assignee

One member being over limit must never block or visually penalise another member.

## Required Changes

### 1. `wipZone` — per-assignee position

Replace `wipZone(for index: Int)` with `wipZone(for task: Task)`.
Count how many `.next` tasks share the same `assigneeId` and appear before this task in the sorted visible list. Compare that per-assignee index against `normalizedWipLimit`.

For unassigned tasks (no `assigneeId`): always `.normal` — we cannot count against any user's limit.

### 2. Over-limit separator — single-assignee filter only

Only insert the separator when the current `assigneeFilter` targets exactly one person (`.mine` or `.member(id)`). In "All tasks" view, suppress it — a single divider across interleaved assignees is incorrect.

### 3. WIP badge — current user's count

When `assigneeFilter == .all`: badge count = `store.nextTaskCount(for: currentMemberId)` (current user's own tasks).
When filtered to one assignee: badge count = `filteredActiveTasks.count` (unchanged — already scoped to one person).

### 4. Tests

Add to `TaskStoreTests.swift`:
- `testNextTaskCount_PerAssignee_IsIsolated` — user A with 3 tasks does not affect user B's count
- `testNextTaskCount_UnassignedTasks_NotCounted` — unassigned tasks do not contribute to any assignee's count
