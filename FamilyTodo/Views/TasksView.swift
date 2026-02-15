import SwiftData
import SwiftUI
import UIKit

/// Tasks screen - daily chores and immediate to-dos
struct TasksView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                TasksContent(householdId: householdId, modelContext: modelContext)
            } else {
                GuidedEmptyStateView()
            }
        }
    }
}

private struct TasksContent: View {
    @StateObject private var store: TaskStore
    @StateObject private var memberStore: MemberStore

    @State private var newTaskTitle = ""
    @State private var taskBeingCompleted: UUID?
    @State private var showAllCompleteAnimation = false
    @State private var showAddSheet = false
    @State private var selectedTask: Task?
    @FocusState private var isInputFocused: Bool

    @EnvironmentObject private var userSession: UserSession
    @Environment(\.appTabBarHeight) private var tabBarHeight
    @Environment(\.appKeyboardVisible) private var isKeyboardVisible

    init(householdId: UUID, modelContext: ModelContext) {
        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(householdId)
        _store = StateObject(wrappedValue: taskStore)
        _memberStore = StateObject(wrappedValue: MemberStore(householdId: householdId, modelContext: modelContext))
    }

    var body: some View {
        GeometryReader { _ in
            let listBottomInset = isKeyboardVisible
                ? CGFloat(16)
                : AppChromeMetrics.contentBottomInset(tabBarHeight: tabBarHeight)
            let floatingButtonInset = AppChromeMetrics.floatingButtonBottomInset(
                tabBarHeight: tabBarHeight
            )

            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    focusRuleBanner
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if !store.nextTasks.isEmpty {
                                sectionHeader("NEXT")

                                ForEach(store.nextTasks) { task in
                                    if taskBeingCompleted != task.id {
                                        TaskRow(
                                            task: task,
                                            assigneeName: assigneeName(for: task),
                                            onToggle: { toggleTask(task) },
                                            onOpenDetail: { selectedTask = task }
                                        )
                                        .rowInsertAnimation()
                                        .accessibilityIdentifier("taskRow_\(task.title)")
                                    }
                                }
                            }

                            if !store.backlogTasks.isEmpty {
                                sectionHeader("BACKLOG")

                                ForEach(store.backlogTasks) { task in
                                    TaskRow(
                                        task: task,
                                        assigneeName: assigneeName(for: task),
                                        onToggle: { toggleTask(task) },
                                        onOpenDetail: { selectedTask = task }
                                    )
                                    .rowInsertAnimation()
                                    .accessibilityIdentifier("taskRowBacklog_\(task.title)")
                                }
                            }

                            if !store.doneTasks.isEmpty {
                                sectionHeader("COMPLETED")

                                ForEach(store.doneTasks) { task in
                                    TaskRow(
                                        task: task,
                                        assigneeName: assigneeName(for: task),
                                        onToggle: { toggleTask(task) },
                                        onOpenDetail: { selectedTask = task }
                                    )
                                    .rowInsertAnimation()
                                    .accessibilityIdentifier("taskRowCompleted_\(task.title)")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, listBottomInset)
                    .refreshable {
                        store.setSyncMode(userSession.syncMode)
                        memberStore.setSyncMode(userSession.syncMode)
                        await store.loadTasks()
                        await memberStore.loadMembers()
                    }
                }

                if !isKeyboardVisible {
                    addPillButton
                        .padding(.trailing, AppChromeMetrics.horizontalInset)
                        .padding(.bottom, floatingButtonInset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            store.setSyncMode(userSession.syncMode)
            memberStore.setSyncMode(userSession.syncMode)
            await store.loadTasks()
            await memberStore.loadMembers()
        }
        .sheet(isPresented: $showAddSheet) {
            addTaskSheet
                .presentationDetents([.height(180)])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(
                task: task,
                members: memberStore.members,
                onSave: { updatedTask in
                    _ = _Concurrency.Task {
                        await store.updateTask(updatedTask)
                    }
                },
                onDelete: { taskToDelete in
                    _ = _Concurrency.Task {
                        await store.deleteTask(taskToDelete)
                    }
                }
            )
        }
        .onChange(of: store.error as? TaskStoreError) { _, error in
            if let error {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                print("Task Error: \(error.localizedDescription)")
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Tasks")
                .font(.system(size: 28, weight: .bold))

            if store.nextTasks.isEmpty, !store.doneTasks.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                    .scaleEffect(showAllCompleteAnimation ? 1.2 : 1.0)
                    .animation(WowAnimation.spring, value: showAllCompleteAnimation)
            }

            Spacer()
        }
    }

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

    private var addPillButton: some View {
        Button {
            HapticManager.lightTap()
            showAddSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Add task")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppChromeMetrics.compactCTAHorizontalPadding)
            .frame(height: AppChromeMetrics.compactCTAHeight)
            .background {
                Capsule()
                    .fill(.green)
                    .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("taskAddButton")
    }

    private var addTaskSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)

                    TextField("What needs to be done?", text: $newTaskTitle)
                        .font(.system(size: 17))
                        .focused($isInputFocused)
                        .accessibilityIdentifier("taskInputField")
                        .submitLabel(.done)
                        .onSubmit {
                            addTask()
                        }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        newTaskTitle = ""
                        showAddSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        addTask()
                    }
                    .fontWeight(.semibold)
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                isInputFocused = true
            }
        }
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        if !store.canMoveToNext(assigneeId: nil) {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            return
        }

