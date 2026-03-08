// swiftlint:disable file_length
import SwiftData
import SwiftUI

/// Backlog screen - long-term storage for ideas and projects, organized by categories
struct BacklogView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                BacklogContent(householdId: householdId, modelContext: modelContext)
            } else {
                GuidedEmptyStateView()
            }
        }
    }
}

private struct BacklogContent: View {
    private enum PromotionBanner: Equatable {
        case assigneeRequired
        case wipLimitReached(current: Int, limit: Int)
        case failed(String)

        var text: String {
            switch self {
            case .assigneeRequired:
                "Assign this idea before moving it to Tasks/NEXT."
            case let .wipLimitReached(current, limit):
                "WIP limit reached (\(current)/\(limit)). Complete one active task first."
            case let .failed(message):
                message
            }
        }
    }

    @StateObject private var store: BacklogStore
    @StateObject private var taskStore: TaskStore
    @StateObject private var memberStore: MemberStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryColorHex = MemberColorToken.randomHex()
    @State private var activeBanner: PromotionBanner?
    @State private var pendingPromotionItem: BacklogItem?
    @State private var pendingPromotionTask: Task?
    @State private var selectedAssigneeIdForPromotion: UUID?
    @State private var pendingAssignmentItem: BacklogItem?
    @State private var pendingAssignmentTask: Task?
    @State private var selectedAssigneeIdForAssignment: UUID?
    @State private var editingCategory: BacklogCategory?
    @State private var editingItem: BacklogItem?
    @State private var activeComposerCategoryId: UUID?
    @State private var composerText = ""
    @State private var pendingDeletionItem: BacklogItem?
    @State private var pendingDeletionTask: Task?
    @State private var deletionTask: _Concurrency.Task<Void, Never>?
    @State private var hiddenPendingDeleteIds: Set<UUID> = []
    @State private var hiddenPendingPromotionIds: Set<UUID> = []
    @State private var processingPromotionEntryIds: Set<UUID> = []
    @FocusState private var focusedComposerCategoryId: UUID?
    @AppStorage("hasSeenIdeasTutorial") private var hasSeenIdeasTutorial = false
    private let householdId: UUID
    private let modelContext: ModelContext

