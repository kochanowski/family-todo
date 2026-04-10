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
        case moveToIdeasFailed

        var text: String {
            switch self {
            case .assigneeRequired:
                "Assign this task before moving it to Next."
            case let .wipLimitReached(current, limit):
                "WIP limit reached (\(current)/\(limit)). Complete one active task first."
            case .moveToIdeasFailed:
                "Couldn't move task to Ideas. Try again."
            }
        }
    }

    private enum TasksFilter: String, CaseIterable {
        case active = "Active"
        case completed = "Completed"
    }

    private enum AssigneeFilter: Equatable {
        case all
        case mine
        case member(UUID)
    }

    private struct AssigneeFilterChip: Identifiable {
        let id: String
        let title: String
        let filter: AssigneeFilter
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
    @State private var assigneeFilter: AssigneeFilter = .all
    @State private var pendingCleanupAction: CompletedCleanupAction?
    @State private var pendingDeletedTask: Task?
    @State private var pendingDeleteWork: _Concurrency.Task<Void, Never>?
    @State private var remoteHighlightedTaskIDs: Set<UUID> = []
    @State private var isApplyingRemoteSyncAnimation = false
    @State private var remoteSyncResetTask: _Concurrency.Task<Void, Never>?
    @State private var hiddenPendingDeleteIds: Set<UUID> = []
    @State private var hiddenMovedToIdeasIds: Set<UUID> = []
    @State private var processingMovedToIdeasIds: Set<UUID> = []
    @State private var hasStartedInitialLoad = false
    @State private var editMode: EditMode = .inactive
    @State private var showRecommendedLimitInfo = false
    @AppStorage("recommendedWipLimit") private var recommendedWipLimit = TaskStore
        .defaultRecommendedWipLimit
    @AppStorage(AppTipProgressKey.tasksTutorialSeen) private var hasSeenTasksTutorial = false
    @AppStorage(AppTipProgressKey.tasksSwipeActionsCompleted)
    private var hasCompletedTaskSwipeActionsTip = false
    @AppStorage(AppTips.runtimeGenerationDefaultsKey)
    private var appTipRuntimeGeneration = 0
    @Binding private var selectedTab: AppTab
    @Namespace private var tasksFilterGlassNamespace

    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var celebrationManager: CelebrationManager
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager
    @EnvironmentObject private var syncCoordinator: HouseholdSyncCoordinator
    @Environment(\.colorScheme) private var colorScheme

    init(householdId: UUID, modelContext: ModelContext, selectedTab: Binding<AppTab>) {
        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(householdId)
        _store = StateObject(wrappedValue: taskStore)
        _memberStore = StateObject(
            wrappedValue: MemberStore(householdId: householdId, modelContext: modelContext)
        )
        _backlogStore = StateObject(
            wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext)
        )
        _selectedTab = selectedTab
    }

    var body: some View {
        let listBottomInset: CGFloat = 16
        let shouldShowActiveEmptyState = activeFilter == .active && filteredActiveTasks.isEmpty
        let shouldShowCompletedEmptyState =
            activeFilter == .completed && filteredCompletedTasks.isEmpty
        let hasRenderableSnapshot = store.hasHydratedLocalSnapshot

        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                .padding(.top, AppChromeMetrics.screenHeaderTopPadding)
                .padding(.bottom, AppChromeMetrics.screenHeaderBottomPadding)

            filterToggle
                .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                .padding(.bottom, 10)

            if shouldShowAssigneeFilterChips {
                assigneeFilterChips
                    .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                    .padding(.bottom, 12)
            }

            if activeFilter == .active {
                if let activeBanner {
                    InlineStatusBanner(text: activeBanner.text)
                        .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            if hasRenderableSnapshot {
                if shouldShowActiveEmptyState {
                    activeTasksEmptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                        .padding(.bottom, listBottomInset)
                } else if shouldShowCompletedEmptyState {
                    completedTasksEmptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                        .padding(.bottom, listBottomInset)
                } else {
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
                    .padding(.bottom, listBottomInset)
                    .environment(\.editMode, $editMode)
                    .refreshable {
                        await performManualRefresh()
                        markTasksTutorialAsSeenIfNeeded()
                    }
                }
            } else {
                ProgressView("Loading tasks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 40)
            }
        }
        .appAdaptiveWidth(
            maxWidth: AppChromeMetrics.regularContentMaxWidth,
            alignment: .topLeading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            guard !hasStartedInitialLoad else { return }
            hasStartedInitialLoad = true
            await refreshData()
            markTasksTutorialAsSeenIfNeeded()
        }
        .onChange(of: selectedTab) { _, newTab in
            guard newTab == .tasks else { return }
            _ = _Concurrency.Task {
                await refreshData()
                markTasksTutorialAsSeenIfNeeded()
            }
        }
        .onChange(of: userSession.syncMode) { _, _ in
            _ = _Concurrency.Task {
                await refreshData()
                markTasksTutorialAsSeenIfNeeded()
            }
        }
        .onChange(of: userSession.userId) { _, _ in
            updateStoreCloudContext()
        }
        .onChange(of: householdStore.currentHousehold?.ownerId) { _, _ in
            updateStoreCloudContext()
        }
        .onChange(of: store.nextTasks.isEmpty) { _, isEmpty in
            if !isEmpty {
                markTasksTutorialAsSeenIfNeeded()
            }
        }
        .onChange(of: activeFilter) { _, newFilter in
            if newFilter != .active, editMode.isEditing {
                editMode = .inactive
            }
        }
        .onChange(of: assigneeFilter) { _, newFilter in
            if newFilter != .all, editMode.isEditing {
                editMode = .inactive
            }
        }
        .onChange(of: activeMembers.map(\.id)) { _, _ in
            normalizeAssigneeFilterSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memberProfileDidChange)) { _ in
            memberStore.markLocalSnapshotStale()
            memberStore.rehydrateVisibleSnapshotFromCache()
            normalizeAssigneeFilterSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskBoardDataDidChange)) { notification in
            store.markLocalSnapshotStale()
            if isLocalStoreNotification(notification) {
                store.rehydrateVisibleSnapshotFromCache()
                markTasksTutorialAsSeenIfNeeded()
            } else {
                store.replayPendingMutationsIfNeeded()
            }
        }
        .onChange(of: syncCoordinator.latestBatch?.id) { _, _ in
            guard let batch = syncCoordinator.latestBatch,
                  !batch.domains.isDisjoint(with: [.tasks, .members, .backlog, .ideas])
            else {
                return
            }

            store.markLocalSnapshotStale()
            if selectedTab == .tasks {
                handleRemoteTaskSyncBatch(batch)
            } else {
                store.rehydrateVisibleSnapshotFromCache()
                store.replayPendingMutationsIfNeeded()
            }
        }
        .onDisappear {
            cancelRemoteSyncAnimationReset()
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
                }
            )
        }
        .alert("Recommended Task Limit", isPresented: $showRecommendedLimitInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "This is your daily recommended limit of active tasks to help you stay focused. You can adjust this limit in the More -> Settings tab."
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
        let displayedTasks = filteredActiveTasks
        ForEach(displayedTasks) { task in
            if taskBeingCompleted != task.id {
                let index = displayedTasks.firstIndex(where: { $0.id == task.id }) ?? 0
                if isSingleAssigneeFilter,
                   index == normalizedWipLimit,
                   displayedTasks.count > normalizedWipLimit
                {
                    overLimitSeparator
                        .tasksListRowStyle(taskListRowInsets)
                }

                TaskRow(
                    task: task,
                    assignee: assignee(for: task),
                    categoryName: categoryName(for: task),
                    categoryColor: categoryColor(for: task),
                    appTipRuntimeGeneration: appTipRuntimeGeneration,
                    wipZone: wipZone(for: task),
                    showsSwipeActionsTip: shouldShowTaskSwipeActionsTip &&
                        task.id == taskSwipeActionsTipTaskID,
                    onToggle: { toggleTask(task) },
                    onOpenDetail: { selectedTask = task }
                )
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if isTaskAssignedToOther(task) {
                        let isPokeInFlight = store.pendingTaskMutations.contains(task.id)
                        let isPokeAvailable = store.canPoke(task: task)
                        Button {
                            sendPoke(task)
                        } label: {
                            if isPokeInFlight {
                                Label("Sending...", systemImage: "hourglass")
                            } else {
                                Label(
                                    isPokeAvailable ? "Poke" : "Poked today",
                                    systemImage: isPokeAvailable ? "hand.wave.fill" : "moon.zzz.fill"
                                )
                            }
                        }
                        .tint(isPokeInFlight ? .gray : (isPokeAvailable ? .orange : .gray))
                        .disabled(isPokeInFlight || !isPokeAvailable)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        HapticManager.lightTap()
                        demoteTaskToBacklog(task)
                    } label: {
                        Label {
                            Text("Move to Ideas")
                                .font(themeStore.font(for: .buttonLabel))
                        } icon: {
                            Image(systemName: "archivebox.fill")
                        }
                    }
                    .tint(.indigo)

                    Button(role: .destructive) {
                        queueDeleteTask(task)
                    } label: {
                        Label {
                            Text("Delete")
                                .font(themeStore.font(for: .buttonLabel))
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                }
                .accessibilityIdentifier("taskRow_\(task.title)")
                .remoteSyncStructuralTransition(enabled: isApplyingRemoteSyncAnimation)
                .remoteSyncHighlight(
                    isActive: remoteHighlightedTaskIDs.contains(task.id),
                    cornerRadius: 8
                )
                .tasksListRowStyle(taskListRowInsets)
            }
        }
        .onMove(perform: moveActiveTasks)
        .moveDisabled(
            taskBeingCompleted != nil ||
                !hiddenPendingDeleteIds.isEmpty ||
                !hiddenMovedToIdeasIds.isEmpty
        )
        .animation(.default, value: activeTaskAnimationIDs)
    }

    private var completedTasksContent: some View {
        ForEach(filteredCompletedTasks) { task in
            TaskRow(
                task: task,
                assignee: assignee(for: task),
                categoryName: categoryName(for: task),
                categoryColor: categoryColor(for: task),
                appTipRuntimeGeneration: appTipRuntimeGeneration,
                wipZone: .normal,
                showsSwipeActionsTip: false,
                onToggle: { toggleTask(task) },
                onOpenDetail: { selectedTask = task }
            )
            .swipeActions(edge: .trailing) {
                Button {
                    archiveTask(task)
                } label: {
                    Label {
                        Text("Archive")
                            .font(themeStore.font(for: .buttonLabel))
                    } icon: {
                        Image(systemName: "archivebox")
                    }
                }
                .tint(.orange)
            }
            .accessibilityIdentifier("taskRowCompletedAll_\(task.title)")
            .remoteSyncStructuralTransition(enabled: isApplyingRemoteSyncAnimation)
            .remoteSyncHighlight(
                isActive: remoteHighlightedTaskIDs.contains(task.id),
                cornerRadius: 8
            )
            .tasksListRowStyle(taskListRowInsets)
        }
        .animation(.default, value: completedTaskAnimationIDs)
    }

    private var activeTasksEmptyState: some View {
        Group {
            if shouldShowFilteredActiveEmptyState {
                ThemedEmptyStateView(
                    title: "No Matching Active Tasks",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: "Try a different filter or create a new task."
                )
            } else if store.doneTasks.isEmpty {
                ThemedEmptyStateView(
                    title: "No Tasks Yet. Ready to get organized?",
                    systemImage: "checklist",
                    description: "Start in Ideas, then promote the task when you're ready to work on it."
                ) {
                    Button("Create your first task") {
                        HapticManager.lightTap()
                        selectedTab = .backlog
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .buttonStyle(.borderedProminent)
                    .tint(themeStore.accentTabColor)
                }
            } else {
                ThemedEmptyStateView(
                    title: "All Caught Up!",
                    systemImage: "sparkles",
                    description: "The house is looking great. Enjoy your free time or create a new task."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: -40)
    }

    private var completedTasksEmptyState: some View {
        Group {
            if shouldShowFilteredCompletedEmptyState {
                ThemedEmptyStateView(
                    title: "No Matching Completed Tasks",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: "Try another filter to see completed items."
                )
            } else {
                ThemedEmptyStateView(
                    title: "No Completed Tasks",
                    systemImage: "checkmark.circle",
                    description: "Tasks you finish will appear here."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: -40)
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

    private var currentMemberId: UUID? {
        currentMember?.id ?? userSession.userId.flatMap(UUID.init(uuidString:))
    }

    private var assigneeFilterOptions: [AssigneeFilterChip] {
        var options: [AssigneeFilterChip] = [
            AssigneeFilterChip(id: "all", title: "All tasks", filter: .all),
        ]

        if currentMemberId != nil {
            options.append(AssigneeFilterChip(id: "mine", title: "My tasks", filter: .mine))
        }

        for member in activeMembers where member.id != currentMemberId {
            options.append(
                AssigneeFilterChip(
                    id: "member-\(member.id.uuidString)",
                    title: "\(member.displayName)'s tasks",
                    filter: .member(member.id)
                )
            )
        }

        return options
    }

    private var filteredActiveTasks: [Task] {
        visibleNextTasks.filter(matchesAssigneeFilter)
    }

    private var filteredCompletedTasks: [Task] {
        store.recentlyDoneTasks.filter(matchesAssigneeFilter)
    }

    private var activeTaskAnimationIDs: [UUID] {
        filteredActiveTasks.map(\.id)
    }

    private var completedTaskAnimationIDs: [UUID] {
        filteredCompletedTasks.map(\.id)
    }

    private var shouldShowAssigneeFilterChips: Bool {
        activeMembers.count > 1
    }

    private var shouldShowFilteredActiveEmptyState: Bool {
        shouldShowAssigneeFilterChips && assigneeFilter != .all && !visibleNextTasks.isEmpty
    }

    private var shouldShowFilteredCompletedEmptyState: Bool {
        shouldShowAssigneeFilterChips && assigneeFilter != .all && !store.recentlyDoneTasks.isEmpty
    }

    private var header: some View {
        AppScreenHeader(title: "Tasks") {
            HStack(spacing: 8) {
                if activeFilter == .active {
                    Button {
                        showRecommendedLimitInfo = true
                    } label: {
                        TasksWIPBadge(count: wipBadgeCount, limit: normalizedWipLimit)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows information about the recommended task limit")
                }

                if subscriptionManager.tasksInlineIndicator != nil,
                   selectedTab == .tasks
                {
                    SyncStatusIcon()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        } trailing: {
            if activeFilter == .active {
                if assigneeFilter == .all {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .foregroundStyle(
                        visibleNextTasks.isEmpty
                            ? themeStore.contentSecondaryColor : themeStore.accentTabColor
                    )
                    .disabled(visibleNextTasks.isEmpty)
                }
            } else {
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
                                id: "tasks-filter-indicator", in: tasksFilterGlassNamespace
                            )
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

    private var assigneeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(assigneeFilterOptions) { option in
                    let isSelected = assigneeFilter == option.filter
                    let foreground =
                        isSelected
                            ? themeStore.foregroundOnAccent(
                                for: themeStore.accentTabColor,
                                colorScheme: colorScheme
                            ) : themeStore.contentSecondaryColor

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            assigneeFilter = option.filter
                        }
                    } label: {
                        Text(option.title)
                            .font(themeStore.font(for: .chip))
                            .foregroundStyle(foreground)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background {
                                Capsule()
                                    .fill(isSelected ? themeStore.accentTabColor : Color(.systemGray6))
                            }
                            .overlay {
                                Capsule()
                                    .stroke(
                                        isSelected
                                            ? themeStore.accentTabColor.opacity(0.5)
                                            : themeStore.borderLightColor.opacity(0.5),
                                        lineWidth: 0.9
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
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
                    assigneeId: existingAssignee, excludingTaskId: task.id
                )
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
                    let validation = await store.toggleTaskCompletion(task)
                    taskBeingCompleted = nil
                    handleNextTransitionValidation(validation)

                    if willCompleteAll {
                        HapticManager.success()
                        if themeStore.celebrationsEnabled {
                            celebrationManager.celebrateAllTasksComplete()
                        }
                    } else {
                        HapticManager.mediumTap()
                        if themeStore.celebrationsEnabled {
                            let weeklyCompletedCount = store.completedTaskCountThisWeek()
                            celebrationManager.celebrateTaskCompletion(
                                taskTitle: task.title,
                                weeklyCompletedCount: weeklyCompletedCount
                            )
                        }
                    }
                }
            }
        } else {
            _ = _Concurrency.Task {
                let validation = await store.toggleTaskCompletion(task)
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

    private func assignee(for task: Task) -> Member? {
        guard let assigneeId = task.assigneeId else { return nil }
        return memberStore.members.first(where: { $0.id == assigneeId })
    }

    private func isTaskAssignedToOther(_ task: Task) -> Bool {
        let assignedIDs = Set(task.assigneeIds + (task.assigneeId.map { [$0] } ?? []))
        guard !assignedIDs.isEmpty, let currentMemberId else { return false }
        return !assignedIDs.contains(currentMemberId)
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

    private func wipZone(for task: Task) -> TaskRow.WipZone {
        let limit = normalizedWipLimit
        guard let assigneeId = task.assigneeId else { return .normal }
        let assigneeTasks = visibleNextTasks.filter { $0.assigneeId == assigneeId }
        let assigneeIndex = assigneeTasks.firstIndex(where: { $0.id == task.id }) ?? 0
        return assigneeIndex < limit ? .normal : .warning
    }

    private var isSingleAssigneeFilter: Bool {
        switch assigneeFilter {
        case .all: false
        case .mine, .member: true
        }
    }

    private var wipBadgeCount: Int {
        switch assigneeFilter {
        case .all:
            guard let id = currentMemberId else { return filteredActiveTasks.count }
            return store.nextTaskCount(for: id)
        case .mine, .member:
            return filteredActiveTasks.count
        }
    }

    private var normalizedWipLimit: Int {
        min(max(recommendedWipLimit, 1), 7)
    }

    private var visibleNextTasks: [Task] {
        store.nextTasks.filter {
            !hiddenPendingDeleteIds.contains($0.id) && !hiddenMovedToIdeasIds.contains($0.id)
        }
    }

    private var shouldShowTaskSwipeActionsTip: Bool {
        AppTipVisibility.shouldShowTaskSwipeActionsTip(
            isTasksTabSelected: selectedTab == .tasks,
            isShowingActiveFilter: activeFilter == .active,
            hasVisibleActiveTasks: !filteredActiveTasks.isEmpty,
            isReordering: editMode.isEditing,
            hasInlineBanner: activeBanner != nil,
            hasPresentedSheet: selectedTask != nil || pendingNextTask != nil,
            hasPendingDeleteToast: pendingDeletedTask != nil,
            isTaskCompletionAnimating: taskBeingCompleted != nil,
            hasCompletedSwipeActionsTip: hasCompletedTaskSwipeActionsTip
        )
    }

    private var taskSwipeActionsTipTaskID: UUID? {
        filteredActiveTasks.first?.id
    }

    private func matchesAssigneeFilter(_ task: Task) -> Bool {
        switch assigneeFilter {
        case .all:
            return true
        case .mine:
            guard let currentMemberId else { return false }
            return task.assigneeId == currentMemberId
        case let .member(memberId):
            return task.assigneeId == memberId
        }
    }

    private func normalizeAssigneeFilterSelection() {
        guard shouldShowAssigneeFilterChips else {
            assigneeFilter = .all
            return
        }

        switch assigneeFilter {
        case .all:
            return
        case .mine:
            if currentMemberId == nil {
                assigneeFilter = .all
            }
        case let .member(memberId):
            if !activeMembers.contains(where: { $0.id == memberId }) {
                assigneeFilter = .all
            }
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
            Button(role: .destructive) {
                pendingCleanupAction = .clearAll
            } label: {
                Text("Clear All")
                    .font(themeStore.font(for: .buttonLabel))
            }
            Button {
                pendingCleanupAction = .keepLast7Days
            } label: {
                Text("Keep Last 7 Days")
                    .font(themeStore.font(for: .buttonLabel))
            }
            Button {
                pendingCleanupAction = .keepLast30Days
            } label: {
                Text("Keep Last 30 Days")
                    .font(themeStore.font(for: .buttonLabel))
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(themeStore.accentTabColor)
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

    private func refreshData() async {
        updateStoreCloudContext()
        store.setSyncMode(userSession.syncMode)
        memberStore.setSyncMode(userSession.syncMode)
        backlogStore.setSyncMode(userSession.syncMode)

        async let loadTasks = store.loadTasksForDisplay()
        async let loadMembers = memberStore.loadMembersForDisplay()
        async let loadBacklog = backlogStore.loadDataForDisplay()

        _ = await (loadTasks, loadMembers, loadBacklog)
        normalizeAssigneeFilterSelection()
    }

    private func performManualRefresh() async {
        if userSession.syncMode == .cloud {
            await syncCoordinator.performInteractiveManualRefresh()
        }
        await refreshData()
    }

    private func updateStoreCloudContext() {
        let syncContext = householdStore.currentSyncContext(userId: userSession.userId)
        store.setCloudContext(syncContext)
        memberStore.setCloudContext(syncContext)
        backlogStore.setCloudContext(syncContext)
    }

    private func markTasksTutorialAsSeenIfNeeded() {
        guard !store.nextTasks.isEmpty, !hasSeenTasksTutorial else { return }
        hasSeenTasksTutorial = true
    }

    private func archiveTask(_ task: Task) {
        _ = _Concurrency.Task {
            await store.archiveTask(task)
        }
    }

    private func sendPoke(_ task: Task) {
        guard isTaskAssignedToOther(task) else { return }
        guard store.canPoke(task: task), !store.pendingTaskMutations.contains(task.id) else {
            HapticManager.warning()
            return
        }

        AppTips.donateTaskSwipeActionUsed()
        _ = _Concurrency.Task {
            let didPoke = await store.pokeTask(task)
            if didPoke {
                HapticManager.selection()
            } else {
                HapticManager.warning()
            }
        }
    }

    private func demoteTaskToBacklog(_ task: Task) {
        guard processingMovedToIdeasIds.insert(task.id).inserted else { return }
        AppTips.donateTaskSwipeActionUsed()
        withAnimation(.easeInOut(duration: 0.18)) {
            hiddenMovedToIdeasIds.insert(task.id)
        }

        let result = store.moveTaskToIdeas(
            task,
            destinationCategoryId: backlogStore.resolveDestinationCategoryIdForTaskMove(task)
        )
        guard case .success = result else {
            processingMovedToIdeasIds.remove(task.id)
            hiddenMovedToIdeasIds.remove(task.id)
            showBanner(.moveToIdeasFailed)
            HapticManager.warning()
            return
        }

        processingMovedToIdeasIds.remove(task.id)
        hiddenMovedToIdeasIds.remove(task.id)
    }

    private func moveActiveTasks(from source: IndexSet, to destination: Int) {
        let visibleIds = visibleNextTasks.map(\.id)
        _ = _Concurrency.Task {
            await store.reorderActiveTasks(
                from: source,
                to: destination,
                visibleTaskIDs: visibleIds
            )
        }
    }

    private func isLocalStoreNotification(_ notification: Notification) -> Bool {
        (notification.object as? String) == "local"
    }

    private func handleRemoteTaskBoardChange(_ notification: Notification) {
        let payload = notification.remoteSyncAnimationPayload
        let changedIDs = payload?.workItemChangedIDs ?? []

        cancelRemoteSyncAnimationReset()
        isApplyingRemoteSyncAnimation = true

        _ = _Concurrency.Task { @MainActor in
            let refreshTask = RemoteVisibleRefreshTask(
                changedIDs: changedIDs,
                captureVisibleLocations: visibleTaskLocations,
                rehydratePrimaryStore: {
                    withAnimation(WowAnimation.spring) {
                        store.rehydrateVisibleSnapshotFromCache()
                    }
                },
                refreshDependentStores: {
                    memberStore.markLocalSnapshotStale()
                    memberStore.rehydrateVisibleSnapshotFromCache()
                    backlogStore.markLocalSnapshotStale()
                    backlogStore.rehydrateVisibleSnapshotFromCache()
                    normalizeAssigneeFilterSelection()
                }
            )

            let delta = await refreshTask.run()
            remoteHighlightedTaskIDs = delta.highlightedIDs
            logRemoteSyncVisibleRefreshLatency(screen: "Tasks", payload: payload)
            scheduleRemoteSyncAnimationReset()
            markTasksTutorialAsSeenIfNeeded()
        }
    }

    private func handleRemoteTaskSyncBatch(_ batch: HouseholdSyncBatch) {
        if batch.classification == .bootstrap {
            cancelRemoteSyncAnimationReset()
            _ = _Concurrency.Task { @MainActor in
                store.rehydrateVisibleSnapshotFromCache()
                memberStore.markLocalSnapshotStale()
                memberStore.rehydrateVisibleSnapshotFromCache()
                backlogStore.markLocalSnapshotStale()
                backlogStore.rehydrateVisibleSnapshotFromCache()
                normalizeAssigneeFilterSelection()
                markTasksTutorialAsSeenIfNeeded()
            }
            return
        }

        let changedIDs = batch.taskChangedIDs

        cancelRemoteSyncAnimationReset()
        isApplyingRemoteSyncAnimation = true

        _ = _Concurrency.Task { @MainActor in
            let refreshTask = RemoteVisibleRefreshTask(
                changedIDs: changedIDs,
                captureVisibleLocations: visibleTaskLocations,
                rehydratePrimaryStore: {
                    withAnimation(WowAnimation.spring) {
                        store.rehydrateVisibleSnapshotFromCache()
                    }
                },
                refreshDependentStores: {
                    memberStore.markLocalSnapshotStale()
                    memberStore.rehydrateVisibleSnapshotFromCache()
                    backlogStore.markLocalSnapshotStale()
                    backlogStore.rehydrateVisibleSnapshotFromCache()
                    normalizeAssigneeFilterSelection()
                }
            )

            let delta = await refreshTask.run()
            remoteHighlightedTaskIDs = delta.highlightedIDs
            scheduleRemoteSyncAnimationReset()
            markTasksTutorialAsSeenIfNeeded()
        }
    }

    private func visibleTaskLocations() -> [UUID: Int] {
        let visibleTasks = activeFilter == .active ? filteredActiveTasks : filteredCompletedTasks
        return Dictionary(uniqueKeysWithValues: visibleTasks.map { ($0.id, 0) })
    }

    private func scheduleRemoteSyncAnimationReset() {
        remoteSyncResetTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(
                nanoseconds: WowAnimation.remoteSyncStructureResetNanoseconds
            )
            guard !_Concurrency.Task.isCancelled else { return }
            isApplyingRemoteSyncAnimation = false

            try? await _Concurrency.Task.sleep(
                nanoseconds: WowAnimation.remoteSyncHighlightDurationNanoseconds
            )
            guard !_Concurrency.Task.isCancelled else { return }
            remoteHighlightedTaskIDs.removeAll()
            remoteSyncResetTask = nil
        }
    }

    private func cancelRemoteSyncAnimationReset() {
        remoteSyncResetTask?.cancel()
        remoteSyncResetTask = nil
        isApplyingRemoteSyncAnimation = false
        remoteHighlightedTaskIDs.removeAll()
    }

    private func queueDeleteTask(_ task: Task) {
        AppTips.donateTaskSwipeActionUsed()
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
    let assignee: Member?
    let categoryName: String?
    let categoryColor: Color?
    let appTipRuntimeGeneration: Int
    let wipZone: WipZone
    let showsSwipeActionsTip: Bool
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
                                taskMetadataChip(
                                    categoryName,
                                    foreground: categoryColor,
                                    background: categoryColor.opacity(0.12)
                                )
                            }

                            if let assignee {
                                MemberNameChipView(
                                    name: assignee.displayName,
                                    colorHex: assignee.colorHex
                                )
                            }

                            if let dueDate = task.dueDate {
                                dueDateLabel(dueDate)
                            }

                            if task.taskType == .recurring {
                                taskMetadataChip(
                                    "Recurring",
                                    systemImage: "repeat",
                                    foreground: .purple,
                                    background: Color.purple.opacity(0.12)
                                )
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
            .contextualPopoverTip(
                showsSwipeActionsTip,
                tipID: "tasks.swipeActions",
                TaskSwipeActionsTip(),
                arrowEdge: .top,
                generation: appTipRuntimeGeneration
            )
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

    private func taskMetadataChip(
        _ text: String,
        systemImage: String? = nil,
        foreground: Color,
        background: Color
    ) -> some View {
        Group {
            if let systemImage {
                Label {
                    Text(text)
                } icon: {
                    Image(systemName: systemImage)
                }
            } else {
                Text(text)
            }
        }
        .font(themeStore.font(for: .chip))
        .foregroundStyle(foreground)
        .lineLimit(1)
        .padding(.horizontal, MetadataChipMetrics.horizontalPadding)
        .padding(.vertical, MetadataChipMetrics.verticalPadding)
        .frame(minHeight: MetadataChipMetrics.minHeight)
        .background(
            Capsule()
                .fill(background)
        )
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

        taskMetadataChip(
            dueDateText(for: date),
            foreground: dueColor,
            background: dueBackgroundColor.opacity(0.12)
        )
    }

    private func dueDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = Task.dueDateHasExplicitTime(date) ? .short : .none
        return formatter.string(from: date)
    }
}

private struct TaskDetailSheet: View {
    let task: Task
    let members: [Member]
    let onSave: (Task) -> Void
    let onDelete: (Task) -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var notificationSettings = NotificationSettingsStore()
    @State private var title: String
    @State private var assigneeId: UUID?
    @State private var hasDueDate: Bool
    @State private var hasDueTime: Bool
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

        let initialAssigneeId = task.assigneeId ?? members.first(where: \.isActive)?.id
        _title = State(initialValue: task.title)
        _assigneeId = State(initialValue: initialAssigneeId)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _hasDueTime = State(initialValue: task.dueDate.map { Task.dueDateHasExplicitTime($0) } ?? false)
        _dueDate = State(initialValue: task.dueDate ?? Date())
        _notes = State(initialValue: task.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $title)
                        .font(themeStore.font(for: .bodyStrong))
                } header: {
                    Text("Task title")
                        .font(themeStore.font(for: .sectionHeader))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }

                Section {
                    if assignableMembers.isEmpty {
                        Text("No members available.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                    } else {
                        Picker(selection: $assigneeId) {
                            ForEach(assignableMembers) { member in
                                Text(member.displayName)
                                    .font(themeStore.font(for: .bodyStrong))
                                    .tag(Optional(member.id))
                            }
                        } label: {
                            Label("Assigned To", systemImage: "person.fill")
                                .font(themeStore.font(for: .bodyStrong))
                        }
                        .font(themeStore.font(for: .bodyStrong))
                    }

                    Toggle(isOn: $hasDueDate) {
                        Label("Due Date", systemImage: "calendar")
                            .font(themeStore.font(for: .bodyStrong))
                    }
                    if hasDueDate {
                        DatePicker(
                            selection: $dueDate,
                            displayedComponents: [.date]
                        ) {
                            Text("Choose Date")
                                .font(themeStore.font(for: .bodyStrong))
                        }
                        .font(themeStore.font(for: .bodyStrong))

                        Toggle(isOn: $hasDueTime) {
                            Label("Specific Time", systemImage: "clock")
                                .font(themeStore.font(for: .bodyStrong))
                        }

                        if hasDueTime {
                            DatePicker(
                                selection: $dueDate,
                                displayedComponents: [.hourAndMinute]
                            ) {
                                Text("Reminder Time")
                                    .font(themeStore.font(for: .bodyStrong))
                            }
                            .font(themeStore.font(for: .bodyStrong))
                        }
                    }
                } header: {
                    Text("Details")
                        .font(themeStore.font(for: .sectionHeader))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }

                Section {
                    TextEditor(text: $notes)
                        .font(themeStore.font(for: .listRowTitle))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                } header: {
                    Label("Notes", systemImage: "note.text")
                        .font(themeStore.font(for: .sectionHeader))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }

                Section {
                    Button(role: .destructive) {
                        onDelete(task)
                        dismiss()
                    } label: {
                        Text("Delete Task")
                            .font(themeStore.font(for: .buttonLabel))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .foregroundStyle(.red)
                }
            }
            .font(themeStore.font(for: .bodyStrong))
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: hasDueTime) { _, isEnabled in
                guard isEnabled, !Task.dueDateHasExplicitTime(dueDate) else { return }
                if let updatedDate = Task.date(
                    byApplyingTimeFrom: notificationSettings.reminderTime,
                    to: dueDate
                ) {
                    dueDate = updatedDate
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                }
                ToolbarItem(placement: .principal) {
                    Text("Task")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            assigneeId == nil
                    )
                }
            }
        }
    }

    private var assignableMembers: [Member] {
        var byID: [UUID: Member] = [:]

        for member in members where member.isActive || member.id == assigneeId {
            byID[member.id] = member
        }

        return byID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func save() {
        guard let assigneeId else { return }

        var updatedTask = task
        updatedTask.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedTask.assigneeId = assigneeId
        updatedTask.assigneeIds = [assigneeId]
        updatedTask.dueDate = if hasDueDate {
            hasDueTime ? dueDate : Calendar.current.startOfDay(for: dueDate)
        } else {
            nil
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedTask.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        onSave(updatedTask)
        dismiss()
    }
}

private extension View {
    func tasksListRowStyle(_ insets: EdgeInsets) -> some View {
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
