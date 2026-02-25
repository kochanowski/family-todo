import SwiftData
import SwiftUI
import UIKit

// swiftlint:disable file_length
/// Tasks screen - execution board for tasks promoted from Backlog
struct TasksView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext
    @Binding private var selectedTab: AppTab

    init(selectedTab: Binding<AppTab>) {
        _selectedTab = selectedTab
    }

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                TasksContent(
                    householdId: householdId,
                    modelContext: modelContext,
                    selectedTab: $selectedTab
                )
            } else {
                GuidedEmptyStateView()
            }
        }
    }
}

// swiftlint:disable type_body_length
private struct TasksContent: View {
    private enum InlineBanner: Equatable {
        case assigneeRequired
        case wipLimitReached(current: Int, limit: Int)

        var text: String {
            switch self {
            case .assigneeRequired:
                "Assign this task before moving it to Next."
            case .wipLimitReached(let current, let limit):
                "WIP limit reached (\(current)/\(limit)). Complete one active task first."
            }
        }
    }

    private enum TasksFilter: String, CaseIterable {
        case active = "Active"
        case completed = "Completed"
    }

    private enum CompletedCleanupAction: String, Identifiable {
        case clearAll
        case keepLast7Days
        case keepLast30Days

        var id: String {
            rawValue
        }
    }

    @StateObject private var store: TaskStore
    @StateObject private var memberStore: MemberStore
    @StateObject private var backlogStore: BacklogStore

    @State private var taskBeingCompleted: UUID?
    @State private var selectedTask: Task?
    @State private var pendingNextTask: Task?
    @State private var selectedAssigneeIdForNext: UUID?
    @State private var activeBanner: InlineBanner?
    @State private var activeFilter: TasksFilter = .active
    @State private var pendingCleanupAction: CompletedCleanupAction?
    @State private var pendingDeletedTask: Task?
    @State private var pendingDeleteWork: _Concurrency.Task<Void, Never>?
    @State private var hiddenPendingDeleteIds: Set<UUID> = []
    @State private var hiddenMovedToIdeasIds: Set<UUID> = []
    @AppStorage("recommendedWipLimit") private var recommendedWipLimit = TaskStore
        .defaultRecommendedWipLimit
    @Binding private var selectedTab: AppTab
    @Namespace private var tasksFilterGlassNamespace

    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var celebrationManager: CelebrationManager

