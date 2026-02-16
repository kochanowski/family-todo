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

---

## 🔴 CRASH Fix — App nie uruchamia się na iPhone (fatalError w ModelContainer)

### Crash log

```
Incident:     2C628A62-E67B-4F90-ADD7-E413CC3F236B
Device:       iPhone15,4 · iOS 26.2.1 · Build 238 (TestFlight)
Launch→Crash: 0.57s

Exception Type: EXC_BREAKPOINT (SIGTRAP)
Thread 0 Crashed:
0  libswiftCore.dylib
1  HousePulse - closure #1 in variable initialization expression of
                FamilyTodoApp.sharedModelContainer + 1132 (FamilyTodoApp.swift:49)
2  HousePulse - FamilyTodoApp.init() + 24 (FamilyTodoApp.swift:13)
```

### Root cause

**`CachedShoppingItem.sortOrder: Int` (L16) — brak wartości domyślnej.**

`FamilyTodoApp.swift:36` tworzy `ModelContainer(for: schema, configurations:)`. SwiftData używa **lightweight auto-migration** (brak `VersionedSchema` / `MigrationPlan` w projekcie). Kiedy SwiftData próbuje dodać kolumnę `sortOrder INTEGER NOT NULL` do istniejącej tabeli SQLite, która ma wiersze — SQLite odmawia, bo `NOT NULL` bez `DEFAULT` jest niewykonalne dla istniejących rekordów.

```
SQLite error: "Cannot add a NOT NULL column with default value NULL"
→ ModelContainer(for:configurations:) throws
→ catch block (L37-50) → fatalError (L49)
→ EXC_BREAKPOINT
```

**To dotyczy TYLKO użytkowników z istniejącymi danymi** (TestFlight / App Store). Nowe instalacje i CI (in-memory store) działają poprawnie — dlatego build przechodzi, ale app crashuje na iPhone.

### Zmiana 1 — Dodać default do sortOrder (KRYTYCZNE)

**Plik:** `FamilyTodo/Models/CachedShoppingItem.swift`

**Linia 16:**

```swift
// OBECNE:
var sortOrder: Int

// NOWE:
var sortOrder: Int = 0
```

To pozwala SwiftData na lightweight migration: `ALTER TABLE CachedShoppingItem ADD COLUMN sortOrder INTEGER NOT NULL DEFAULT 0`.

### Zmiana 2 — FamilyTodoApp: recovery zamiast fatalError (KRYTYCZNE)

**Plik:** `FamilyTodo/FamilyTodoApp.swift`

**Linie 35-51** — zamienić `fatalError` na resiliency path:

```swift
// OBECNE (linie 35-51):
do {
    return try ModelContainer(for: schema, configurations: [modelConfiguration])
} catch {
    #if CI
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        } catch {
            fatalError("Could not create CI ModelContainer: \(error)")
        }
    #else
        fatalError("Could not create ModelContainer: \(error)")
    #endif
}

// NOWE:
do {
    return try ModelContainer(for: schema, configurations: [modelConfiguration])
} catch {
    #if CI
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        } catch {
            fatalError("Could not create CI ModelContainer: \(error)")
        }
    #else
        // Migration failed — destroy corrupt/incompatible store and retry.
        // User loses local data but app can launch. Cloud data will re-sync.
        print("⚠️ ModelContainer migration failed: \(error)")
        print("⚠️ Destroying local store and retrying...")

        let storeURL = modelConfiguration.url
        let storePath = storeURL.path()
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: storePath + suffix)
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer after reset: \(error)")
        }
    #endif
}
```

> **UWAGA:** `modelConfiguration.url` zwraca URL do pliku SQLite. Trzeba też usunąć `-shm` i `-wal` (WAL journal files). Jeśli `ModelConfiguration` nie expo url, użyj:
> ```swift
> let defaultURL = URL.applicationSupportDirectory
>     .appending(path: "default.store")
> ```

### Zmiana 3 — Sprawdzić inne @Model klasy (OPCJONALNIE)

Przeszukać wszystkie `@Model` klasy pod kątem nowych non-optional properties bez defaultów. Wynik skanowania:

| Model | Property | Default? | Status |
|-------|----------|----------|--------|
| `CachedShoppingItem` | `sortOrder: Int` | ❌ BRAK | 🔴 CRASH |
| `CachedTask` | `completedAt: Date?` | ✅ Optional | OK |
| `CachedTask` | `completedById: String?` | ✅ Optional | OK |
| `CachedTask` | `notes: String?` | ✅ Optional | OK |
| Inne modele | — | ✅ | OK |

**Tylko `CachedShoppingItem.sortOrder` wymaga naprawy.**

### Zasada na przyszłość

> **Każdy nowy property w `@Model` MUSI mieć:**
> - wartość domyślną (`= 0`, `= ""`, `= false`), **LUB**
> - być Optional (`Type?`)
>
> Inaczej SwiftData lightweight migration zawsze crashnie na istniejących użytkownikach.

---
---

# UX Round 2 — 10 nowych issues (2026-02-16 13:58)

## Spis zmian

| # | Issue | Pliki | Effort | Status |
|---|-------|-------|--------|--------|
| R2-1 | Banner „Add tasks" → tap naviguje do Backlog | `TasksView.swift` | 15 min | ✅ DO |
| R2-2 | ~~Backlog promote~~ | — | — | ❌ SKIP — działa OK |
| R2-3 | More: ikona „Task History" — spójność | `MoreView.swift` | 5 min | ✅ DO |
| R2-4 | Completed task: swipe → archiwizuj | `TasksView.swift` | 30 min | ✅ DO |
| R2-5 | Nazwy: „Completed" (Tasks) + „Task History" (More) | `TasksView.swift`, `MoreView.swift` | 15 min | ✅ DO |
| R2-6 | More → Task History: cleanup options | `MoreView.swift` | 45 min | ✅ DO |
| R2-7 | ~~Shopping badge kolory~~ | — | — | ❌ SKIP |
| R2-8 | Settings: konfigurowalny WIP limit (1-7) | `MoreView.swift`, `TaskStore.swift`, `TasksView.swift` | 45 min | ✅ DO |
| R2-9 | Tasks: mniejsze odstępy | `TasksView.swift` | 5 min | ✅ DO |
| R2-10 | Checkbox: square fill (blue) | `TasksView.swift` | 15 min | ✅ DO |
| R2-11 | WIP zone: zielony border dla zadań 1-3 | `TasksView.swift` | 10 min | ✅ DO (NOWE) |