    init(householdId: UUID, modelContext: ModelContext) {
        self.householdId = householdId
        self.modelContext = modelContext
        _store = StateObject(
            wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext)
        )
        let tasks = TaskStore(modelContext: modelContext)
        tasks.setHousehold(householdId)
        _taskStore = StateObject(wrappedValue: tasks)
        _memberStore = StateObject(
            wrappedValue: MemberStore(householdId: householdId, modelContext: modelContext)
        )
    }

    var body: some View {
        let listBottomInset: CGFloat = 16
        let hasUncategorizedIdeas = !uncategorizedBacklogTasks.isEmpty

        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                .padding(.top, AppChromeMetrics.screenHeaderTopPadding)
                .padding(
                    .bottom, activeBanner == nil ? AppChromeMetrics.screenHeaderBottomPadding : 8
                )

            if let activeBanner {
                BacklogStatusBanner(text: activeBanner.text)
                    .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if store.categories.isEmpty, !hasUncategorizedIdeas {
                emptyState
                    .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                    .padding(.bottom, listBottomInset)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            if hasUncategorizedIdeas {
                                UncategorizedBacklogTasksCard(
                                    tasks: uncategorizedBacklogTasks,
                                    isPromotingTask: { processingPromotionEntryIds.contains($0) },
                                    assigneeFor: assignee(for:),
                                    onAssignTask: { task in
                                        queueAssignTask(task)
                                    },
                                    onPromoteTask: { task in
                                        promoteTask(task)
                                    },
                                    onDeleteTask: { task in
                                        queueDeleteTask(task)
                                    }
                                )
                            }

                            ForEach(store.categories) { category in
                                let categoryItems = visibleItems(for: category.id)
                                let categoryTasks = visibleBacklogTasks(for: category.id)
                                CategoryCard(
                                    category: category,
                                    items: categoryItems,
                                    backlogTasks: categoryTasks,
                                    isPromotingEntry: { processingPromotionEntryIds.contains($0) },
                                    assigneeFor: { assigneeId in
                                        assignee(for: assigneeId)
                                    },
                                    isAddingItem: activeComposerCategoryId == category.id,
                                    newItemText: Binding(
                                        get: {
                                            activeComposerCategoryId == category.id
                                                ? composerText : ""
                                        },
                                        set: { composerText = $0 }
                                    ),
                                    focusedComposerCategoryId: $focusedComposerCategoryId,
                                    onActivateComposer: {
                                        activateComposer(for: category.id, scrollProxy: scrollProxy)
                                    },
                                    onSubmitItem: {
                                        submitComposer(for: category.id)
                                    },
                                    onCancelItem: {
                                        cancelComposer(for: category.id)
                                    },
                                    onDeleteItem: { item in
                                        queueDeleteItem(item)
                                    },
                                    onDeleteTask: { task in
                                        queueDeleteTask(task)
                                    },
                                    onEditItem: { item in
                                        editingItem = item
                                    },
                                    onAssignItem: { item in
                                        queueAssignItem(item)
                                    },
                                    onAssignTask: { task in
                                        queueAssignTask(task)
                                    },
                                    onPromoteItem: { item in
                                        promoteItem(item)
                                    },
                                    onPromoteTask: { task in
                                        promoteTask(task)
                                    },
                                    onEditCategory: {
                                        editingCategory = category
                                    },
                                    onDeleteCategory: {
                                        _ = _Concurrency.Task {
                                            let result = await store.deleteCategory(category)
                                            await MainActor.run {
                                                handleCategoryDeletionResult(result)
                                            }
                                        }
                                    }
                                )
                                .id(category.id)
                                .rowInsertAnimation()
                            }
                        }
                        .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                        .padding(.bottom, listBottomInset)
                    }
                    .scrollDismissesKeyboard(.never)
                }
                .refreshable {
                    store.setSyncMode(userSession.syncMode)
                    taskStore.setSyncMode(userSession.syncMode)
                    memberStore.setSyncMode(userSession.syncMode)
                    await store.loadData()
                    await taskStore.loadTasks()
                    await memberStore.loadMembers()
                    markIdeasTutorialAsSeenIfNeeded()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            store.setSyncMode(userSession.syncMode)
            taskStore.setSyncMode(userSession.syncMode)
            memberStore.setSyncMode(userSession.syncMode)
            await store.loadData()
            await taskStore.loadTasks()
            await memberStore.loadMembers()
            markIdeasTutorialAsSeenIfNeeded()
        }
        .onChange(of: store.categories.isEmpty) { _, categoriesAreEmpty in
            if !categoriesAreEmpty || !allVisibleBacklogTasks.isEmpty {
                markIdeasTutorialAsSeenIfNeeded()
            }
        }
        .onChange(of: taskStore.backlogTasks.count) { _, _ in
            markIdeasTutorialAsSeenIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskBoardDataDidChange)) { _ in
            _ = _Concurrency.Task {
                await store.loadData()
                await taskStore.loadTasks()
                markIdeasTutorialAsSeenIfNeeded()
            }
        }
        .sheet(isPresented: $isAddingCategory) {
            CategoryEditorSheet(
                title: "New Category",
                initialName: newCategoryName,
                initialColorHex: newCategoryColorHex,
                primaryTitle: "Create",
                onCancel: {
                    newCategoryName = ""
                    newCategoryColorHex = MemberColorToken.randomHex()
                },
                onSubmit: { name, colorHex in
                    newCategoryName = ""
                    newCategoryColorHex = MemberColorToken.randomHex()
                    HapticManager.lightTap()
                    _ = _Concurrency.Task { await store.addCategory(name, colorHex: colorHex) }
                }
            )
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditorSheet(
                title: "Edit Category",
                initialName: category.title,
                initialColorHex: category.colorHex,
                primaryTitle: "Save",
                onCancel: {},
                onSubmit: { newName, newColorHex in
                    _ = _Concurrency.Task {
                        await store.updateCategory(
                            category,
                            newTitle: newName,
                            newColorHex: newColorHex
                        )
                    }
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { pendingPromotionItem != nil || pendingPromotionTask != nil },
                set: { isPresented in
                    if !isPresented {
                        cancelPendingPromotion()
                    }
                }
            )
        ) {
            if pendingPromotionItem != nil || pendingPromotionTask != nil {
                BacklogAssigneePickerSheet(
                    title: "Assign before start",
                    actionTitle: "Promote",
                    members: activeMembers,
                    autoConfirmOnSelection: false,
                    selectedAssigneeId: $selectedAssigneeIdForPromotion,
                    onCancel: {
                        cancelPendingPromotion()
                    },
                    onConfirm: {
                        guard let assigneeId = selectedAssigneeIdForPromotion else { return }
                        let item = pendingPromotionItem
                        let task = pendingPromotionTask
                        pendingPromotionItem = nil
                        pendingPromotionTask = nil
                        selectedAssigneeIdForPromotion = nil
                        if let item {
                            completePromotion(of: item, assigneeId: assigneeId)
                        } else if let task {
                            completePromotion(of: task, assigneeId: assigneeId)
                        }
                    }
                )
            }
        }
        .sheet(
            isPresented: Binding(
                get: { pendingAssignmentItem != nil || pendingAssignmentTask != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingAssignmentItem = nil
                        pendingAssignmentTask = nil
                        selectedAssigneeIdForAssignment = nil
                    }
                }
            )
        ) {
            BacklogAssigneePickerSheet(
                title: "Assign owner",
                actionTitle: "Save",
                members: activeMembers,
                autoConfirmOnSelection: true,
                selectedAssigneeId: $selectedAssigneeIdForAssignment,
                onCancel: {
                    pendingAssignmentItem = nil
                    pendingAssignmentTask = nil
                    selectedAssigneeIdForAssignment = nil
                },
                onConfirm: {
                    guard let selectedAssignee = selectedAssigneeIdForAssignment else { return }
                    let item = pendingAssignmentItem
                    let task = pendingAssignmentTask
                    pendingAssignmentItem = nil
                    pendingAssignmentTask = nil
                    selectedAssigneeIdForAssignment = nil
                    _ = _Concurrency.Task {
                        if let item {
                            await store.updateItem(
                                item,
                                title: item.title,
                                notes: item.notes,
                                assigneeId: selectedAssignee
                            )
                        } else if let task {
                            await updateBacklogTaskAssignment(task, assigneeId: selectedAssignee)
                        }
                    }
                }
            )
        }
        .sheet(item: $editingItem) { item in
            BacklogItemEditSheet(
                item: item,
                members: activeMembers,
                onSave: { title, notes, assigneeId in
                    _ = _Concurrency.Task {
                        await store.updateItem(
                            item,
                            title: title,
                            notes: notes,
                            assigneeId: assigneeId
                        )
                    }
                },
                onDelete: {
                    queueDeleteItem(item)
                }
            )
        }
        .overlay(alignment: .bottom) {
            if let deletionTitle = pendingDeletionTitle {
                ToastView(
                    message: "\"\(deletionTitle)\" deleted",
                    actionTitle: "Undo",
                    action: undoPendingDeleteItem
                )
                .padding(.horizontal, ToastView.Metrics.horizontalInset)
                .padding(.bottom, AppChromeMetrics.compactCTAHeight + 22)
                .transition(ToastView.AnimationTokens.transition)
                .id(pendingDeletionID)
            }
        }
        .animation(ToastView.AnimationTokens.curve, value: pendingDeletionID)
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

    private func assignee(for assigneeId: UUID?) -> Member? {
        guard let assigneeId else { return nil }
        return activeMembers.first(where: { $0.id == assigneeId })
    }

    private var allBacklogTasks: [Task] {
        taskStore.backlogTasks
            .sorted { lhs, rhs in
                let lhsDue = lhs.dueDate ?? .distantFuture
                let rhsDue = rhs.dueDate ?? .distantFuture
                if lhsDue != rhsDue {
                    return lhsDue < rhsDue
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private var allVisibleBacklogTasks: [Task] {
        allBacklogTasks.filter {
            !hiddenPendingDeleteIds.contains($0.id) &&
                !hiddenPendingPromotionIds.contains($0.id)
        }
    }

    private var uncategorizedBacklogTasks: [Task] {
        allVisibleBacklogTasks.filter { task in
            guard let categoryId = task.backlogCategoryId else { return true }
            return !store.categories.contains(where: { $0.id == categoryId })
        }
    }

    private var pendingDeletionTitle: String? {
        pendingDeletionItem?.title ?? pendingDeletionTask?.title
    }

    private var pendingDeletionID: UUID? {
        pendingDeletionItem?.id ?? pendingDeletionTask?.id
    }

    private func visibleBacklogTasks(for categoryId: UUID) -> [Task] {
        allVisibleBacklogTasks.filter { $0.backlogCategoryId == categoryId }
    }

    private var header: some View {
        AppScreenHeader(title: "Ideas", trailing: {
            Button {
                newCategoryColorHex = MemberColorToken.randomHex()
                isAddingCategory = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(themeStore.accentTabColor)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("backlogAddCategoryButton")
        })
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Create a Category First", systemImage: "folder.badge.plus")
        } description: {
            Text(
                "Ideas are organized into categories like Home, Errands, or Wishlist. Add a category first, then start collecting ideas inside it."
            )
        } actions: {
            Button("Add Category") {
                HapticManager.lightTap()
                newCategoryColorHex = MemberColorToken.randomHex()
                isAddingCategory = true
                hasSeenIdeasTutorial = true
            }
            .buttonStyle(.borderedProminent)
            .tint(themeStore.accentTabColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: -40)
    }

    private func markIdeasTutorialAsSeenIfNeeded() {
        guard !store.categories.isEmpty || !allVisibleBacklogTasks.isEmpty, !hasSeenIdeasTutorial else { return }
        hasSeenIdeasTutorial = true
    }

    private func queueAssignItem(_ item: BacklogItem) {
        guard !activeMembers.isEmpty else {
            showBanner(.failed("No members available to assign."))
            return
        }

        pendingAssignmentTask = nil
        pendingAssignmentItem = item
        selectedAssigneeIdForAssignment = item.assigneeId ?? currentMember?.id ?? activeMembers.first?.id
    }

    private func queueAssignTask(_ task: Task) {
        guard !activeMembers.isEmpty else {
            showBanner(.failed("No members available to assign."))
            return
        }

        pendingAssignmentItem = nil
        pendingAssignmentTask = task
        selectedAssigneeIdForAssignment = task.assigneeId ?? currentMember?.id ?? activeMembers.first?.id
    }

    private func promoteItem(_ item: BacklogItem) {
        guard processingPromotionEntryIds.insert(item.id).inserted else { return }

        if activeMembers.isEmpty {
            if let userId = userSession.userId, let assigneeId = UUID(uuidString: userId) {
                completePromotion(of: item, assigneeId: assigneeId)
            } else {
                processingPromotionEntryIds.remove(item.id)
                showBanner(.assigneeRequired)
            }
            return
        }

        if let assignedId = item.assigneeId {
            completePromotion(of: item, assigneeId: assignedId)
            return
        }

        if activeMembers.count == 1, let assigneeId = activeMembers.first?.id {
            completePromotion(of: item, assigneeId: assigneeId)
            return
        }

        pendingPromotionItem = item
        pendingPromotionTask = nil
        selectedAssigneeIdForPromotion = currentMember?.id
    }

    private func completePromotion(of item: BacklogItem, assigneeId: UUID) {
        if !processingPromotionEntryIds.contains(item.id) {
            processingPromotionEntryIds.insert(item.id)
        }
        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
            hiddenPendingPromotionIds.insert(item.id)
        }

        _ = _Concurrency.Task {
            let result = await store.promoteItemToTask(item, assigneeId: assigneeId)
            await MainActor.run {
                processingPromotionEntryIds.remove(item.id)
                switch result {
                case .success:
                    hiddenPendingPromotionIds.remove(item.id)
                case .assigneeRequired, .wipLimitReached, .failed:
                    withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                        hiddenPendingPromotionIds.remove(item.id)
                    }
                }
                handlePromotionResult(result)
            }
        }
    }

    private func promoteTask(_ task: Task) {
        guard processingPromotionEntryIds.insert(task.id).inserted else { return }

        if task.taskType == .recurring, task.assigneeId == nil {
            processingPromotionEntryIds.remove(task.id)
            showBanner(.assigneeRequired)
            return
        }

        if activeMembers.isEmpty {
            if let userId = userSession.userId, let assigneeId = UUID(uuidString: userId) {
                completePromotion(of: task, assigneeId: assigneeId)
            } else {
                processingPromotionEntryIds.remove(task.id)
                showBanner(.assigneeRequired)
            }
            return
        }

        if let assigneeId = task.assigneeId {
            completePromotion(of: task, assigneeId: assigneeId)
            return
        }

        if activeMembers.count == 1, let assigneeId = activeMembers.first?.id {
            completePromotion(of: task, assigneeId: assigneeId)
            return
        }

        pendingPromotionItem = nil
        pendingPromotionTask = task
        selectedAssigneeIdForPromotion = currentMember?.id ?? activeMembers.first?.id
    }

    private func completePromotion(of task: Task, assigneeId: UUID) {
        if !processingPromotionEntryIds.contains(task.id) {
            processingPromotionEntryIds.insert(task.id)
        }
        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
            hiddenPendingPromotionIds.insert(task.id)
        }

        _ = _Concurrency.Task {
            var updatedTask = task
            let resolvedAssigneeIds = task.assigneeIds.isEmpty
                ? [assigneeId]
                : Array(task.assigneeIds + [assigneeId]).removingDuplicates()
            updatedTask.assigneeId = assigneeId
            updatedTask.assigneeIds = resolvedAssigneeIds
            let validation = await taskStore.moveTask(updatedTask, to: .next)

            await MainActor.run {
                processingPromotionEntryIds.remove(task.id)
                switch validation {
                case .ok:
                    hiddenPendingPromotionIds.remove(task.id)
                    activeBanner = nil
                    HapticManager.success()
                case .assigneeRequired:
                    withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                        hiddenPendingPromotionIds.remove(task.id)
                    }
                    HapticManager.warning()
                    showBanner(.assigneeRequired)
                case let .wipLimitReached(current, limit):
                    withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                        hiddenPendingPromotionIds.remove(task.id)
                    }
                    HapticManager.warning()
                    showBanner(.wipLimitReached(current: current, limit: limit))
                }
            }
        }
    }

    private func cancelPendingPromotion() {
        if let item = pendingPromotionItem {
            processingPromotionEntryIds.remove(item.id)
        }
        if let task = pendingPromotionTask {
            processingPromotionEntryIds.remove(task.id)
        }
        pendingPromotionItem = nil
        pendingPromotionTask = nil
        selectedAssigneeIdForPromotion = nil
    }

    private func handlePromotionResult(_ result: BacklogStore.PromotionResult) {
        switch result {
        case .success:
            activeBanner = nil
            HapticManager.success()
        case .assigneeRequired:
            HapticManager.warning()
            showBanner(.assigneeRequired)
        case let .wipLimitReached(current, limit):
            HapticManager.warning()
            showBanner(.wipLimitReached(current: current, limit: limit))
        case let .failed(message):
            HapticManager.warning()
            showBanner(.failed(message))
        }
    }

    private func showBanner(_ banner: PromotionBanner) {
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

    private func activateComposer(for categoryId: UUID, scrollProxy: ScrollViewProxy) {
        activeComposerCategoryId = categoryId
        composerText = ""
        focusedComposerCategoryId = nil

        withAnimation(WowAnimation.easeOut) {
            scrollProxy.scrollTo(categoryId, anchor: .bottom)
        }

        scheduleComposerFocus(for: categoryId)
    }

    private func submitComposer(for categoryId: UUID) {
        guard activeComposerCategoryId == categoryId else { return }
        let trimmedText = composerText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            clearComposerState()
            return
        }

        HapticManager.lightTap()
        _ = _Concurrency.Task {
            await store.addItem(to: categoryId, title: trimmedText)
        }
        clearComposerState()
    }

    private func cancelComposer(for categoryId: UUID) {
        guard activeComposerCategoryId == categoryId else { return }
        clearComposerState()
    }

    private func clearComposerState() {
        focusedComposerCategoryId = nil
        activeComposerCategoryId = nil
        composerText = ""
    }

    private func scheduleComposerFocus(for categoryId: UUID) {
        // Keyboard + layout updates can race each other in scroll containers.
        // Retry focus a few times to keep the composer deterministic.
        for attempt in 0 ..< 4 {
            let delay = 0.03 + (Double(attempt) * 0.05)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard activeComposerCategoryId == categoryId else { return }
                focusedComposerCategoryId = categoryId
            }
        }
    }

    private func visibleItems(for categoryId: UUID) -> [BacklogItem] {
        store.items(for: categoryId)
            .filter {
                !hiddenPendingDeleteIds.contains($0.id) &&
                    !hiddenPendingPromotionIds.contains($0.id)
            }
    }

    private func handleCategoryDeletionResult(_ result: BacklogStore.CategoryDeletionResult) {
        switch result {
        case .deleted:
            activeBanner = nil
        case let .blockedByBacklogTasks(count):
            showBanner(.failed("Move or delete \(count) backlog task\(count == 1 ? "" : "s") before deleting this category."))
        case let .failed(message):
            showBanner(.failed(message))
        }
    }

    private func updateBacklogTaskAssignment(_ task: Task, assigneeId: UUID) async {
        if task.taskType == .recurring,
           let recurringChoreId = task.recurringChoreId
        {
            let recurringStore = RecurringChoreStore(
                householdId: householdId,
                modelContext: modelContext
            )
            recurringStore.setSyncMode(userSession.syncMode)
            await recurringStore.loadChores()

            if var recurringChore = recurringStore.chores.first(where: { $0.id == recurringChoreId }) {
                recurringChore.defaultAssigneeIds = [assigneeId]
                recurringChore.assigneeIds = [assigneeId]
                recurringChore.rotationEnabled = false
                recurringChore.nextAssigneeIndex = 0
                recurringChore.updatedAt = Date()
                await recurringStore.updateChore(recurringChore)
                return
            }
        }

        var updatedTask = task
        updatedTask.assigneeId = assigneeId
        updatedTask.assigneeIds = task.assigneeIds.isEmpty
            ? [assigneeId]
            : Array(task.assigneeIds + [assigneeId]).removingDuplicates()
        _ = await taskStore.updateTask(updatedTask)
    }

    private func queueDeleteItem(_ item: BacklogItem) {
        if let previous = pendingDeletionItem {
            deletionTask?.cancel()
            deletionTask = nil
            withAnimation(ToastView.AnimationTokens.curve) {
                pendingDeletionItem = nil
                pendingDeletionTask = nil
                hiddenPendingDeleteIds.remove(previous.id)
            }

            _ = _Concurrency.Task {
                _ = await store.deleteItem(previous)
            }
        } else if let previousTask = pendingDeletionTask {
            deletionTask?.cancel()
            deletionTask = nil
            withAnimation(ToastView.AnimationTokens.curve) {
                pendingDeletionTask = nil
                hiddenPendingDeleteIds.remove(previousTask.id)
            }

            _ = _Concurrency.Task {
                await taskStore.deleteTask(previousTask)
            }
        }

        withAnimation(ToastView.AnimationTokens.curve) {
            pendingDeletionItem = item
            pendingDeletionTask = nil
            hiddenPendingDeleteIds.insert(item.id)
        }
        HapticManager.lightTap()

        deletionTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(5))
            guard !_Concurrency.Task.isCancelled else { return }
            _ = await store.deleteItem(item)
            await MainActor.run {
                withAnimation(ToastView.AnimationTokens.curve) {
                    if pendingDeletionItem?.id == item.id {
                        pendingDeletionItem = nil
                    }
                    if pendingDeletionTask?.id == item.id {
                        pendingDeletionTask = nil
                    }
                    hiddenPendingDeleteIds.remove(item.id)
                }
                deletionTask = nil
            }
        }
    }

    private func queueDeleteTask(_ task: Task) {
        if let previous = pendingDeletionItem {
            deletionTask?.cancel()
            deletionTask = nil
            withAnimation(ToastView.AnimationTokens.curve) {
                pendingDeletionItem = nil
                hiddenPendingDeleteIds.remove(previous.id)
            }

            _ = _Concurrency.Task {
                _ = await store.deleteItem(previous)
            }
        } else if let previousTask = pendingDeletionTask {
            deletionTask?.cancel()
            deletionTask = nil
            withAnimation(ToastView.AnimationTokens.curve) {
                pendingDeletionTask = nil
                hiddenPendingDeleteIds.remove(previousTask.id)
            }

            _ = _Concurrency.Task {
                await taskStore.deleteTask(previousTask)
            }
        }

        withAnimation(ToastView.AnimationTokens.curve) {
            pendingDeletionItem = nil
            pendingDeletionTask = task
            hiddenPendingDeleteIds.insert(task.id)
        }
        HapticManager.lightTap()

        deletionTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(5))
            guard !_Concurrency.Task.isCancelled else { return }
            await taskStore.deleteTask(task)
            await MainActor.run {
                withAnimation(ToastView.AnimationTokens.curve) {
                    if pendingDeletionTask?.id == task.id {
                        pendingDeletionTask = nil
                    }
                    hiddenPendingDeleteIds.remove(task.id)
                }
                deletionTask = nil
            }
        }
    }

    private func undoPendingDeleteItem() {
        guard pendingDeletionID != nil else { return }
        deletionTask?.cancel()
        deletionTask = nil
        withAnimation(ToastView.AnimationTokens.curve) {
            if let pendingDeletionItem {
                hiddenPendingDeleteIds.remove(pendingDeletionItem.id)
            }
            if let pendingDeletionTask {
                hiddenPendingDeleteIds.remove(pendingDeletionTask.id)
            }
            pendingDeletionItem = nil
            pendingDeletionTask = nil
        }
        HapticManager.lightTap()
    }
}

