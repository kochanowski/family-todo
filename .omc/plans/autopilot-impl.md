# I1.8 Per-User Recommended Task Limit — Implementation Plan

## Branch: `feature/i1-8-per-user-task-limit`

---

## Step 1 — Fix `wipZone` in `TasksView.swift`

**File:** `FamilyTodo/Views/TasksView.swift`

Replace the current `wipZone(for index: Int)` method with a task-aware version:

```swift
private func wipZone(for task: Task) -> TaskRow.WipZone {
    let limit = normalizedWipLimit
    guard let assigneeId = task.assigneeId else { return .normal }
    let assigneeTasks = visibleNextTasks.filter { $0.assigneeId == assigneeId }
    let assigneeIndex = assigneeTasks.firstIndex(where: { $0.id == task.id }) ?? 0
    return assigneeIndex < limit ? .normal : .warning
}
```

Update the call site in `activeTasksContent`:
```swift
wipZone: wipZone(for: task)   // was wipZone(for: index)
```

The `let index = ...` line in `activeTasksContent` can be removed if it's only used for `wipZone` and the separator guard (see Step 2 below — `index` is still needed for the separator check).

---

## Step 2 — Guard separator to single-assignee filter

**File:** `FamilyTodo/Views/TasksView.swift`

In `activeTasksContent`, the separator insertion:

```swift
// Current (broken in multi-assignee view):
if index == normalizedWipLimit, displayedTasks.count > normalizedWipLimit {
    overLimitSeparator
}

// Replace with:
if isSingleAssigneeFilter,
   index == normalizedWipLimit,
   displayedTasks.count > normalizedWipLimit {
    overLimitSeparator
}
```

Add helper:
```swift
private var isSingleAssigneeFilter: Bool {
    switch assigneeFilter {
    case .all: return false
    case .mine, .member: return true
    }
}
```

---

## Step 3 — Fix WIP badge count

**File:** `FamilyTodo/Views/TasksView.swift`

In the `header` computed property, change the badge:

```swift
// Current:
TasksWIPBadge(count: filteredActiveTasks.count, limit: normalizedWipLimit)

// Replace with:
TasksWIPBadge(count: wipBadgeCount, limit: normalizedWipLimit)
```

Add helper:
```swift
private var wipBadgeCount: Int {
    switch assigneeFilter {
    case .all:
        guard let id = currentMemberId else { return filteredActiveTasks.count }
        return store.nextTaskCount(for: id)
    case .mine, .member:
        return filteredActiveTasks.count
    }
}
```

---

## Step 4 — Add tests to `TaskStoreTests.swift`

**File:** `FamilyTodoTests/TaskStoreTests.swift`

Add two tests in the `// MARK: - WIP Guidance Tests` section:

```swift
func testNextTaskCount_PerAssignee_IsIsolated() async {
    let userA = UUID()
    let userB = UUID()
    // Add 3 next tasks for A, 1 for B
    for i in 0..<3 {
        await store.createTask(title: "A\(i)", assigneeId: userA, householdId: householdId, status: .next)
    }
    await store.createTask(title: "B0", assigneeId: userB, householdId: householdId, status: .next)
    await store.loadTasks()
    XCTAssertEqual(store.nextTaskCount(for: userA), 3)
    XCTAssertEqual(store.nextTaskCount(for: userB), 1, "User B at 1 task should not be affected by user A reaching limit")
}

func testNextTaskCount_UnassignedTasks_NotCounted() async {
    let userA = UUID()
    // One assigned, two unassigned next tasks
    await store.createTask(title: "Assigned", assigneeId: userA, householdId: householdId, status: .next)
    await store.createTask(title: "Free1", assigneeId: nil, householdId: householdId, status: .next)
    await store.createTask(title: "Free2", assigneeId: nil, householdId: householdId, status: .next)
    await store.loadTasks()
    XCTAssertEqual(store.nextTaskCount(for: userA), 1)
}
```

Note: `createTask` signature may need to be checked — use the same pattern already in the test file. The `status` parameter may need to be set via `moveTask` if `createTask` always creates `.backlog`.

---

## Step 5 — pre-commit + push

```
pre-commit run --all-files
git add FamilyTodo/Views/TasksView.swift FamilyTodoTests/TaskStoreTests.swift
git commit -m "I1.8 Fix WIP limit to be per-assignee in TasksView"
git push -u origin feature/i1-8-per-user-task-limit
```

---

## Acceptance Checklist

- [ ] User A with 3+ tasks does not mark user B's tasks as `.warning`
- [ ] Badge shows current user's own task count when "All tasks" filter is active
- [ ] Over-limit separator only appears when a single assignee is selected
- [ ] New tests pass in CI
- [ ] `validateNextTransition` and `canMoveToNext` remain unchanged (soft limit is intentional)
- [ ] Unassigned tasks are always `.normal` zone