### Decyzje użytkownika (2026-02-16 14:07)

- **Checkbox:** Opcja B — `square` → `checkmark.square.fill` (.blue)
- **Nazwy:** „COMPLETED" w Tasks (bez zmian) + „Task History" w More
- **Shopping badge:** zostawić bez zmian
- **Backlog promote:** działa poprawnie — drop
- **WIP kolory:** zielony left border dla pozycji 1-3 (normal zone)

---

## R2-1 — Banner „Add tasks from Backlog" → tap naviguje do Backlog

### Problem
Gdy NEXT jest puste, banner mówi „Add tasks from Backlog to start" z ikoną `plus.circle` — ale kliknięcie nic nie robi. Intuicyjnie user chce kliknąć i przejść do Backlog.

### Zmiana

**Plik:** `FamilyTodo/Views/TasksView.swift`

Dodać `@Binding var selectedTab: AppTab` lub użyć `@EnvironmentObject` z tab selection. Owinąć banner w `Button` gdy `count == 0`:

```swift
// OBECNE (L238-269):
@ViewBuilder
private var focusRuleBanner: some View {
    let count = store.nextTasks.count
    // ... HStack z tekstem i ikoną
}

// NOWE:
@ViewBuilder
private var focusRuleBanner: some View {
    let count = store.nextTasks.count
    let state: (color: Color, icon: String, text: String) = switch count {
    case 0:
        (.blue, "plus.circle", "Add tasks from Backlog to start")
    // ... reszta bez zmian
    }

    if count == 0 {
        Button {
            // Przejdź do Backlog tab
            tabSelection = .backlog
        } label: {
            bannerContent(state: state)
        }
        .buttonStyle(.plain)
    } else {
        bannerContent(state: state)
    }
}

private func bannerContent(state: (color: Color, icon: String, text: String)) -> some View {
    HStack(spacing: 12) {
        Image(systemName: state.icon)
            .font(.system(size: 18))
            .foregroundStyle(state.color)
        Text(state.text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
        Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background {
        RoundedRectangle(cornerRadius: 12)
            .fill(state.color.opacity(0.1))
    }
}
```

> **UWAGA:** Wymaga dostępu do tab selection binding. Sprawdzić jak `ContentView` zarządza `TabView` selection i przekazać do `TasksContent`.

---

## R2-2 — Backlog → Tasks promote nadal nie działa

### Problem
User nie może przenieść zadania z Backlog do Tasks. Kod `promoteItem` (L283-305) wygląda poprawnie strukturalnie — trzeba debugować.

### Możliwe root causes

1. **`userSession.userId` jest `nil` w guest mode** — sprawdzić czy `userId` jest ustawiany w `UserSession` dla gościa
2. **`UUID(uuidString: userId)` zwraca `nil`** — jeśli `userId` nie jest poprawnym UUID stringiem (np. jest Apple ID zamiast UUID)
3. **`store.promoteItemToTask` zwraca błąd** — walidacja wewnętrzna blokuje

### Sposób debugowania

Dodać tymczasowe `print()` lub sprawdzić w `TaskStore.promoteItemToTask`:

```swift
// W BacklogView.swift L283-290, dodać logi:
private func promoteItem(_ item: BacklogItem) {
    print("DEBUG promoteItem: activeMembers=\(activeMembers.count), userId=\(userSession.userId ?? "nil")")
    if activeMembers.isEmpty {
        if let userId = userSession.userId, let assigneeId = UUID(uuidString: userId) {
            print("DEBUG: guest promote with assigneeId=\(assigneeId)")
            completePromotion(of: item, assigneeId: assigneeId)
        } else {
            print("DEBUG: no userId or UUID parse failed. userId=\(userSession.userId ?? "nil")")
            showBanner(.assigneeRequired)
        }
        return
    }
    // ... reszta
}
```

Sprawdzić `promoteItemToTask` w `TaskStore` — czy nie blokuje z powodu soft WIP limitu lub innej walidacji.

---

## R2-3 — More: ikona Completed Tasks — spójność kolorów

### Problem
W More lista: Backlog Categories (gray), Repetitive Tasks (gray), **Completed Tasks (green)**, Settings (gray). Zielona ikona jest niespójna.

### Zmiana

**Plik:** `FamilyTodo/Views/MoreView.swift`

**Linia 63:**

```swift
// OBECNE:
MoreRow(icon: "checkmark.circle", title: "Completed Tasks", tint: .green)

// NOWE:
MoreRow(icon: "checkmark.circle", title: "Completed Tasks")
```

Usunąć `tint: .green` → domyślne `.primary` (jak reszta ikon). Opcjonalnie zmienić ikonę na `clock.arrow.circlepath` (history) co lepiej oddaje „archiwum".

---

## R2-4 — Completed task: long-press/swipe → archiwizuj do More

### Problem
Completed tasks w Tasks nie mają opcji szybkiego przeniesienia do archiwum (More → Completed Tasks). User chce long-press lub swipe.

### Zmiana

**Plik:** `FamilyTodo/Views/TasksView.swift`

**Linie 123-133** — dodać swipe actions i context menu do completed task rows:

```swift
// OBECNE (L123-133):
ForEach(store.recentlyDoneTasks) { task in
    TaskRow(
        task: task,
        assigneeName: assigneeName(for: task),
        wipZone: .normal,
        onToggle: { toggleTask(task) },
        onOpenDetail: { selectedTask = task }
    )
    .rowInsertAnimation()
    .accessibilityIdentifier("taskRowCompleted_\(task.title)")
}

// NOWE:
ForEach(store.recentlyDoneTasks) { task in
    TaskRow(
        task: task,
        assigneeName: assigneeName(for: task),
        wipZone: .normal,
        onToggle: { toggleTask(task) },
        onOpenDetail: { selectedTask = task }
    )
    .swipeActions(edge: .trailing) {
        Button {
            archiveTask(task)
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .tint(.orange)
    }
    .contextMenu {
        Button {
            archiveTask(task)
        } label: {
            Label("Move to History", systemImage: "archivebox")
        }

        Button {
            toggleTask(task)
        } label: {
            Label("Undo Complete", systemImage: "arrow.uturn.backward")
        }
    }
    .rowInsertAnimation()
    .accessibilityIdentifier("taskRowCompleted_\(task.title)")
}
```

