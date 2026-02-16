# claude-PLAN-ux-issues.md — Implementacja 8 UX Issues

> Autor: Antigravity · Data: 2026-02-16
> Zatwierdzone przez właściciela projektu

---

## Spis zmian

| # | Issue | Pliki | Effort |
|---|-------|-------|--------|
| 2 | Unmark completed — instant revert bez sheeta | `TasksView.swift` | 15 min |
| 3+4 | Guest mode assign — auto-assign do userId | `BacklogView.swift`, `TasksView.swift` | 30 min |
| 6 | Chevron tap — cały row tappable | `TasksView.swift` | 15 min |
| 8 | Recently Purchased spacing | `ShoppingListView.swift` | 5 min |
| 10 | Soft WIP limit — color zones, no hard cap | `TaskStore.swift`, `TasksView.swift` | 45 min |
| 5 | Backlog items — rounded container | `BacklogView.swift` | 30 min |
| 1 | Completed lifecycle — 24h auto-hide + history | `TaskStore.swift`, `TasksView.swift`, `MoreView.swift` | 2h |
| 7 | Shopping long-press reorder | `ShoppingListView.swift`, `ShoppingItem.swift`, `ShoppingListStore.swift` | 2h |

**#9 (Tab colors) — SKIP.** Monotone jest poprawne z iOS 26 Liquid Glass.

---

## WAŻNE ZASADY

1. **Nie łamać istniejących funkcjonalności** — każda zmiana musi być backward-compatible
2. **Zachowywać istniejący styl kodu** — `WowAnimation.spring`, `HapticManager`, `@StateObject`, `_Concurrency.Task`
3. **Testować build po każdym kroku** — `xcodebuild build` musi przejść
4. **Commit atomicznie** — jeden commit per issue lub logiczną grupę

---

## Issue #2 — Unmark completed (instant revert)

### Problem
Kliknięcie zielonego checkmarks na completed tasku otwiera sheet "Assign and start" — zamiast po prostu cofnąć do Next.

### Root cause
`TasksView.swift:280-307` — `toggleTask` when done→next: jeśli task ma assignee, waliduje ale **nie returnuje** po pozytywnej walidacji. Wpada do else branch i otwiera picker.

### Zmiana

**Plik:** `FamilyTodo/Views/TasksView.swift`

**Linie 280-307** — funkcja `toggleTask`, zmienić blok `if newStatus == .next`:

```swift
// OBECNE (linie 283-307):
if newStatus == .next {
    if let existingAssignee = task.assigneeId {
        let validation = store.validateNextTransition(assigneeId: existingAssignee, excludingTaskId: task.id)
        guard validation == .ok else {
            handleNextTransitionValidation(validation)
            HapticManager.warning()
            return
        }
    } else {
        let members = activeMembers
        if members.count == 1, let assigneeId = members.first?.id {
            var updatedTask = task
            updatedTask.assigneeId = assigneeId
            updatedTask.assigneeIds = [assigneeId]
            updatedTask.status = .next
            _ = _Concurrency.Task {
                let validation = await store.updateTask(updatedTask)
                handleNextTransitionValidation(validation)
            }
        } else {
            pendingNextTask = task
            selectedAssigneeIdForNext = currentMember?.id
        }
        return
    }
}

// NOWE:
if newStatus == .next {
    if let existingAssignee = task.assigneeId {
        let validation = store.validateNextTransition(assigneeId: existingAssignee, excludingTaskId: task.id)
        guard validation == .ok else {
            handleNextTransitionValidation(validation)
            HapticManager.warning()
            return
        }
        // ✅ Task ma assignee — przenieś natychmiast bez sheeta
        moveTaskToNext(task, assigneeId: existingAssignee)
        return
    } else {
        let members = activeMembers
        if members.count == 1, let assigneeId = members.first?.id {
            var updatedTask = task
            updatedTask.assigneeId = assigneeId
            updatedTask.assigneeIds = [assigneeId]
            updatedTask.status = .next
            _ = _Concurrency.Task {
                let validation = await store.updateTask(updatedTask)
                handleNextTransitionValidation(validation)
            }
        } else {
            pendingNextTask = task
            selectedAssigneeIdForNext = currentMember?.id
        }
        return
    }
}
```