private struct BacklogStatusBanner: View {
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

// MARK: - Category Card

struct CategoryCard: View {
    let category: BacklogCategory
    let items: [BacklogItem]
    let backlogTasks: [Task]
    let isPromotingEntry: (UUID) -> Bool
    let assigneeFor: (UUID?) -> Member?
    let isAddingItem: Bool
    @Binding var newItemText: String
    let focusedComposerCategoryId: FocusState<UUID?>.Binding
    let onActivateComposer: () -> Void
    let onSubmitItem: () -> Void
    let onCancelItem: () -> Void
    let onDeleteItem: (BacklogItem) -> Void
    let onDeleteTask: (Task) -> Void
    let onEditItem: (BacklogItem) -> Void
    let onAssignItem: (BacklogItem) -> Void
    let onAssignTask: (Task) -> Void
    let onPromoteItem: (BacklogItem) -> Void
    let onPromoteTask: (Task) -> Void
    let onEditCategory: () -> Void
    let onDeleteCategory: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(category.color)
                        .frame(width: 10, height: 10)

                    Text(category.title.uppercased())
                        .font(themeStore.font(for: .sectionHeader))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }

                Spacer()

                Menu {
                    Button {
                        onEditCategory()
                    } label: {
                        Label("Edit Category", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        if items.isEmpty, backlogTasks.isEmpty {
                            onDeleteCategory()
                        } else {
                            HapticManager.warning()
                            showDeleteConfirmation = true
                        }
                    } label: {
                        Label("Delete Category", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .accessibilityIdentifier("backlogCategoryHeader_\(category.title)")

            VStack(spacing: 6) {
                ForEach(backlogTasks) { task in
                    let canPromote = task.assigneeId != nil
                    let isPromoting = isPromotingEntry(task.id)
                    BacklogTaskRow(
                        task: task,
                        assignee: assigneeFor(task.assigneeId),
                        canPromote: canPromote,
                        isPromotionDisabled: isPromoting,
                        onAssign: { onAssignTask(task) },
                        onPromote: { onPromoteTask(task) },
                        onDelete: { onDeleteTask(task) }
                    )
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if canPromote {
                            Button {
                                onPromoteTask(task)
                            } label: {
                                Label("Promote", systemImage: "arrow.up.circle")
                            }
                            .tint(.blue)
                            .disabled(isPromoting)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDeleteTask(task)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                ForEach(items) { item in
                    let canPromote = item.assigneeId != nil
                    let isPromoting = isPromotingEntry(item.id)
                    BacklogItemRow(
                        item: item,
                        assignee: assigneeFor(item.assigneeId),
                        canPromote: canPromote,
                        isPromotionDisabled: isPromoting,
                        onTap: { onEditItem(item) },
                        onAssign: { onAssignItem(item) },
                        onPromote: { onPromoteItem(item) },
                        onDelete: { onDeleteItem(item) }
                    )
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if canPromote {
                            Button {
                                onPromoteItem(item)
                            } label: {
                                Label("Promote", systemImage: "arrow.up.circle")
                            }
                            .tint(.blue)
                            .disabled(isPromoting)
                        }
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

            if isAddingItem {
                HStack(spacing: 10) {
                    composerPlaceholderIcon

                    TextField(
                        "",
                        text: $newItemText,
                        prompt: Text("Add item").font(themeStore.font(for: .listRowTitle))
                    )
                    .font(themeStore.font(for: .listRowTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                    .focused(focusedComposerCategoryId, equals: category.id)
                    .onSubmit {
                        onSubmitItem()
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            focusedComposerCategoryId.wrappedValue = category.id
                        }
                    }
                    .submitLabel(.done)
                    .autocorrectionDisabled()

                    Button {
                        onCancelItem()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(themeStore.contentSecondaryColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else {
                Button {
                    onActivateComposer()
                } label: {
                    HStack(spacing: 10) {
                        addItemPlaceholderIcon

                        Text("Add item")
                            .font(themeStore.font(for: .buttonLabel))
                            .foregroundStyle(themeStore.accentTabColor)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("backlogAddItemButton_\(category.title)")
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(cardBorder, lineWidth: colorScheme == .light ? 1 : 0)
                }
                .shadow(
                    color: colorScheme == .light
                        ? themeStore.borderLightColor.opacity(0.35) : .clear,
                    radius: colorScheme == .light ? 6 : 0,
                    x: 0,
                    y: colorScheme == .light ? 2 : 0
                )
        }
        .sheet(isPresented: $showDeleteConfirmation) {
            AppConfirmationSheet(
                title: "Delete \"\(category.title)\"?",
                message: "This will permanently delete the category and all of its ideas.",
                primaryTitle: deleteCategoryPrimaryTitle,
                primaryStyle: .destructive,
                onPrimary: {
                    withAnimation(WowAnimation.easeOut) {
                        onDeleteCategory()
                    }
                }
            )
        }
    }

    private var deleteCategoryPrimaryTitle: String {
        let totalEntries = items.count + backlogTasks.count
        let itemLabel = totalEntries == 1 ? "Entry" : "Entries"
        return "Delete Category and \(totalEntries) \(itemLabel)"
    }

    private var cardBackground: Color {
        themeStore.surfaceColor
    }

    private var cardBorder: Color {
        colorScheme == .light ? themeStore.borderLightColor : .clear
    }

    @ViewBuilder
    private var composerPlaceholderIcon: some View {
        if themeStore.preset == .retro {
            Rectangle()
                .stroke(Color(hex: "F7D51D"), lineWidth: 2.2)
                .frame(width: 20, height: 20)
                .overlay {
                    Rectangle()
                        .stroke(Color.black.opacity(0.75), lineWidth: 1)
                        .padding(0.8)
                }
        } else {
            Circle()
                .stroke(themeStore.checkboxEmptyColor, lineWidth: 1.5)
                .frame(width: 20, height: 20)
        }
    }

    @ViewBuilder
    private var addItemPlaceholderIcon: some View {
        if themeStore.preset == .retro {
            Rectangle()
                .stroke(themeStore.accentTabColor.opacity(0.9), lineWidth: 2.2)
                .frame(width: 20, height: 20)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(themeStore.accentTabColor)
                }
        } else {
            Circle()
                .stroke(themeStore.accentTabColor.opacity(0.55), lineWidth: 1.5)
                .frame(width: 20, height: 20)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(themeStore.accentTabColor)
                }
        }
    }
}

// MARK: - Backlog Item Row

private struct UncategorizedBacklogTasksCard: View {
    let tasks: [Task]
    let isPromotingTask: (UUID) -> Bool
    let assigneeFor: (UUID?) -> Member?
    let onAssignTask: (Task) -> Void
    let onPromoteTask: (Task) -> Void
    let onDeleteTask: (Task) -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(themeStore.contentSecondaryColor)

                Text("UNCATEGORIZED")
                    .font(themeStore.font(for: .sectionHeader))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 6) {
                ForEach(tasks) { task in
                    BacklogTaskRow(
                        task: task,
                        assignee: assigneeFor(task.assigneeId),
                        canPromote: task.assigneeId != nil,
                        isPromotionDisabled: isPromotingTask(task.id),
                        onAssign: { onAssignTask(task) },
                        onPromote: { onPromoteTask(task) },
                        onDelete: { onDeleteTask(task) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(themeStore.surfaceColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            colorScheme == .light ? themeStore.borderLightColor : .clear,
                            lineWidth: colorScheme == .light ? 1 : 0
                        )
                }
        }
    }
}

private struct BacklogTaskRow: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let task: Task
    let assignee: Member?
    let canPromote: Bool
    let isPromotionDisabled: Bool
    let onAssign: () -> Void
    let onPromote: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(themeStore.font(for: .listRowTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if let dueDate = task.dueDate {
                        Text(dueDate, style: .date)
                            .font(themeStore.font(for: .chip))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                    }

                    if let assignee {
                        MemberBadgeView(
                            name: assignee.displayName,
                            colorHex: assignee.colorHex
                        )
                    }

                    if task.taskType == .recurring {
                        RecurringIndicatorView()
                    }
                }
            }

            Spacer()

            HStack(spacing: 16) {
                if task.taskType != .recurring || task.assigneeId == nil {
                    Button(action: onAssign) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 14))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }

                if canPromote {
                    Button(action: onPromote) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPromotionDisabled)
                    .opacity(isPromotionDisabled ? 0.45 : 1)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : .white)
        }
        .animation(.easeInOut(duration: 0.2), value: canPromote)
    }
}

struct BacklogItemRow: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let item: BacklogItem
    let assignee: Member?
    let canPromote: Bool
    let isPromotionDisabled: Bool
    let onTap: () -> Void
    let onAssign: () -> Void
    let onPromote: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(themeStore.font(for: .listRowTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                    .strikethrough(false)

                if let assignee {
                    MemberBadgeView(
                        name: assignee.displayName,
                        colorHex: assignee.colorHex,
                        displayStyle: .compact
                    )
                }
            }

            Spacer()

            HStack(spacing: 16) {
                Button(action: onAssign) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                if canPromote {
                    Button(action: onPromote) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPromotionDisabled)
                    .opacity(isPromotionDisabled ? 0.45 : 1)
                    .transition(.opacity.combined(with: .scale))
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : .white)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .animation(.easeInOut(duration: 0.2), value: canPromote)
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

#Preview {
    BacklogView()
        .environmentObject(UserSession.shared)
        .environmentObject(ThemeStore())
}

// swiftlint:enable file_length