Dodać helper function:

```swift
private func archiveTask(_ task: Task) {
    // Ustaw completedAt na >24h temu → przeniesie do archivedDoneTasks
    var updated = task
    updated.completedAt = Date().addingTimeInterval(-86401)
    _ = _Concurrency.Task {
        await store.updateTask(updated)
    }
}
```

---

## R2-5 — Nazwy sekcji: „Recently Done" vs „Task History"

### Propozycje nazw

| Tasks tab | More tab | Logika |
|-----------|----------|--------|
| **Recently Done** | **Task History** | DONE = świeże (24h), HISTORY = archiwum |
| **Just Finished** | **All Completed** | Lekki vs formalny |
| **Done Today** | **Past Tasks** | Temporalny podział |
| **✓ Recent** | **✓ Archive** | Minimalistyczne |

**Rekomendacja:** **„Recently Done"** (Tasks) + **„Task History"** (More)

### Zmiana

1. **`TasksView.swift` L121:** `sectionHeader("COMPLETED")` → `sectionHeader("RECENTLY DONE")`
2. **`MoreView.swift` L63:** `title: "Completed Tasks"` → `title: "Task History"`
3. **`MoreView.swift` CompletedTasksView:** zmienić `navigationTitle` i empty state text

---

## R2-6 — More → Task History: opcje czyszczenia

### Propozycje

Tak — Clean All + Clean by period to dobre pomysły. Proponuję:

- **Clear All** — kasuje całą historię
- **Keep Last 7 Days** — zostawia ostatni tydzień
- **Keep Last 30 Days** — zostawia ostatni miesiąc

### Zmiana

**Plik:** `FamilyTodo/Views/MoreView.swift` — w `CompletedTasksView`

Dodać toolbar button z menu:

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Menu {
            Button(role: .destructive) {
                clearArchivedTasks(olderThan: nil) // all
            } label: {
                Label("Clear All", systemImage: "trash")
            }

            Button {
                clearArchivedTasks(olderThan: 7)
            } label: {
                Label("Keep Last 7 Days", systemImage: "calendar")
            }

            Button {
                clearArchivedTasks(olderThan: 30)
            } label: {
                Label("Keep Last 30 Days", systemImage: "calendar.badge.clock")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17))
        }
    }
}
```

Dodać do `TaskStore`:

```swift
func clearArchivedTasks(keepingDays: Int?) {
    let cutoff: Date? = keepingDays.map { Date().addingTimeInterval(-Double($0) * 86400) }
    tasks.removeAll { task in
        guard task.status == .done,
              let completedAt = task.completedAt,
              completedAt <= Date().addingTimeInterval(-86400)
        else { return false }

        if let cutoff { return completedAt < cutoff }
        return true  // Clear All
    }
    // Persist deletion
}
```

---

## R2-7 — Shopping: spójność kolorów Add item + badge

### Obecny stan
- Add item pill: `.fill(.blue)` + blue shadow
- Count badge: `.fill(.blue)`

### Rekomendacja

Niebieskie jest OK jako akcent akcji — spójne z iOS native. Ale można rozważyć:

**Opcja A (zachowaj blue, subtelniejszy badge):**
```swift
// Badge (L220):
.background(Capsule().fill(.blue.opacity(0.15)))  // zamiast solid blue
.foregroundStyle(.blue)  // zamiast .white
```

**Opcja B (system tint — dopasuje się do theme):**
```swift
// Add pill (L283):
.fill(Color.accentColor)

// Badge:
.background(Capsule().fill(Color.accentColor))
```

**Opcja C (bez zmian):** Niebieskie FAB-style przyciski to standard iOS (np. Reminders, Notes). Jeśli reszta aplikacji też używa `.blue` jako akcentu — jest spójne.

> **Rekomendacja:** Opcja A — zmniejsz wizualną wagę badge'a, zachowaj blue na CTA. Badge z pełnym `.blue` rywalizuje z przyciskiem o uwagę.

---

## R2-8 — Settings: konfigurowalny WIP limit (1-7)

### Zmiana 1 — TaskStore

**Plik:** `FamilyTodo/Stores/TaskStore.swift`

```swift
// OBECNE:
static let recommendedWipLimit = 3

// NOWE:
@AppStorage("recommendedWipLimit") static var recommendedWipLimit = 3
```

> **UWAGA:** `@AppStorage` na `static var` nie działa w Swift — trzeba refaktorować na instancyjny property lub używać `UserDefaults.standard.integer(forKey:)`. Proponuję:

```swift
static var recommendedWipLimit: Int {
    let stored = UserDefaults.standard.integer(forKey: "recommendedWipLimit")
    return stored > 0 ? stored : 3
}
```

### Zmiana 2 — SettingsView

**Plik:** `FamilyTodo/Views/MoreView.swift` — w `SettingsView` (L643+)

Dodać nową sekcję po toggles:

```swift
Section("Tasks") {
    HStack {
        Label("Recommended task limit", systemImage: "target")
            .foregroundStyle(.primary)

        Spacer()

        Stepper(
            "\(wipLimit)",
            value: $wipLimit,
            in: 1...7
        )
        .frame(width: 120)
    }
}
```

Z `@AppStorage`:

```swift
@AppStorage("recommendedWipLimit") private var wipLimit = 3
```

### Zmiana 3 — TasksView banner

Banner już używa `TaskStore.recommendedWipLimit` — będzie automatycznie reagować na zmianę UserDefaults.

---

## R2-9 — Tasks: mniejsze odstępy między zadaniami

### Problem
`TaskRow` ma `.padding(.vertical, 12)` = 24pt total. Za dużo, zwłaszcza widoczne na screenshocie.

### Zmiana

**Plik:** `FamilyTodo/Views/TasksView.swift`

**Linia 608:**

```swift
// OBECNE:
.padding(.vertical, 12)