**Kluczowa zmiana:** Dodano `moveTaskToNext(task, assigneeId: existingAssignee)` + `return` po pozytywnej walidacji w branchu gdy assignee istnieje (linia ~290).

---

## Issue #3+4 — Guest mode auto-assign

### Problem
W trybie gościa (bez household) `memberStore.members` jest puste → Assign/Promote nie działa.

### Zmiana 1 — BacklogView

**Plik:** `FamilyTodo/Views/BacklogView.swift`

**Linie 283-301** — funkcja `promoteItem`, zmienić guard na:

```swift
// OBECNE (linie 283-287):
private func promoteItem(_ item: BacklogItem) {
    guard !activeMembers.isEmpty else {
        showBanner(.assigneeRequired)
        return
    }

// NOWE:
private func promoteItem(_ item: BacklogItem) {
    // Guest mode — auto-assign do właściciela urządzenia
    if activeMembers.isEmpty {
        if let userId = userSession.userId {
            completePromotion(of: item, assigneeId: userId)
        } else {
            showBanner(.assigneeRequired)
        }
        return
    }
```

### Zmiana 2 — TasksView

**Plik:** `FamilyTodo/Views/TasksView.swift`

**Linie 249-263** — funkcja `startTaskFromBacklog`, zmienić guard na:

```swift
// OBECNE (linie 249-254):
private func startTaskFromBacklog(_ task: Task) {
    let members = activeMembers
    guard !members.isEmpty else {
        showBanner(.assigneeRequired)
        return
    }

// NOWE:
private func startTaskFromBacklog(_ task: Task) {
    let members = activeMembers
    // Guest mode — auto-assign do właściciela urządzenia
    if members.isEmpty {
        if let userId = userSession.userId {
            moveTaskToNext(task, assigneeId: userId)
        } else {
            showBanner(.assigneeRequired)
        }
        return
    }
```

---

## Issue #6 — Chevron tap (whole row tappable)

### Problem
Strzałka `>` w `TaskRow` jest statycznym `Image` — kliknięcie nic nie robi. Edycja dopiero po kliknięciu tekstu.

### Zmiana

**Plik:** `FamilyTodo/Views/TasksView.swift`

**Linie 457-519** — cały `struct TaskRow`, zastąpić body na:

```swift
struct TaskRow: View {
    let task: Task
    let assigneeName: String?
    let onToggle: () -> Void
    let onOpenDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox — izolowany tap target
            Button(action: onToggle) {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isCompleted ? Color.green : Color.secondary.opacity(0.3), lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay {
                        if isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(width: 44, height: 44) // Apple HIG min touch target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Cała reszta wiersza → detail (w tym chevron)
            Button(action: onOpenDetail) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.system(size: 15))
                            .foregroundStyle(isCompleted ? .secondary : .primary)
                            .strikethrough(isCompleted)

                        HStack(spacing: 8) {
                            if task.taskType == .recurring {
                                Label("Recurring", systemImage: "repeat")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.purple.opacity(0.12)))
                            }

                            if let dueDate = task.dueDate {
                                dueDateLabel(dueDate)
                            }

                            if let assigneeName {
                                Text(assigneeName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.14)))
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private var isCompleted: Bool {
        task.status == .done
    }

    // zachować istniejące: dueDateLabel, dateFormatter
```

**Kluczowe zmiany:**
1. Checkbox ma `frame(width: 44, height: 44)` + `.contentShape(Rectangle())` — Apple HIG min touch target
2. Cała reszta wiersza (tekst + chevron) w jednym `Button(action: onOpenDetail)` z `.contentShape(Rectangle())`
3. Chevron jest wewnątrz tappable button zamiast standalone Image