    init(householdId: UUID, modelContext: ModelContext, selectedTab: Binding<AppTab>) {
        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(householdId)
        _store = StateObject(wrappedValue: taskStore)
        _memberStore = StateObject(
            wrappedValue: MemberStore(householdId: householdId, modelContext: modelContext))
        _backlogStore = StateObject(
            wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext))
        _selectedTab = selectedTab
    }

    var body: some View {
        let listBottomInset: CGFloat = 16

        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                .padding(.top, AppChromeMetrics.screenHeaderTopPadding)
                .padding(.bottom, AppChromeMetrics.screenHeaderBottomPadding)

            filterToggle
                .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                .padding(.bottom, 12)

            if activeFilter == .active {
                if let activeBanner {
                    InlineStatusBanner(text: activeBanner.text)
                        .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                activeTasksHeader
                    .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                    .padding(.bottom, 8)
            }

            List {
                if activeFilter == .active {
                    activeTasksContent
                } else {
                    completedTasksContent
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .animation(.easeInOut(duration: 0.22), value: visibleNextTasks.map(\.id))
            .padding(.bottom, listBottomInset)
            .refreshable {
                store.setSyncMode(userSession.syncMode)
                memberStore.setSyncMode(userSession.syncMode)
                backlogStore.setSyncMode(userSession.syncMode)
                await store.loadTasks()
                await memberStore.loadMembers()
                await backlogStore.loadData()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            store.setSyncMode(userSession.syncMode)
            memberStore.setSyncMode(userSession.syncMode)
            backlogStore.setSyncMode(userSession.syncMode)
            await store.loadTasks()
            await memberStore.loadMembers()
            await backlogStore.loadData()
        }
        .sheet(item: $pendingCleanupAction) { action in
            AppConfirmationSheet(
                title: "Completed Tasks Cleanup",
                message: cleanupMessage(for: action),
                primaryTitle: cleanupPrimaryTitle(for: action),
                primaryStyle: action == .clearAll ? .destructive : .accent,
                onPrimary: {
                    runCleanupAction(action)
                }
            )
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
                },
                onDemoteToBacklog: { taskToDemote in
                    demoteTaskToBacklog(taskToDemote)
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { pendingNextTask != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingNextTask = nil
                        selectedAssigneeIdForNext = nil
                    }
                }
            )
        ) {
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
        .overlay(alignment: .bottom) {
            if let pendingDeletedTask {
                ToastView(
                    message: "\"\(pendingDeletedTask.title)\" deleted",
                    actionTitle: "Undo",
                    action: undoPendingDeleteTask
                )
                .padding(.horizontal, ToastView.Metrics.horizontalInset)
                .padding(.bottom, AppChromeMetrics.compactCTAHeight + 22)
                .transition(ToastView.AnimationTokens.transition)
                .id(pendingDeletedTask.id)
            }
        }
        .animation(ToastView.AnimationTokens.curve, value: pendingDeletedTask?.id)
        .onChange(of: store.error as? TaskStoreError) { _, error in
            guard let error else { return }
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            print("Task Error: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private var activeTasksContent: some View {
        if !visibleNextTasks.isEmpty {
            ForEach(Array(visibleNextTasks.enumerated()), id: \.element.id) { index, task in
                if taskBeingCompleted != task.id {
                    if index == normalizedWipLimit, visibleNextTasks.count > normalizedWipLimit {
                        overLimitSeparator
                            .tasksListRowStyle(taskListRowInsets)
                    }

                    TaskRow(
                        task: task,
                        assigneeName: assigneeName(for: task),
                        assigneeId: task.assigneeId,
                        categoryName: categoryName(for: task),
                        categoryColor: categoryColor(for: task),
                        wipZone: wipZone(for: index),
                        onToggle: { toggleTask(task) },
                        onOpenDetail: { selectedTask = task }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            HapticManager.lightTap()
                            demoteTaskToBacklog(task)
                        } label: {
                            Label("Move to Ideas", systemImage: "archivebox.fill")
                        }
                        .tint(.indigo)

                        Button(role: .destructive) {
                            queueDeleteTask(task)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .rowInsertAnimation()
                    .accessibilityIdentifier("taskRow_\(task.title)")
                    .tasksListRowStyle(taskListRowInsets)
                }
            }
        }

        if !store.backlogTasks.isEmpty {
            sectionHeader("IDEAS")
                .tasksListRowStyle(taskListRowInsets)

            ForEach(store.backlogTasks) { task in
                TaskRow(
                    task: task,
                    assigneeName: assigneeName(for: task),
                    assigneeId: task.assigneeId,
                    categoryName: categoryName(for: task),
                    categoryColor: categoryColor(for: task),
                    wipZone: .normal,
                    onToggle: { toggleTask(task) },
                    onOpenDetail: { selectedTask = task }
                )
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        startTaskFromBacklog(task)
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .tint(themeStore.accentColor)
                }
                .rowInsertAnimation()
                .accessibilityIdentifier("taskRowBacklog_\(task.title)")
                .tasksListRowStyle(taskListRowInsets)
            }
        }

        if !store.recentlyDoneTasks.isEmpty {
            sectionHeader("COMPLETED")
                .tasksListRowStyle(taskListRowInsets)

            ForEach(store.recentlyDoneTasks) { task in
                TaskRow(
                    task: task,
                    assigneeName: assigneeName(for: task),
                    assigneeId: task.assigneeId,
                    categoryName: categoryName(for: task),
                    categoryColor: categoryColor(for: task),
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
                .tasksListRowStyle(taskListRowInsets)
            }
        }
    }

    @ViewBuilder
    private var completedTasksContent: some View {
        if store.doneTasks.isEmpty {
            ContentUnavailableView {
                Label("No Completed Tasks", systemImage: "checkmark.circle")
            } description: {
                Text("Complete some tasks to see them here.")
            }
            .padding(.top, 40)
            .tasksListRowStyle(taskListRowInsets)
        } else {
            sectionHeader("COMPLETED")
                .tasksListRowStyle(taskListRowInsets)

            ForEach(store.doneTasks) { task in
                TaskRow(
                    task: task,
                    assigneeName: assigneeName(for: task),
                    assigneeId: task.assigneeId,
                    categoryName: categoryName(for: task),
                    categoryColor: categoryColor(for: task),
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
                .rowInsertAnimation()
                .accessibilityIdentifier("taskRowCompletedAll_\(task.title)")
                .tasksListRowStyle(taskListRowInsets)
            }
        }
    }

    private var activeMembers: [Member] {
        memberStore.members
            .filter(\.isActive)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private var currentMember: Member? {
        guard let userId = userSession.userId else { return nil }
        return activeMembers.first { $0.userId == userId }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tasks")
                .font(themeStore.font(for: .screenHeader))
                .foregroundStyle(themeStore.contentPrimaryColor)

            Spacer()

            if activeFilter == .completed {
                completedCleanupMenu
            }
        }
    }

    private var filterToggle: some View {
        HStack(spacing: 0) {
            ForEach(TasksFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        activeFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(themeStore.font(for: .filterLabel))
                        .foregroundStyle(activeFilter == filter ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(alignment: .center) {
                    if activeFilter == filter {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule()
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
                            }
                            .matchedGeometryEffect(
                                id: "tasks-filter-indicator", in: tasksFilterGlassNamespace)
                    }
                }
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(Color(.systemGray6))
        }
    }

    private var activeTasksHeader: some View {
        let count = visibleNextTasks.count
        let limit = normalizedWipLimit
        let overLimit = count > limit

        return HStack {
            Text("Active Tasks")
                .font(themeStore.font(for: .sectionHeader))
                .foregroundStyle(themeStore.contentSecondaryColor)

            Spacer()

            Text("\(count) / \(limit)")
                .font(themeStore.font(for: .bodySmall))
                .fontWeight(overLimit ? .bold : .regular)
                .foregroundStyle(overLimit ? .red : themeStore.contentSecondaryColor)
                .monospacedDigit()
        }
    }

    private func startTaskFromBacklog(_ task: Task) {
        let members = activeMembers
        if members.isEmpty {
            if let userId = userSession.userId, let assigneeId = UUID(uuidString: userId) {
                moveTaskToNext(task, assigneeId: assigneeId)
            } else {
                showBanner(.assigneeRequired)
            }
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
                let validation = store.validateNextTransition(
                    assigneeId: existingAssignee, excludingTaskId: task.id)
                guard validation == .ok else {
                    handleNextTransitionValidation(validation)
                    HapticManager.warning()
                    return
                }
                moveTaskToNext(task, assigneeId: existingAssignee)
                return
            } else {
                let members = activeMembers
                if members.isEmpty {
                    if let userId = userSession.userId, let assigneeId = UUID(uuidString: userId) {
                        moveTaskToNext(task, assigneeId: assigneeId)
                    } else {
                        showBanner(.assigneeRequired)
                    }
                } else if members.count == 1, let assigneeId = members.first?.id {
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
                        if themeStore.celebrationsEnabled {
                            celebrationManager.celebrateAllTasksComplete()
                            celebrationManager.triggerConfetti()
                            if activeMembers.count > 1, let name = currentMember?.displayName {
                                celebrationManager.notifyPartner(
                                    completedBy: name,
                                    action: "Cleared all tasks! 🏡"
                                )
                            }
                        }
                    } else {
                        HapticManager.mediumTap()
                        if themeStore.celebrationsEnabled {
                            celebrationManager.celebrateTaskCompletion(taskTitle: task.title)
                            if activeMembers.count > 1, let name = currentMember?.displayName {
                                celebrationManager.notifyPartner(
                                    completedBy: name,
                                    action: "\(task.title) — done!"
                                )
                            }
                        }
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
        case .wipLimitReached(let current, let limit):
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

    private func categoryName(for task: Task) -> String? {
        guard let backlogCategoryId = task.backlogCategoryId else { return nil }
        return backlogStore.categories.first(where: { $0.id == backlogCategoryId })?.title
    }

    private func categoryColor(for task: Task) -> Color? {
        guard let backlogCategoryId = task.backlogCategoryId else { return nil }
        return backlogStore.categories.first(where: { $0.id == backlogCategoryId })?.color
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(themeStore.font(for: .sectionHeader))
            .foregroundStyle(themeStore.contentSecondaryColor)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overLimitSeparator: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(themeStore.separatorColor)
                .frame(height: 1)

            Text("Over limit")
                .font(themeStore.font(for: .chip))
                .foregroundStyle(themeStore.contentSecondaryColor)
                .fixedSize()

            Rectangle()
                .fill(themeStore.separatorColor)
                .frame(height: 1)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("tasksOverLimitSeparator")
    }

    private func wipZone(for index: Int) -> TaskRow.WipZone {
        let limit = normalizedWipLimit
        if index < limit {
            return .normal
        }
        return .warning
    }

    private var normalizedWipLimit: Int {
        min(max(recommendedWipLimit, 1), 7)
    }

    private var visibleNextTasks: [Task] {
        store.nextTasks.filter {
            !hiddenPendingDeleteIds.contains($0.id) && !hiddenMovedToIdeasIds.contains($0.id)
        }
    }

    private var taskListRowInsets: EdgeInsets {
        EdgeInsets(
            top: 0,
            leading: AppChromeMetrics.screenHorizontalInset,
            bottom: 0,
            trailing: AppChromeMetrics.screenHorizontalInset
        )
    }

    private var completedCleanupMenu: some View {
        Menu {
            Button("Clear All", role: .destructive) {
                pendingCleanupAction = .clearAll
            }
            Button("Keep Last 7 Days") {
                pendingCleanupAction = .keepLast7Days
            }
            Button("Keep Last 30 Days") {
                pendingCleanupAction = .keepLast30Days
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("completedCleanupMenu")
    }

    private func runCleanupAction(_ action: CompletedCleanupAction) {
        _ = _Concurrency.Task {
            switch action {
            case .clearAll:
                await store.clearCompletedTasks(keepingDays: nil)
            case .keepLast7Days:
                await store.clearCompletedTasks(keepingDays: 7)
            case .keepLast30Days:
                await store.clearCompletedTasks(keepingDays: 30)
            }
            pendingCleanupAction = nil
            HapticManager.lightTap()
        }
    }

    private func cleanupPrimaryTitle(for action: CompletedCleanupAction) -> String {
        switch action {
        case .clearAll:
            "Clear All"
        case .keepLast7Days:
            "Keep Last 7 Days"
        case .keepLast30Days:
            "Keep Last 30 Days"
        }
    }

    private func cleanupMessage(for action: CompletedCleanupAction) -> String {
        switch action {
        case .clearAll:
            "This removes all completed tasks."
        case .keepLast7Days:
            "This removes completed tasks older than 7 days."
        case .keepLast30Days:
            "This removes completed tasks older than 30 days."
        }
    }

    private func archiveTask(_ task: Task) {
        var updatedTask = task
        updatedTask.completedAt = Date().addingTimeInterval(-86401)
        _ = _Concurrency.Task {
            _ = await store.updateTask(updatedTask)
        }
    }

    private func demoteTaskToBacklog(_ task: Task) {
        withAnimation(.easeInOut(duration: 0.18)) {
            hiddenMovedToIdeasIds.insert(task.id)
        }

        _ = _Concurrency.Task {
            let resolvedCategoryId: UUID? =
                if let backlogCategoryId = task.backlogCategoryId,
                    backlogStore.categories.contains(where: { $0.id == backlogCategoryId })
                {
                    backlogCategoryId
                } else {
                    backlogStore.categories.first?.id
                }

            guard let resolvedCategoryId else {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        hiddenMovedToIdeasIds.remove(task.id)
                    }
                }
                return
            }

            await backlogStore.addItem(
                to: resolvedCategoryId,
                title: task.title,
                assigneeId: task.assigneeId,
                notes: task.notes
            )

            await store.deleteTask(task)
            await MainActor.run {
                hiddenMovedToIdeasIds.remove(task.id)
            }
        }
    }

    private func queueDeleteTask(_ task: Task) {
        if let previous = pendingDeletedTask {
            pendingDeleteWork?.cancel()
            pendingDeleteWork = nil
            withAnimation(ToastView.AnimationTokens.curve) {
                pendingDeletedTask = nil
                hiddenPendingDeleteIds.remove(previous.id)
            }

            _ = _Concurrency.Task {
                await store.deleteTask(previous)
            }
        }

        withAnimation(ToastView.AnimationTokens.curve) {
            pendingDeletedTask = task
            hiddenPendingDeleteIds.insert(task.id)
        }
        HapticManager.lightTap()

        pendingDeleteWork = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 5_000_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            await store.deleteTask(task)
            await MainActor.run {
                withAnimation(ToastView.AnimationTokens.curve) {
                    if pendingDeletedTask?.id == task.id {
                        pendingDeletedTask = nil
                    }
                    hiddenPendingDeleteIds.remove(task.id)
                }
                pendingDeleteWork = nil
            }
        }
    }

    private func undoPendingDeleteTask() {
        guard let pendingDeletedTask else { return }
        pendingDeleteWork?.cancel()
        pendingDeleteWork = nil
        withAnimation(ToastView.AnimationTokens.curve) {
            hiddenPendingDeleteIds.remove(pendingDeletedTask.id)
            self.pendingDeletedTask = nil
        }
        HapticManager.lightTap()
    }
}

// swiftlint:enable type_body_length

private struct InlineStatusBanner: View {
    @EnvironmentObject private var themeStore: ThemeStore
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)

            Text(text)
                .font(themeStore.font(for: .bodySmall))
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
    @EnvironmentObject private var themeStore: ThemeStore
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
                            .font(themeStore.font(for: .inlineTitle))
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
                    .font(themeStore.font(for: .buttonLabel))
                    .disabled(selectedAssigneeId == nil)
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationBackground(.ultraThinMaterial)
    }
}

struct TaskRow: View {
    enum WipZone {
        case safe
        case normal
        case warning
        case danger
    }

    @EnvironmentObject private var themeStore: ThemeStore

    let task: Task
    let assigneeName: String?
    let assigneeId: UUID?
    let categoryName: String?
    let categoryColor: Color?
    let wipZone: WipZone
    let onToggle: () -> Void
    let onOpenDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ThemedCheckbox(
                isChecked: isCompleted,
                onToggle: onToggle,
                size: 22,
                style: .square,
                checkedColor: checkedColor,
                uncheckedColor: uncheckedColor
            )

            Button(action: onOpenDetail) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(themeStore.font(for: .listRowTitle))
                            .foregroundStyle(taskTitleColor)
                            .strikethrough(isCompleted)

                        HStack(spacing: 6) {
                            if let categoryName, let categoryColor {
                                HStack(spacing: 0) {
                                    Text(categoryName)
                                        .font(themeStore.font(for: .chip))
                                        .foregroundStyle(categoryColor)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(categoryColor.opacity(0.12)))
                            }

                            if let assigneeName {
                                let memberColor = Self.memberColor(for: assigneeId)
                                HStack(spacing: 4) {
                                    Text(String(assigneeName.prefix(1)).uppercased())
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 20, height: 20)
                                        .background(Circle().fill(memberColor))
                                    Text(assigneeName)
                                        .font(themeStore.font(for: .bodySmall))
                                        .foregroundStyle(memberColor)
                                }
                                .padding(.trailing, 8)
                                .padding(.leading, 2)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(memberColor.opacity(0.12)))
                            }

                            if let dueDate = task.dueDate {
                                dueDateLabel(dueDate)
                            }

                            if task.taskType == .recurring {
                                Label("Recurring", systemImage: "repeat")
                                    .font(themeStore.font(for: .chip))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.purple.opacity(0.12)))
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
            .opacity(isDimmedOverLimit ? 0.72 : 1.0)
        }
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackgroundColor)
        }
    }

    private var isCompleted: Bool {
        task.status == .done
    }

    private var isDimmedOverLimit: Bool {
        !isCompleted && (wipZone == .warning || wipZone == .danger)
    }

    private var taskTitleColor: Color {
        if isCompleted || isDimmedOverLimit {
            return themeStore.contentSecondaryColor
        }
        return themeStore.contentPrimaryColor
    }

    private var checkedColor: Color {
        isDimmedOverLimit ? .secondary.opacity(0.55) : themeStore.accentTabColor
    }

    private var uncheckedColor: Color {
        switch wipZone {
        case .safe, .normal:
            themeStore.checkboxEmptyColor
        case .warning, .danger:
            themeStore.checkboxEmptyColor.opacity(0.85)
        }
    }

    private var rowBackgroundColor: Color {
        .clear
    }

    @ViewBuilder
    private func dueDateLabel(_ date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let isOverdue = task.isOverdue
        let dueColor: Color =
            if isDimmedOverLimit {
                .secondary
            } else if isOverdue {
                .red
            } else if isToday {
                .orange
            } else {
                .secondary
            }
        let dueBackgroundColor: Color =
            if isDimmedOverLimit {
                .secondary
            } else if isOverdue {
                .red
            } else {
                .orange
            }

        Text(dateFormatter.string(from: date))
            .font(themeStore.font(for: .chip))
            .foregroundStyle(dueColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(dueBackgroundColor.opacity(0.12))
            )
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }

    /// Deterministic color for a member based on their ID hash.
    private static func memberColor(for id: UUID?) -> Color {
        guard let id else { return .secondary }
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint]
        let hash = abs(id.hashValue)
        return colors[hash % colors.count]
    }
}

private struct TaskDetailSheet: View {
    let task: Task
    let members: [Member]
    let onSave: (Task) -> Void
    let onDelete: (Task) -> Void
    let onDemoteToBacklog: (Task) -> Void

    @EnvironmentObject private var themeStore: ThemeStore
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
        onDelete: @escaping (Task) -> Void,
        onDemoteToBacklog: @escaping (Task) -> Void
    ) {
        self.task = task
        self.members = members
        self.onSave = onSave
        self.onDelete = onDelete
        self.onDemoteToBacklog = onDemoteToBacklog

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
                        .font(themeStore.font(for: .body))
                    Picker("Status", selection: $status) {
                        Text("Ideas").tag(Task.TaskStatus.backlog)
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
                        .font(themeStore.font(for: .body))
                        .scrollContentBackground(.hidden)
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

        if status == .backlog {
            onDemoteToBacklog(updatedTask)
        } else {
            onSave(updatedTask)
        }
        dismiss()
    }
}

extension View {
    fileprivate func tasksListRowStyle(_ insets: EdgeInsets) -> some View {
        listRowInsets(insets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

#Preview {
    TasksView(selectedTab: .constant(.tasks))
        .environmentObject(UserSession.shared)
}

// swiftlint:enable file_length