// NOWE:
.padding(.vertical, 6)
```

**Apple HIG reference:** iOS 17+ Lists mają ~44pt row height. Z 22px checkbox + 6pt top + 6pt bottom = 34pt min, co jest wciąż dobrym touch targetem (checkbox ma 44x44 frame).

---

## R2-10 — Checkbox: alternatywne ikony

### Propozycje

Zamiast zielonych checkmarków (`RoundedRectangle` + `checkmark`):

| # | Styl | Unchecked | Checked | Opis |
|---|------|-----------|---------|------|
| A | **SF Symbols circle** | `circle` | `checkmark.circle.fill` (.green) | Apple Reminders style |
| B | **Solid fill** | `square` (.secondary) | `checkmark.square.fill` (.blue) | Apple-native checkbox |
| C | **Minimal dot** | `circle` | `largecircle.fill.circle` (.primary) | Radio-button feel |
| D | **Soft check** | `circle` (.secondary) | `checkmark.circle.fill` (.teal) | Mniej agresywny kolor |
| E | **Strikethrough only** | brak ikony | strikethrough tekst | Ultra-minimalistyczne |

**Rekomendacja:** **Opcja A** (Reminders-style) lub **D** (teal zamiast green — mniej krzykliwy):

```swift
// Opcja A:
Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
    .font(.system(size: 22))
    .foregroundStyle(isCompleted ? .green : .secondary.opacity(0.4))

// Opcja D:
Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
    .font(.system(size: 22))
    .foregroundStyle(isCompleted ? .teal : .secondary.opacity(0.4))
```

**DECYZJA:** Opcja B — square checkbox, blue fill.

```swift
// NOWE (zastąpić cały Button(action: onToggle) w TaskRow.body):
Button(action: onToggle) {
    Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
        .font(.system(size: 22))
        .foregroundStyle(isCompleted ? .blue : .secondary.opacity(0.3))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
}
.buttonStyle(.plain)
```

Usunąć cały obecny `RoundedRectangle(cornerRadius: 4)` + overlay z `checkmark`.

---

## R2-11 — WIP zone: zielony border dla zadań 1-3 (NOWE)

### Problem
Pomarańczowy i czerwony indicator działają dobrze dla 4-5 i 6+, ale brakuje pozytywnego zielonego feedbacku dla „normalnej" strefy (1-3 taski).

### Zmiana

**Plik:** `FamilyTodo/Views/TasksView.swift`

**Linie 609-622** — zmienić overlay w TaskRow:

```swift
// OBECNE:
.overlay(alignment: .leading) {
    switch wipZone {
    case .normal:
        EmptyView()
    case .warning:
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.orange)
            .frame(width: 3)
    case .danger:
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.red)
            .frame(width: 3)
    }
}

// NOWE:
.overlay(alignment: .leading) {
    RoundedRectangle(cornerRadius: 2)
        .fill(wipZoneColor)
        .frame(width: 3)
}
```

Dodać computed property w TaskRow:

```swift
private var wipZoneColor: Color {
    switch wipZone {
    case .normal: .green
    case .warning: .orange
    case .danger: .red
    }
}
```

> **UWAGA:** `.normal` dotyczy TYLKO tasks w sekcji NEXT (pozycje 1-3). Tasks w BACKLOG i COMPLETED też przekazują `.normal` — ale te nie mają overlay bo używają tego samego WipZone. Trzeba dodać dodatkowy warunek: zielony indicator tylko gdy task.status == .next.

Alternatywnie: dodać nowy case `.safe` do WipZone enum:

```swift
enum WipZone {
    case safe     // pozycja 1-3 w NEXT (zielony)
    case normal   // backlog / completed (brak indicatora)
    case warning  // pozycja 4-5 (pomarańczowy)
    case danger   // pozycja 6+ (czerwony)
}
```

I w overlay:
```swift
.overlay(alignment: .leading) {
    switch wipZone {
    case .normal:
        EmptyView()
    case .safe:
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.green)
            .frame(width: 3)
    case .warning:
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.orange)
            .frame(width: 3)
    case .danger:
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.red)
            .frame(width: 3)
    }
}
```

W `wipZone(for:)` helper (L418):
```swift
private func wipZone(for index: Int) -> TaskRow.WipZone {
    index < TaskStore.recommendedWipLimit ? .safe : (index < 5 ? .warning : .danger)
}
```

---

## Kolejność wdrażania (po decyzjach)

1. **R2-9** (spacing) — 5 min
2. **R2-3** (More icon) — 5 min
3. **R2-5** (naming: „Task History") — 15 min
4. **R2-10** (square checkbox blue) — 15 min
5. **R2-11** (green WIP zone) — 10 min
6. **R2-1** (banner tap → Backlog) — 15 min
7. **R2-4** (archive swipe) — 30 min
8. **R2-8** (settings WIP stepper) — 45 min
9. **R2-6** (cleanup options) — 45 min

**Łączny effort: ~3h** (pomniejszony o R2-2 i R2-7)

---

## R2-BUG-1 — focusRuleBanner: hardcoded progi warning/danger (BUGFIX)

### Problem
W `TasksView.swift` w `focusRuleBanner` progi `case 4 ... 5` (orange) są hardcoded, nie dostosowują się do dynamicznego WIP limitu configurowalnego w Settings (R2-8).

Jeśli user zmieni limit na 5, to 5 tasków pokaże warning (pomarańczowy) zamiast green — bo `case 4...5` jest stałe.

### Obecny kod (do naprawienia)

**Plik:** `FamilyTodo/Views/TasksView.swift` — w `focusRuleBanner`

```swift
// ŹLE — hardcoded progi:
let state: (color: Color, icon: String, text: String) = switch count {
case 0:
    (.blue, "plus.circle", "Add tasks from Backlog to start")
case 1 ... recommendedWipLimit:
    (.blue, "target", "\(count) of \(recommendedWipLimit) recommended slots used")
case 4 ... 5:                    // ← BUG: hardcoded
    (.orange, "exclamationmark.circle", "\(count) active - consider finishing some first")
default:
    (.red, "exclamationmark.triangle", "\(count) active - too many tasks reduces focus")
}
```

### Poprawka

```swift
// DOBRZE — dynamiczne progi:
let state: (color: Color, icon: String, text: String) = switch count {
case 0:
    (.blue, "plus.circle", "Add tasks from Backlog to start")
case 1 ... recommendedWipLimit:
    (.blue, "target", "\(count) of \(recommendedWipLimit) recommended slots used")
case (recommendedWipLimit + 1) ... (recommendedWipLimit + 2):
    (.orange, "exclamationmark.circle", "\(count) active - consider finishing some first")
default:
    (.red, "exclamationmark.triangle", "\(count) active - too many tasks reduces focus")
}
```

> **Zmiana:** `case 4 ... 5` → `case (recommendedWipLimit + 1) ... (recommendedWipLimit + 2)`

---

## R2-BUG-2 — Tasks: spacing nadal za duży (BUGFIX)

### Problem
`.padding(.vertical, 6)` wciąż daje za duże odstępy. Checkbox już ma `frame(width: 44, height: 44)` — dodatkowy padding jest zbędny.

### Poprawka

**Plik:** `FamilyTodo/Views/TasksView.swift` — w `TaskRow.body`

```swift
// OBECNE:
.padding(.vertical, 6)