---

## Issue #8 — Recently Purchased spacing

### Problem
`RestockItemRow` ma `.padding(.vertical, 12)` = 24pt total (za dużo).

### Zmiana

**Plik:** `FamilyTodo/Views/ShoppingListView.swift`

**Linia 731** — w `struct RestockItemRow`:

```swift
// OBECNE:
.padding(.vertical, 12)

// NOWE:
.padding(.vertical, 6)
```

---

## Issue #10 — Soft WIP limit z color zones

### Problem
Hard limit 3 tasków blokuje dodawanie. Zamiast tego: rekomendacja z kolorami.

### Zmiana 1 — TaskStore

**Plik:** `FamilyTodo/Stores/TaskStore.swift`

**Linie 28-29** — zmienić wipLimit i dodać nowego enum member:

```swift
// OBECNE:
/// WIP limit per user (max 3 tasks in "Next")
static let wipLimit = 3

// NOWE:
/// Recommended WIP limit per user (soft limit — user can exceed)
static let recommendedWipLimit = 3
```

**Linie 59-69** — zmienić `validateNextTransition` na **zawsze pozwalać** (soft limit):

```swift
// OBECNE:
func validateNextTransition(assigneeId: UUID?, excludingTaskId: UUID? = nil) -> NextTransitionValidation {
    guard let assigneeId else { return .assigneeRequired }
    let currentCount = tasks.filter {
        $0.status == .next &&
            $0.assigneeId == assigneeId &&
            $0.id != excludingTaskId
    }.count
    guard currentCount < Self.wipLimit else {
        return .wipLimitReached(current: currentCount, limit: Self.wipLimit)
    }
    return .ok
}

// NOWE:
func validateNextTransition(assigneeId: UUID?, excludingTaskId: UUID? = nil) -> NextTransitionValidation {
    guard let assigneeId else { return .assigneeRequired }
    // Soft limit — zawsze zwracaj .ok, UI pokaże ostrzeżenie kolorami
    return .ok
}
```

> **UWAGA:** Nie usuwaj enum `NextTransitionValidation` ani case `.wipLimitReached` — mogą być używane gdzie indziej. Tylko zmień logikę w `validateNextTransition` żeby zawsze zwracała `.ok` (jeśli assignee istnieje).

**Dodać helper** — nową computed property w `TaskStore`:

```swift
/// Count of currently active (Next) tasks for a given user
func nextTaskCount(for assigneeId: UUID) -> Int {
    tasks.filter { $0.status == .next && $0.assigneeId == assigneeId }.count
}
```

### Zmiana 2 — TasksView focusRuleBanner

**Plik:** `FamilyTodo/Views/TasksView.swift`

**Linie 229-247** — zastąpić `focusRuleBanner` na dynamiczny z color zones:

```swift
// OBECNE:
private var focusRuleBanner: some View {
    HStack(spacing: 12) {
        Image(systemName: "target")
            .font(.system(size: 18))
            .foregroundStyle(.blue)

        Text("Focus on max 3 active tasks")
            .font(.system(size: 14))
            .foregroundStyle(.primary)

        Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background {
        RoundedRectangle(cornerRadius: 12)
            .fill(.blue.opacity(0.1))
    }
}

// NOWE:
private var focusRuleBanner: some View {
    let count = store.nextTasks.count
    let (bannerColor, bannerIcon, bannerText): (Color, String, String) = {
        switch count {
        case 0:
            return (.blue, "plus.circle", "Add tasks from Backlog to start")
        case 1...3:
            return (.blue, "target", "\(count) of 3 recommended slots used")
        case 4...5:
            return (.orange, "exclamationmark.circle",
                "\(count) active — consider finishing some first")
        default:
            return (.red, "exclamationmark.triangle",
                "\(count) active — too many tasks reduces focus")
        }
    }()

    HStack(spacing: 12) {
        Image(systemName: bannerIcon)
            .font(.system(size: 18))
            .foregroundStyle(bannerColor)

        Text(bannerText)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)

        Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background {
        RoundedRectangle(cornerRadius: 12)
            .fill(bannerColor.opacity(0.1))
    }
}
```