        _ = _Concurrency.Task {
            await store.createTask(title: title, status: .next)
        }

        newTaskTitle = ""
        showAddSheet = false
        HapticManager.lightTap()
    }

    private func toggleTask(_ task: Task) {
        let newStatus: Task.TaskStatus = task.status == .done ? .next : .done

        if newStatus == .next, !store.canMoveToNext(assigneeId: task.assigneeId, excludingTaskId: task.id) {
            HapticManager.warning()
            return
        }

        let willCompleteAll = newStatus == .done && store.nextTasks.count == 1

        if newStatus == .done {
            HapticManager.lightTap()
            withAnimation(WowAnimation.easeOut) {
                taskBeingCompleted = task.id
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                _ = _Concurrency.Task {
                    await store.moveTask(task, to: newStatus)
                    taskBeingCompleted = nil

                    if willCompleteAll {
                        HapticManager.success()
                        showAllCompleteAnimation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showAllCompleteAnimation = false
                        }
                    } else {
                        HapticManager.mediumTap()
                    }
                }
            }
        } else {
            _ = _Concurrency.Task {
                await store.moveTask(task, to: newStatus)
            }
            HapticManager.lightTap()
        }
    }

    private func assigneeName(for task: Task) -> String? {
        guard let assigneeId = task.assigneeId else { return nil }
        return memberStore.members.first(where: { $0.id == assigneeId })?.displayName
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TaskRow: View {
    let task: Task
    let assigneeName: String?
    let onToggle: () -> Void
    let onOpenDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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
            }
            .buttonStyle(.plain)

            Button(action: onOpenDetail) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 15))
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .strikethrough(isCompleted)

                    HStack(spacing: 8) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
    }

    private var isCompleted: Bool {
        task.status == .done
    }

    @ViewBuilder
    private func dueDateLabel(_ date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let isOverdue = task.isOverdue

        Text(dateFormatter.string(from: date))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isOverdue ? .red : (isToday ? .orange : .secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill((isOverdue ? Color.red : Color.orange).opacity(0.12)))
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }
}

private struct TaskDetailSheet: View {
    let task: Task
    let members: [Member]
    let onSave: (Task) -> Void
    let onDelete: (Task) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var status: Task.TaskStatus
    @State private var assigneeId: UUID?
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var notes: String

    init(
        task: Task,
        members: [Member],
        onSave: @escaping (Task) -> Void,
        onDelete: @escaping (Task) -> Void
    ) {
        self.task = task
        self.members = members
        self.onSave = onSave
        self.onDelete = onDelete

        _title = State(initialValue: task.title)
        _status = State(initialValue: task.status)
        _assigneeId = State(initialValue: task.assigneeId)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _dueDate = State(initialValue: task.dueDate ?? Date())
        _notes = State(initialValue: task.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    Picker("Status", selection: $status) {
                        Text("Backlog").tag(Task.TaskStatus.backlog)
                        Text("Next").tag(Task.TaskStatus.next)
                        Text("Done").tag(Task.TaskStatus.done)
                    }
                }

                Section("Assignee") {
                    Picker("Who", selection: $assigneeId) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.displayName).tag(Optional(member.id))
                        }
                    }
                }

                Section("Due Date") {
                    Toggle("Set due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker(
                            "Due",
                            selection: $dueDate,
                            displayedComponents: [.date]
                        )
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                Section {
                    Button("Delete Task", role: .destructive) {
                        onDelete(task)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        var updatedTask = task
        updatedTask.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedTask.status = status
        updatedTask.assigneeId = assigneeId
        updatedTask.assigneeIds = assigneeId.map { [$0] } ?? []
        updatedTask.dueDate = hasDueDate ? dueDate : nil
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedTask.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        onSave(updatedTask)
        dismiss()
    }
}

#Preview {
    TasksView()
        .environmentObject(UserSession.shared)
}