// NOWE:
.padding(.vertical, 2)
```

---

## R2-12 — WIP zone: redesign — checkbox kolor + subtelne tło (NOWE)

### Problem
Lewy pasek kolorowy (overlay `.leading`) jest zbyt utility/inżynierski. Chcemy bardziej elegancki sposób sygnalizacji WIP zone.

### Zmiana: usunąć lewy pasek, dodać 2 efekty

**Plik:** `FamilyTodo/Views/TasksView.swift` — w `TaskRow`

#### Krok 1 — Usunąć cały `.overlay(alignment: .leading)` block

Usunąć linie z overlay (obecne ~L657-675):

```swift
// USUNĄĆ CAŁOŚĆ:
.overlay(alignment: .leading) {
    switch wipZone {
    case .safe:
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.green)
            .frame(width: 3)
    case .normal:
        EmptyView()
    case .warning:
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.orange)
            .frame(width: 3)
    case .danger:
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.red)
            .frame(width: 3)
    }
}
```

#### Krok 2 — Checkbox kolor zależny od WIP zone

Zmienić foregroundStyle checkboxa (L604-606):

```swift
// OBECNE:
Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
    .font(.system(size: 22))
    .foregroundStyle(isCompleted ? .blue : .secondary.opacity(0.3))

// NOWE:
Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
    .font(.system(size: 22))
    .foregroundStyle(isCompleted ? .blue : uncheckedColor)