### Zmiana 3 — TasksView InlineBanner

**Plik:** `FamilyTodo/Views/TasksView.swift`

**Linie 22-33** — usunąć case `wipLimitReached` z InlineBanner (nie jest już używany jako blokujący banner):

Ten krok jest **opcjonalny** — jeśli `InlineBanner.wipLimitReached` nie jest wyświetlany z powodu zmiany w `validateNextTransition`, to kod jest dead ale nie szkodzi.

### Zmiana 4 — TaskRow color coding (opcjonalnie)

Dodać do `TaskRow` opcjonalny parametr `wipZone` do kolorowania wierszy:

```swift
struct TaskRow: View {
    let task: Task
    let assigneeName: String?
    let wipZone: WipZone  // NOWE
    let onToggle: () -> Void
    let onOpenDetail: () -> Void

    enum WipZone {
        case normal    // pozycja 1-3
        case warning   // pozycja 4-5
        case danger    // pozycja 6+
    }
    // ...
}
```

W body dodać subtleny left border na warning/danger:

```swift
.overlay(alignment: .leading) {
    if wipZone != .normal {
        RoundedRectangle(cornerRadius: 2)
            .fill(wipZone == .warning ? Color.orange : Color.red)
            .frame(width: 3)
    }
}
```

W `TasksContent` przy tworzeniu `TaskRow` w sekcji NEXT — obliczać zone:

```swift
ForEach(Array(store.nextTasks.enumerated()), id: \.element.id) { index, task in
    let zone: TaskRow.WipZone = index < 3 ? .normal : (index < 5 ? .warning : .danger)
    TaskRow(
        task: task,
        assigneeName: assigneeName(for: task),
        wipZone: zone,
        onToggle: { toggleTask(task) },
        onOpenDetail: { selectedTask = task }
    )
```

**UWAGA:** `TaskRow` jest używany też w sekcjach BACKLOG i COMPLETED — tam zawsze przekazuj `.normal`.

---

## Issue #5 — Backlog items: rounded container

### Problem
Backlog items w `CategoryCard` to płaskie wiersze z bullet `Circle` i `Divider`. Potrzebujemy zaokrąglonych containerów per item (jak Apple Reminders).

### Zmiana 1 — BacklogItemRow

**Plik:** `FamilyTodo/Views/BacklogView.swift`

**Linie 619-689** — zmienić `BacklogItemRow.body`:

```swift
// OBECNE:
var body: some View {
    HStack(spacing: 12) {
        Circle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 6, height: 6)

        VStack(alignment: .leading, spacing: 4) {
            // ...
        }

        Spacer()

        Menu { /* ... */ }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
    .onTapGesture {
        onTap()
    }
}

// NOWE:
@Environment(\.colorScheme) private var colorScheme

var body: some View {
    HStack(spacing: 12) {
        Circle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 6, height: 6)

        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 15))
                .strikethrough(false)

            if let assigneeName {
                Text(assigneeName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.14)))
            }
        }

        Spacer()

        Menu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                onAssign()
            } label: {
                Label("Assign", systemImage: "person.crop.circle.badge.plus")
            }

            Button {
                onPromote()
            } label: {
                Label("Promote", systemImage: "arrow.up.circle")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(
        RoundedRectangle(cornerRadius: 10)
            .fill(colorScheme == .dark
                ? Color.white.opacity(0.06)
                : Color(.systemBackground))
    )
    .contentShape(Rectangle())
    .onTapGesture {
        onTap()
    }
}
```

