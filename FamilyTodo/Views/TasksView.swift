import SwiftData
import SwiftUI
import UIKit

/// Tasks screen - execution board for tasks promoted from Backlog
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
    private enum InlineBanner: Equatable {
        case assigneeRequired
        case wipLimitReached(current: Int, limit: Int)

        var text: String {
            switch self {
            case .assigneeRequired:
                "Assign this task before moving it to Next."
            case let .wipLimitReached(current, limit):
                "WIP limit reached (\(current)/\(limit)). Complete one active task first."
            }
        }
    }

    @StateObject private var store: TaskStore
    @StateObject private var memberStore: MemberStore

    @State private var taskBeingCompleted: UUID?
    @State private var showAllCompleteAnimation = false
    @State private var selectedTask: Task?
    @State private var pendingNextTask: Task?
    @State private var selectedAssigneeIdForNext: UUID?
    @State private var activeBanner: InlineBanner?

    @EnvironmentObject private var userSession: UserSession

    init(householdId: UUID, modelContext: ModelContext) {
        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(householdId)
        _store = StateObject(wrappedValue: taskStore)
        _memberStore = StateObject(wrappedValue: MemberStore(householdId: householdId, modelContext: modelContext))
    }

    var body: some View {
        let listBottomInset: CGFloat = 16

        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            focusRuleBanner
                .padding(.horizontal, 20)
                .padding(.bottom, activeBanner == nil ? 16 : 8)

            if let activeBanner {
                InlineStatusBanner(text: activeBanner.text)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

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
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    startTaskFromBacklog(task)
                                } label: {
                                    Label("Start", systemImage: "play.fill")
                                }
                                .tint(.blue)
                            }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            store.setSyncMode(userSession.syncMode)
            memberStore.setSyncMode(userSession.syncMode)
            await store.loadTasks()
            await memberStore.loadMembers()
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(
                task: task,
                members: memberStore.members,
                onSave: { updatedTask in
                    _ = _Concurrency.Task {
                        let validation = await store.updateTask(updatedTask)
                        handleNextTransitionValidation(validation)
                    }
                },
                onDelete: { taskToDelete in
                    _ = _Concurrency.Task {
                        await store.deleteTask(taskToDelete)
                    }
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { pendingNextTask != nil },
            set: { isPresented in
                if !isPresented {
                    pendingNextTask = nil
                    selectedAssigneeIdForNext = nil
                }
            }
        )) {
            if let pendingNextTask {
                AssigneePickerSheet(
                    title: "Assign and start",
                    members: activeMembers,
                    selectedAssigneeId: $selectedAssigneeIdForNext,
                    onCancel: {
                        self.pendingNextTask = nil
                        selectedAssigneeIdForNext = nil
                    },
                    onConfirm: {
                        guard let assigneeId = selectedAssigneeIdForNext else { return }
                        self.pendingNextTask = nil
                        selectedAssigneeIdForNext = nil
                        moveTaskToNext(pendingNextTask, assigneeId: assigneeId)
                    }
                )
            }
        }
        .onChange(of: store.error as? TaskStoreError) { _, error in
            guard let error else { return }
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            print("Task Error: \(error.localizedDescription)")
        }
    }

    private var activeMembers: [Member] {
        memberStore.members
            .filter(\.isActive)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var currentMember: Member? {
        guard let userId = userSession.userId else { return nil }
        return activeMembers.first { $0.userId == userId }
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

    private func startTaskFromBacklog(_ task: Task) {
        let members = activeMembers
        guard !members.isEmpty else {
            showBanner(.assigneeRequired)
            return
        }

        if members.count == 1, let assigneeId = members.first?.id {
            moveTaskToNext(task, assigneeId: assigneeId)
            return
        }

        pendingNextTask = task
        selectedAssigneeIdForNext = currentMember?.id
    }

    private func moveTaskToNext(_ task: Task, assigneeId: UUID) {
        var updatedTask = task
        updatedTask.status = .next
        updatedTask.assigneeId = assigneeId
        updatedTask.assigneeIds = [assigneeId]

        _ = _Concurrency.Task {
            let validation = await store.updateTask(updatedTask)
            handleNextTransitionValidation(validation)
            if validation == .ok {
                HapticManager.lightTap()
            }
        }
    }

    private func toggleTask(_ task: Task) {
        let newStatus: Task.TaskStatus = task.status == .done ? .next : .done

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

        let willCompleteAll = newStatus == .done && store.nextTasks.count == 1

        if newStatus == .done {
            HapticManager.lightTap()
            withAnimation(WowAnimation.easeOut) {
                taskBeingCompleted = task.id
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                _ = _Concurrency.Task {
                    let validation = await store.moveTask(task, to: newStatus)
                    taskBeingCompleted = nil
                    handleNextTransitionValidation(validation)

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
                let validation = await store.moveTask(task, to: newStatus)
                handleNextTransitionValidation(validation)
                if validation == .ok {
                    HapticManager.lightTap()
                }
            }
        }
    }

    private func handleNextTransitionValidation(_ validation: TaskStore.NextTransitionValidation) {
        switch validation {
        case .ok:
            activeBanner = nil
        case .assigneeRequired:
            showBanner(.assigneeRequired)
        case let .wipLimitReached(current, limit):
            showBanner(.wipLimitReached(current: current, limit: limit))
        }
    }

    private func showBanner(_ banner: InlineBanner) {
        withAnimation(WowAnimation.spring) {
            activeBanner = banner
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            if activeBanner == banner {
                withAnimation(WowAnimation.easeOut) {
                    activeBanner = nil
                }
            }
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

private struct InlineStatusBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.orange.opacity(0.12))
        }
    }
}

private struct AssigneePickerSheet: View {
    let title: String
    let members: [Member]
    @Binding var selectedAssigneeId: UUID?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List(members) { member in
                Button {
                    selectedAssigneeId = member.id
                } label: {
                    HStack {
                        Text(member.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedAssigneeId == member.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start") {
                        onConfirm()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedAssigneeId == nil)
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationBackground(.ultraThinMaterial)
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
                        ForEach(members.filter(\.isActive)) { member in
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