```

Dodać computed property:

```swift
private var uncheckedColor: Color {
    switch wipZone {
    case .safe:    .green.opacity(0.5)
    case .normal:  .secondary.opacity(0.3)
    case .warning: .orange
    case .danger:  .red
    }
}
```

#### Krok 3 — Subtelne tło wiersza

Dodać `.background` na HStack (po `.padding(.vertical, 2)`):

```swift
.padding(.vertical, 2)
.background {
    RoundedRectangle(cornerRadius: 8)
        .fill(rowBackgroundColor)
}
```

Dodać computed property:

```swift
private var rowBackgroundColor: Color {
    switch wipZone {
    case .safe:    .green.opacity(0.04)
    case .normal:  .clear
    case .warning: .orange.opacity(0.06)
    case .danger:  .red.opacity(0.08)
    }
}
```

> **Efekt:** Unchecked checkbox jest zielony/pomarańczowy/czerwony + wiersz ma delikatne kolorowe tło. Completed taski (`.normal`) nie mają żadnego tintowania. Bardzo subtelne, ale daje informację zwrotną.

---

## R2-13 — Tasks: wyświetlanie kategorii backloga jako tag (NOWE)

### Problem
W Tasks nie widać z jakiej kategorii Backlog pochodzi zadanie. User chce widzieć mały tag z nazwą kategorii obok tytułu taska.

### Analiza modelu danych

- `Task` ma pole `areaId: UUID?` — ale nie jest ono powiązane z `BacklogCategory`
- `BacklogItem` ma `categoryId: UUID` → `BacklogCategory`
- Przy promote (`promoteItemToTask` w `BacklogStore.swift:452`) `categoryId` jest **tracone** — nie jest przekazywane do nowego `Task`

### Zmiana 1 — Dodać `backlogCategoryId` do Task

**Plik:** `FamilyTodo/Models/Task.swift`

```swift
struct Task: Identifiable, Codable {
    // ... istniejące pola ...
    var backlogCategoryId: UUID?  // NOWE — link do BacklogCategory, z której pochodzi
    // ...
}
```

> ⚠️ **WAŻNE: SwiftData migration rule!** Pole MUSI być `Optional` (`UUID?`) — inaczej crash na istniejących danych (jak bug z `sortOrder`).

Dodać do `init`:
```swift
init(
    // ... istniejące parametry ...
    backlogCategoryId: UUID? = nil,
    // ...
) {
    // ...
    self.backlogCategoryId = backlogCategoryId
}
```

### Zmiana 2 — Dodać `backlogCategoryId` do CachedTask

**Plik:** `FamilyTodo/Models/CachedTask.swift`

```swift
var backlogCategoryId: UUID?   // NOWE — musi mieć domyślny nil
```

Zaktualizować `init(from:)` i `toTask()` żeby mapowały to pole.

### Zmiana 3 — Przekazać categoryId przy promote

**Plik:** `FamilyTodo/Stores/BacklogStore.swift` — w `promoteItemToTask`

Oraz **`FamilyTodo/Stores/TaskStore.swift`** — w `createTaskFromBacklogItem`:

```swift
// TaskStore.swift:
func createTaskFromBacklogItem(
    title: String,
    notes: String? = nil,
    preferredStatus: Task.TaskStatus = .next,
    assigneeId: UUID? = nil,
    taskType: Task.TaskType = .oneOff,
    recurringChoreId: UUID? = nil,
    taskId: UUID = UUID(),
    backlogCategoryId: UUID? = nil   // NOWE
) async -> NextTransitionValidation {
    await createTask(
        taskId: taskId,
        title: title,
        status: preferredStatus,
        assigneeId: assigneeId,
        assigneeIds: assigneeId.map { [$0] } ?? [],
        notes: notes,
        taskType: taskType,
        recurringChoreId: recurringChoreId,
        backlogCategoryId: backlogCategoryId  // NOWE
    )
}
```

```swift
// BacklogStore.swift w promoteItemToTask:
let validation = await taskStore.createTaskFromBacklogItem(
    title: item.title,
    notes: item.notes,
    preferredStatus: preferredStatus,
    assigneeId: resolvedAssigneeId,
    taskId: createdTaskId,
    backlogCategoryId: item.categoryId   // NOWE
)
```

### Zmiana 4 — Wyświetlić tag kategorii w TaskRow

**Plik:** `FamilyTodo/Views/TasksView.swift` — w `TaskRow`

Dodać `categoryName: String?` jako nowy parametr:

```swift
struct TaskRow: View {
    let task: Task
    let assigneeName: String?
    let categoryName: String?    // NOWE
    let wipZone: WipZone
    // ...
}
```

W `body`, w `HStack(spacing: 8)` pod tytułem (obok Recurring, Due Date, Assignee):

```swift
if let categoryName {
    Text(categoryName)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.blue.opacity(0.12)))
}
```

### Zmiana 5 — Przekazać categoryName w TasksContent

W pętli `ForEach(store.nextTasks)` i `ForEach(store.recentlyDoneTasks)` trzeba resolve `categoryName` z `backlogCategoryId`:

```swift
TaskRow(
    task: task,
    assigneeName: assigneeName(for: task),
    categoryName: categoryName(for: task),  // NOWE
    wipZone: wipZone(for: index),
    // ...
)
```

Helper function:

```swift
private func categoryName(for task: Task) -> String? {
    guard let categoryId = task.backlogCategoryId else { return nil }
    // Potrzebny dostęp do BacklogStore lub lokalny cache kategorii
    return backlogStore.categories.first(where: { $0.id == categoryId })?.title
}
```

> **UWAGA:** To wymaga dostępu do `BacklogStore` z `TasksContent`. Sprawdzić czy jest dostępny przez `@EnvironmentObject` lub trzeba go dodać.

---

## R2-14 — Tasks: status Backlog w detail sheet → powrót do Backlog (BUG)

### Problem
Gdy w TaskDetailSheet zmienisz status na "Backlog" i klikniesz Save, task zmienia `status = .backlog` — ale zostaje obiektem `Task` (nie `BacklogItem`). Pojawia się sekcja "BACKLOG" w Tasks zamiast powrotu do Backlog tabu.

### Root cause
`save()` w `TaskDetailSheet` (L816-828) po prostu ustawia `updatedTask.status = .backlog` i woła `onSave`. `TaskStore.updateTask` persystuje to jako Task ze statusem `.backlog` → `store.backlogTasks` go wyświetla w Tasks.

Ale Task to NIE jest BacklogItem — nie ma `categoryId` i nie jest widoczny w Backlog tabie.

### DECYZJA: pełna democja — Task → BacklogItem

Kiedy user zmienia status na "Backlog" w detail sheet, task musi:
1. Zostać usunięty jako `Task`
2. Zostać odtworzony jako `BacklogItem` w jego oryginalnej kategorii (`backlogCategoryId`)

### Architektura: callback pattern

`TaskDetailSheet` NIE ma dostępu do `BacklogStore`. Zamiast przekazywać store, użyjemy callbacku `onDemoteToBacklog`, a `TasksContent` obsłuży logikę.

### Zmiana 1 — Dodać callback do TaskDetailSheet

**Plik:** `FamilyTodo/Views/TasksView.swift` — `TaskDetailSheet`

```swift
private struct TaskDetailSheet: View {
    let task: Task
    let members: [Member]
    let onSave: (Task) -> Void
    let onDelete: (Task) -> Void
    let onDemoteToBacklog: (Task) -> Void   // NOWE

    // ... (init z nowym parametrem)
```

### Zmiana 2 — W `save()` wykryć demot

```swift
private func save() {
    var updatedTask = task
    updatedTask.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    updatedTask.status = status
    updatedTask.assigneeId = assigneeId
    updatedTask.assigneeIds = assigneeId.map { [$0] } ?? []
    updatedTask.dueDate = hasDueDate ? dueDate : nil
    let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    updatedTask.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

    if status == .backlog {
        // Demot: NIE wołamy onSave, wołamy onDemoteToBacklog
        onDemoteToBacklog(updatedTask)
    } else {
        onSave(updatedTask)
    }
    dismiss()
}
```

### Zmiana 3 — Dodać `addItem` z notes do BacklogStore

**Plik:** `FamilyTodo/Stores/BacklogStore.swift`

Obecny `addItem(to:title:assigneeId:)` nie przyjmuje `notes`. Dodać parametr:

```swift
func addItem(to categoryId: UUID, title: String, assigneeId: UUID? = nil, notes: String? = nil) async {
    guard let householdId else { return }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }

    let item = BacklogItem(
        categoryId: categoryId,
        householdId: householdId,
        title: trimmedTitle,
        assigneeId: assigneeId,
        notes: notes   // NOWE
    )
    // ... reszta bez zmian
}
```

### Zmiana 4 — Obsłużyć demot w TasksContent

**Plik:** `FamilyTodo/Views/TasksView.swift` — `TasksContent`

Potrzebny dostęp do BacklogStore. Dodać:

```swift
@EnvironmentObject private var backlogStore: BacklogStore
```

> ⚠️ **UWAGA:** Sprawdzić czy `BacklogStore` jest propagowany jako `@EnvironmentObject` z `ContentView`. Jeśli nie — trzeba go dodać w `ContentView`.

Dodać handler:

```swift
private func demoteTaskToBacklog(_ task: Task) {
    _ = _Concurrency.Task {
        // 1. Ustalić categoryId — użyć backlogCategoryId lub pierwszej kategorii jako fallback
        let categoryId: UUID
        if let backlogCatId = task.backlogCategoryId,
           backlogStore.categories.contains(where: { $0.id == backlogCatId }) {
            categoryId = backlogCatId
        } else if let firstCategory = backlogStore.categories.first {
            categoryId = firstCategory.id
        } else {
            // Brak kategorii — nie można demotować
            return
        }

        // 2. Dodać jako BacklogItem
        await backlogStore.addItem(
            to: categoryId,
            title: task.title,
            assigneeId: task.assigneeId,
            notes: task.notes
        )

        // 3. Usunąć Task
        await store.deleteTask(task)
    }
}
```

### Zmiana 5 — Przekazać callback do TaskDetailSheet

W TasksContent, tam gdzie tworzy `TaskDetailSheet`:

```swift
TaskDetailSheet(
    task: selectedTask,
    members: members,
    onSave: { updatedTask in
        // ... istniejący kod save
    },
    onDelete: { task in
        // ... istniejący kod delete
    },
    onDemoteToBacklog: { task in
        demoteTaskToBacklog(task)   // NOWE
    }
)
```

### Zmiana 6 — Sprawdzić propagację BacklogStore

**Plik:** `FamilyTodo/ContentView.swift`

Sprawdzić czy `BacklogStore` jest dostępny jako `@EnvironmentObject` w drzewie widoków zawierającym `TasksView`. Jeśli nie, dodać `.environmentObject(backlogStore)`.

> **Efekt:** User wybiera "Backlog" w Picker → task znika z Tasks → pojawia się w Backlog w oryginalnej kategorii (lub pierwszej kategorii jako fallback). Notatki i assignee są zachowane.

---

# UX Round 3 — Tasks View Redesign (2026-02-16 15:56)

> **Skills:** `swiftui-liquid-glass`, `swift-expert`, `swiftui-ui-patterns`

## Spis zmian R3

| # | Issue | Pliki | Effort |
|---|-------|-------|--------|
| R3-1 | Focus Rule banner z opisem i dynamiczną liczbą | `TasksView.swift` | 15 min |
| R3-2 | Kolory kategorii Backlog (deterministyczne z ID hash) | `BacklogCategory+Color.swift` [NEW], `BacklogView.swift` | 30 min |
| R3-3 | Task tag (kategoria + owner) pod tytułem w kolorze | `TasksView.swift` | 20 min |
| R3-4 | Tasks globalne per household (brak filtrowania po user) | WERYFIKACJA — prawdopodobnie już OK | 5 min |
| R3-5 | Active/Completed toggle z Liquid Glass + przeniesienie z More | `TasksView.swift`, `MoreView.swift` | 60 min |

---

## R3-1 — Focus Rule: banner z opisem i odliczaniem

### Zmiana

**Plik:** `FamilyTodo/Views/TasksView.swift` — `focusRuleBanner`

Obecny banner to jednoliniowy HStack z ikoną i tekstem. Zmienić na:

```swift
@ViewBuilder
private var focusRuleBanner: some View {
    let count = store.nextTasks.count
    let limit = normalizedWipLimit

    VStack(alignment: .leading, spacing: 4) {
        Text("Focus Rule: Max \(limit) active tasks per person to ensure quality and completion.")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)

        HStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 14))
                .foregroundStyle(bannerColor(count: count, limit: limit))

            Text("\(count) of \(limit) slots used")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(bannerColor(count: count, limit: limit))

            Spacer()

            if count == 0 {
                Button("Go to Backlog") {
                    selectedTab = .backlog
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
            }
        }
    }
    .padding(12)
    .background {
        RoundedRectangle(cornerRadius: 12)
            .fill(bannerColor(count: count, limit: limit).opacity(0.08))
    }
}

private func bannerColor(count: Int, limit: Int) -> Color {
    switch count {
    case 0: .blue
    case 1...limit: .blue
    case (limit + 1)...(limit + 2): .orange
    default: .red
    }
}
```

Zmiana ikony: `target` → `chart.bar.fill` (bardziej pasuje do „slots used").

> **Zależność:** Musi uwzględniać `normalizedWipLimit` (dynamiczny z Settings).

---

## R3-2 — Kolory kategorii Backlog

### Problem
Kategorie w Backlog nie mają koloru. Chcemy radosne, eleganckie kolory — deterministycznie przypisane na podstawie `category.id` (żeby kolor był stabilny).

### Zmiana 1 — Nowy plik z extension

**Plik:** `FamilyTodo/Extensions/BacklogCategory+Color.swift` [NEW]

```swift
import SwiftUI

extension BacklogCategory {
    /// Palette of cheerful, elegant colors for category tags.
    static let categoryPalette: [Color] = [
        .purple,
        .orange,
        .teal,
        .pink,
        .indigo,
        .mint,
        .brown,
        .cyan,
        Color(red: 0.95, green: 0.4, blue: 0.3),  // coral
        Color(red: 0.3, green: 0.7, blue: 0.4),    // emerald
    ]

    /// Deterministic color based on category ID hash.
    var color: Color {
        let hash = abs(id.hashValue)
        return Self.categoryPalette[hash % Self.categoryPalette.count]
    }
}
```

### Zmiana 2 — Kolorowa kropka w BacklogView

**Plik:** `FamilyTodo/Views/BacklogView.swift` — w `CategoryCard` header

Dodać kolorową kropkę obok nazwy kategorii. Szukać obecnego header w `CategoryCard` i przed `Text(category.title)` dodać:

```swift
Circle()
    .fill(category.color)
    .frame(width: 10, height: 10)