**Kluczowe zmiany:**
1. Dodać `@Environment(\.colorScheme) private var colorScheme` do `BacklogItemRow`
2. Zmienić padding z `.horizontal: 16, .vertical: 12` na `.horizontal: 14, .vertical: 10`
3. Dodać `.background(RoundedRectangle(cornerRadius: 10).fill(...))`

### Zmiana 2 — CategoryCard: usunąć Divider

**Plik:** `FamilyTodo/Views/BacklogView.swift`

**Linie 494-522** — w `CategoryCard.body`, zmienić ForEach + Divider:

```swift
// OBECNE (linie 494-522):
ForEach(items) { item in
    BacklogItemRow(
        item: item,
        assigneeName: assigneeNameFor(item.assigneeId),
        onTap: { onEditItem(item) },
        onEdit: { onEditItem(item) },
        onAssign: { onAssignItem(item) },
        onPromote: { onPromoteItem(item) },
        onDelete: { onDeleteItem(item) }
    )
    .swipeActions(edge: .leading, allowsFullSwipe: false) { /* ... */ }
    .swipeActions(edge: .trailing) { /* ... */ }

    Divider()
        .padding(.leading, 16)
}

// NOWE:
VStack(spacing: 6) {
    ForEach(items) { item in
        BacklogItemRow(
            item: item,
            assigneeName: assigneeNameFor(item.assigneeId),
            onTap: { onEditItem(item) },
            onEdit: { onEditItem(item) },
            onAssign: { onAssignItem(item) },
            onPromote: { onPromoteItem(item) },
            onDelete: { onDeleteItem(item) }
        )
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onPromoteItem(item)
            } label: {
                Label("Promote", systemImage: "arrow.up.circle")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDeleteItem(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
.padding(.horizontal, 8)
.padding(.bottom, 8)
```

**Kluczowe zmiany:**
1. Owinąć `ForEach` w `VStack(spacing: 6)`
2. Usunąć `Divider()` pomiędzy itemami
3. Dodać `padding(.horizontal, 8)` i `.padding(.bottom, 8)` na VStack
4. Zachować swipe actions bez zmian

> **UWAGA:** swipeActions mogą nie działać na custom VStack — jeśli nie działają, trzeba wrócić do `List` wewnątrz card albo usunąć swipe actions dla tych itemów (context menu zostaje).

---

## Issue #1 — Completed tasks lifecycle

### Problem
Completed tasks siedzą w Tasks na stałe. User musi wiedzieć że znikną i gdzie je znaleźć.

### Zmiana 1 — TaskStore: recentlyDoneTasks

**Plik:** `FamilyTodo/Stores/TaskStore.swift`

**Po linii 56** (po `doneTasks`) — dodać:

```swift
/// Recently completed tasks (last 24h) — shown in Tasks tab
var recentlyDoneTasks: [Task] {
    doneTasks.filter { task in
        guard let completedAt = task.completedAt else { return true }
        return completedAt > Date().addingTimeInterval(-86400)
    }
}

/// Archived completed tasks (older than 24h) — shown in More → Completed Tasks
var archivedDoneTasks: [Task] {
    doneTasks.filter { task in
        guard let completedAt = task.completedAt else { return false }
        return completedAt <= Date().addingTimeInterval(-86400)
    }
}
```

### Zmiana 2 — TasksView: użyć recentlyDoneTasks

**Plik:** `FamilyTodo/Views/TasksView.swift`

**Linie 117-130** — zmienić sekcję COMPLETED:

```swift
// OBECNE:
if !store.doneTasks.isEmpty {
    sectionHeader("COMPLETED")

    ForEach(store.doneTasks) { task in

// NOWE:
if !store.recentlyDoneTasks.isEmpty {
    sectionHeader("COMPLETED")

    ForEach(store.recentlyDoneTasks) { task in
```

### Zmiana 3 — TasksView: info banner (one-time)