```

> **UWAGA:** `CategoryCard` to prawdopodobnie subview w `BacklogView.swift`. Znaleźć dokładne linie i dodać kropkę.

---

## R3-3 — Task tag (kategoria + owner) pod tytułem w kolorze

### Zmiana

**Plik:** `FamilyTodo/Views/TasksView.swift` — `TaskRow`

Obecny `HStack(spacing: 8)` pod tytułem zawiera Recurring badge, Due Date, Assignee. Zmienić na nowy layout z tagami w kolorze kategorii.

#### Nowe parametry TaskRow:

```swift
struct TaskRow: View {
    let task: Task
    let assigneeName: String?
    let categoryName: String?
    let categoryColor: Color?     // NOWE — kolor kategorii
    let wipZone: WipZone
    let onToggle: () -> Void
    let onOpenDetail: () -> Void
```

#### Pod tytułem — tagi w nowym stylu:

```swift
HStack(spacing: 6) {
    // Category tag
    if let categoryName, let categoryColor {
        HStack(spacing: 4) {
            Circle()
                .fill(categoryColor)
                .frame(width: 6, height: 6)
            Text(categoryName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(categoryColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(categoryColor.opacity(0.12)))
    }

    // Owner tag
    if let assigneeName {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.system(size: 8))
                .foregroundStyle(categoryColor ?? .secondary)
            Text(assigneeName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(categoryColor ?? .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill((categoryColor ?? .secondary).opacity(0.12)))
    }

    // Due date (zachować istniejący)
    if let dueDate = task.dueDate {
        dueDateLabel(dueDate)
    }

    // Recurring badge (zachować istniejący)
    if task.taskType == .recurring {
        Label("Recurring", systemImage: "repeat")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.purple.opacity(0.12)))
    }
}
```

#### Przekazać categoryColor w ForEach:

```swift
TaskRow(
    task: task,
    assigneeName: assigneeName(for: task),
    categoryName: categoryName(for: task),
    categoryColor: categoryColor(for: task),  // NOWE
    wipZone: wipZone(for: index),
    onToggle: { toggleTask(task) },
    onOpenDetail: { selectedTask = task }
)
```

Helper:

```swift
private func categoryColor(for task: Task) -> Color? {
    guard let categoryId = task.backlogCategoryId else { return nil }
    return backlogStore.categories.first(where: { $0.id == categoryId })?.color
}
```

> **Zależność:** wymaga R2-13 (backlogCategoryId na Task) i R3-2 (BacklogCategory.color).

---

## R3-4 — Tasks globalne per household

### Weryfikacja

`TaskStore.nextTasks` filtruje `tasks.filter { $0.status == .next }` — **nie filtruje** po `assigneeId` ani po current user. Wszystkie taski w household są widoczne.

→ **Prawdopodobnie już działa poprawnie.** Zweryfikować po wdrożeniu R3-3 czy assignee taguje się poprawnie i czy widać zadania innych osób.

---

## R3-5 — Active/Completed toggle z Liquid Glass

### Problem
Completed Tasks jest w More → Task History. Chcemy przenieść do Tasks jako toggle „Active | Completed" z efektem Liquid Glass na iOS 26+.

### Zmiana 1 — Stan toggle

**Plik:** `FamilyTodo/Views/TasksView.swift` — `TasksContent`

```swift
private enum TasksFilter: String, CaseIterable {
    case active = "Active"
    case completed = "Completed"
}

@State private var activeFilter: TasksFilter = .active
@Namespace private var glassNamespace   // dla morphing
```

### Zmiana 2 — Toggle UI z Liquid Glass

Pod headerem, nad focusRuleBanner:

```swift
@ViewBuilder
private var filterToggle: some View {
    if #available(iOS 26, *) {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(TasksFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.snappy(duration: 0.3)) {
                            activeFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(activeFilter == filter ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        activeFilter == filter
                            ? .regular.interactive()
                            : .regular.tint(.clear),
                        in: .capsule
                    )
                    .glassEffectID(filter.rawValue, in: glassNamespace)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(Color(.systemGray6))
        }
    } else {
        // Fallback pre-iOS 26: standard Picker
        Picker("Filter", selection: $activeFilter) {
            ForEach(TasksFilter.allCases, id: \.self) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }
}
```

### Zmiana 3 — Warunkowe wyświetlanie treści

W `body` ScrollView:

```swift
ScrollView {
    LazyVStack(spacing: 0) {
        if activeFilter == .active {
            // NEXT section (obecna)
            // BACKLOG section (obecna — ale rozważyć usunięcie)
            // COMPLETED RECENTLY section (taski <24h)
        } else {
            // COMPLETED section — wyświetlić WSZYSTKIE doneTasks
            // (nie tylko recentlyDone, ale WSZYSTKIE — przenieść z More)
            ForEach(store.doneTasks) { task in
                TaskRow(
                    task: task,
                    assigneeName: assigneeName(for: task),
                    categoryName: categoryName(for: task),
                    categoryColor: categoryColor(for: task),
                    wipZone: .normal,
                    onToggle: { toggleTask(task) },
                    onOpenDetail: { selectedTask = task }
                )
                // swipe to archive, context menu etc.
            }

            if store.doneTasks.isEmpty {
                ContentUnavailableView {
                    Label("No Completed Tasks", systemImage: "checkmark.circle")
                } description: {
                    Text("Complete some tasks to see them here.")
                }
            }
        }
    }
}
```

### Zmiana 4 — Focus Rule banner tylko w Active

```swift
if activeFilter == .active {
    focusRuleBanner
        .padding(.horizontal, 20)
        .padding(.bottom, activeBanner == nil ? 16 : 8)
}
```

### Zmiana 5 — Usunąć Completed Tasks z More

**Plik:** `FamilyTodo/Views/MoreView.swift`

Usunąć NavigationLink do `CompletedTasksView`:

```swift
// USUNĄĆ:
NavigationLink {
    CompletedTasksView()
} label: {
    MoreRow(icon: "checkmark.circle", title: "Task History")
}
.buttonStyle(.plain)
.accessibilityIdentifier("CompletedTasks")
```

> **UWAGA:** `CompletedTasksView` i `CompletedTasksContent` w `MoreView.swift` mogą zostać usunięte albo zachowane jako dead code do przyszłego użytku. Rekomendacja: zachować ale zakomentować.

### Zmiana 6 — Uwzględnić cleanup (R2-6) w Tasks

Toolbar z opcjami cleanup (Clear All, Keep 7/30 days) przenieść do Tasks view (dostępny tylko w trybie "Completed").

---

## Kolejność wdrażania R3

1. **R3-2** (kategorie kolory) — 30 min — brak zależności
2. **R3-1** (Focus Rule banner) — 15 min — brak zależności
3. **R3-4** (weryfikacja) — 5 min — sprawdzić
4. **R3-3** (task tags) — 20 min — zależy od R2-13 + R3-2
5. **R3-5** (Active/Completed toggle + Glass) — 60 min — największy refactor

**Łączny effort: ~2.5h**