**Plik:** `FamilyTodo/Views/TasksView.swift`

Dodać `@AppStorage` do `TasksContent`:

```swift
// Po linii 44 (po @State private var activeBanner):
@AppStorage("hasSeenCompletedTasksInfo") private var hasSeenCompletedTasksInfo = false
```

Dodać banner po sekcji COMPLETED (wewnątrz `LazyVStack`, po ForEach completed):

```swift
// Po zamknięciu "if !store.recentlyDoneTasks.isEmpty { ... }":
if !store.recentlyDoneTasks.isEmpty, !hasSeenCompletedTasksInfo {
    completedTasksInfoBanner
        .padding(.top, 12)
}
```

Dodać nowy computed property:

```swift
private var completedTasksInfoBanner: some View {
    HStack(spacing: 10) {
        Image(systemName: "info.circle")
            .font(.system(size: 14))
            .foregroundStyle(.blue)

        Text("Completed tasks move to More → Completed Tasks after 24h")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)

        Spacer()

        Button {
            withAnimation(WowAnimation.easeOut) {
                hasSeenCompletedTasksInfo = true
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
        RoundedRectangle(cornerRadius: 10)
            .fill(.blue.opacity(0.08))
    )
}
```

### Zmiana 4 — MoreView: dodać "Completed Tasks"

**Plik:** `FamilyTodo/Views/MoreView.swift`

**Linie 30-72** — w sekcji Settings group (`VStack(spacing: 0)`), dodać nowy NavigationLink **przed** Settings (po Household/Categories):

```swift
// Dodać nowy link w VStack(spacing: 0), po "Categories" link, przed "Settings" link:

Divider()
    .padding(.leading, 52)

NavigationLink {
    CompletedTasksView()
} label: {
    MoreRow(icon: "checkmark.circle", title: "Completed Tasks", tint: .green)
}
.buttonStyle(.plain)
.accessibilityIdentifier("CompletedTasks")
```

### Zmiana 5 — CompletedTasksView (nowy)

Stworzyć nowy plik: **`FamilyTodo/Views/CompletedTasksView.swift`**

```swift
import SwiftData
import SwiftUI

struct CompletedTasksView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                CompletedTasksContent(householdId: householdId, modelContext: modelContext)
            } else {
                ContentUnavailableView {
                    Label("No Household", systemImage: "house")
                } description: {
                    Text("Join or create a household to see completed tasks.")
                }
            }
        }
    }
}

private struct CompletedTasksContent: View {
    @StateObject private var store: TaskStore
    @EnvironmentObject private var userSession: UserSession

    init(householdId: UUID, modelContext: ModelContext) {
        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(householdId)
        _store = StateObject(wrappedValue: taskStore)
    }

    var body: some View {
        Group {
            if store.doneTasks.isEmpty {
                ContentUnavailableView {
                    Label("No Completed Tasks", systemImage: "checkmark.circle")
                } description: {
                    Text("Tasks you complete will appear here.")
                }
            } else {
                List {
                    ForEach(store.doneTasks) { task in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(task.title)
                                    .font(.system(size: 15))
                                    .strikethrough(true)
                                    .foregroundStyle(.secondary)

                                Spacer()
                            }

                            if let notes = task.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }

                            if let completedAt = task.completedAt {
                                Text(completedAt, style: .relative)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Completed Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.setSyncMode(userSession.syncMode)
            await store.loadTasks()
        }
    }
}
```

> **UWAGA:** Dodać plik do Xcode project (powinno się dodać automatycznie jeśli jest w dobrym folderze).

---

## Issue #7 — Shopping list long-press reorder

### Problem
Brak możliwości zmiany kolejności elementów na liście zakupów.

### Zmiana 1 — ShoppingItem: dodać sortOrder

**Plik:** `FamilyTodo/Models/ShoppingItem.swift`

Dodać nowy property:

```swift
var sortOrder: Int = 0
```

### Zmiana 2 — ShoppingListStore: dodać moveItems

**Plik:** `FamilyTodo/Stores/ShoppingListStore.swift`

Dodać:

```swift
/// Reorder items by moving from source indices to destination
func moveItems(from source: IndexSet, to destination: Int) {
    var items = toBuyItems
    items.move(fromOffsets: source, toOffset: destination)
    for (index, var item) in items.enumerated() {
        item.sortOrder = index
    }
    // Persist order
    saveToBuyItems(items)
}
```

> **UWAGA:** Dokładna implementacja `saveToBuyItems` zależy od obecnego persistence API w store. Przejrzeć `ShoppingListStore` i zaimplementować nadpisanie sortOrder dla każdego itemu.

### Zmiana 3 — ShoppingListView: dodać drag reorder

**Plik:** `FamilyTodo/Views/ShoppingListView.swift`

W `ForEach(store.toBuyItems)` (około linii 96) — dodać `.draggable` i `.dropDestination`:

```swift
ForEach(store.toBuyItems) { item in
    // ... istniejące row UI ...
}
.onMove { from, to in
    store.moveItems(from: from, to: to)
    HapticManager.lightTap()
}
```

> **UWAGA:** `.onMove` wymaga `List` — obecny UI to `LazyVStack`. Trzeba albo:
> 1. Zamienić `LazyVStack` na `List` (ryzykowne — rapid entry flow)
> 2. Użyć `.draggable()` + `.dropDestination()` (iOS 16+) na `LazyVStack`
> 3. Dodać `EditButton` w header i manual ↑↓ buttons
>
> Zalecanym podejściem jest wariant 2 — `.draggable()`:

```swift
ForEach(store.toBuyItems) { item in
    if itemBeingRemoved != item.id {
        // ... istniejące row UI ...
    }
}
.draggable(item) // iOS 16+
```

Albo implementacja z custom `DragRelocateDelegate`:

```swift
// Nowy helper struct:
struct ShoppingDragDelegate: DropDelegate {
    let item: ShoppingItem
    @Binding var items: [ShoppingItem]
    @Binding var draggedItem: ShoppingItem?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }),
              fromIndex != toIndex else { return }
        withAnimation(WowAnimation.spring) {
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }
}
```

**To jest najbardziej złożona zmiana** — wymaga testowania z rapid entry flow. Jeśli napotkasz problemy, zaimplementuj prostszą wersję z manual sort buttons zamiast drag.

---

## Kolejność implementacji

```
1. ✂️ Issue #2 — Unmark completed (1 zmiana, 1 plik)
2. ✂️ Issue #3+4 — Guest mode assign (2 zmiany, 2 pliki)
3. ✂️ Issue #6 — Chevron tap (1 zmiana, 1 plik)
4. ✂️ Issue #8 — Recently Purchased spacing (1 linia)
5. 🔧 Issue #10 — Soft WIP limit (3 zmiany, 2 pliki)
6. 🎨 Issue #5 — Backlog rounded container (2 zmiany, 1 plik)
7. 📋 Issue #1 — Completed lifecycle (5 zmian, 3 pliki + 1 nowy)
8. 🔀 Issue #7 — Shopping reorder (3 zmiany, 3 pliki)
```

**Build check po każdym kroku!**

---

## Test matrix

| Test | Co sprawdzić | Device |
|------|-------------|--------|
| Unmark completed | Klik zielony checkmark → task wraca do NEXT natychmiast (bez sheeta) | Wszystkie |
| Guest assign | Guest bez household → Promote w Backlog działa (auto-assign) | Simulator |
| Chevron tap | Klik na `>` otwiera TaskDetailSheet | Wszystkie |
| Checkbox tap area | Checkbox reaguje, ale nie otwiera detail | Wszystkie |
| Recently Purchased | Mniejsze odstępy w liście | Wszystkie |
| WIP banner 0 | "Add tasks from Backlog to start" (blue) | Wszystkie |
| WIP banner 1-3 | "2 of 3 recommended slots used" (blue) | Wszystkie |
| WIP banner 4-5 | "4 active — consider finishing some first" (orange) | Wszystkie |
| WIP banner 6+ | "7 active — too many tasks reduces focus" (red) | Wszystkie |
| WIP row colors | Rows 4-5 pomarańczowy indicator, 6+ czerwony | Wszystkie |
| Backlog container | Zaokrąglone containerki per item, no dividers | Wszystkie |
| Completed 24h | Completed tasks znikają z Tasks po 24h | Simulator (zmienić czas) |
| Completed info banner | Jednorazowy info banner w Tasks | Wszystkie |
| Completed Tasks More | More → Completed Tasks pokazuje historię | Wszystkie |
| Shopping reorder | Long-press → drag to reorder | Wszystkie |

---

## 🔴 CI Fix — Build failure po wdrożeniu

### Błąd

Build `22060361720` (commit `4e2997e`) padł na:

```
❌ TasksView.swift:238:44: function declares an opaque return type,
   but has no return statements in its body from which to infer an underlying type

⚠️ TasksView.swift:264:10: result of call to 'background(alignment:content:)' is unused
```

### Root cause

`focusRuleBanner: some View` (L238-268) ma **multi-statement body**:

```swift
private var focusRuleBanner: some View {   // ← opaque return type
    let count = store.nextTasks.count       // ← statement 1
    let state: (...) = switch count { ... } // ← statement 2
    HStack { ... }                          // ← view (statement 3)
        .background { ... }                 // ← trailing — traktowane jako osobny statement!
}
```

Swift wymaga **single-expression body** dla inferencji `some View` w computed property.
Codex użył `let state = switch count { ... }` — to poprawna składnia Swift 5.9, ale w multi-statement computed property kompilator nie jest w stanie wywnioskować typu `some View`.

Warning `.background is unused` to efekt uboczny — kompilator traktuje `.background { }` jako osobne wyrażenie (nie chain na `HStack`), bo jest zdezorientowany przez wieloliniowy body.

### Rozwiązanie

Dodać `@ViewBuilder` do computed property. To mówi Swiftowi, żeby traktował body jako view builder (jak `var body`), co pozwala na `let` statements + view content:

**Plik:** `FamilyTodo/Views/TasksView.swift`

**Linia 238** — dodać `@ViewBuilder`:

```swift
// OBECNE:
private var focusRuleBanner: some View {

// NOWE:
@ViewBuilder
private var focusRuleBanner: some View {
```

To jedyna potrzebna zmiana. `@ViewBuilder` pozwala na:
- lokalne `let` bindingi
- wieloliniowy body z view hierarchią
- poprawne chainowanie `.background { }` na `HStack`

### Alternatywne rozwiązanie (jeśli `@ViewBuilder` nie wystarczy)

Wyciągnąć tuple do osobnej funkcji:

```swift
private func focusBannerState() -> (color: Color, icon: String, text: String) {
    let count = store.nextTasks.count
    switch count {
    case 0:
        return (.blue, "plus.circle", "Add tasks from Backlog to start")
    case 1 ... TaskStore.recommendedWipLimit:
        return (.blue, "target", "\(count) of \(TaskStore.recommendedWipLimit) recommended slots used")
    case 4 ... 5:
        return (.orange, "exclamationmark.circle", "\(count) active - consider finishing some first")
    default:
        return (.red, "exclamationmark.triangle", "\(count) active - too many tasks reduces focus")
    }
}

private var focusRuleBanner: some View {
    let state = focusBannerState()
    // ... reszta bez zmian
}
```

> To drugie rozwiązanie też wymaga `@ViewBuilder` jeśli jest `let` w computed property — więc użyj rozwiązania 1.
