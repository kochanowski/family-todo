import SwiftData
import SwiftUI

// swiftlint:disable file_length type_body_length

/// Backlog screen - long-term storage for ideas and projects, organized by categories
struct BacklogView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext
    @Binding private var selectedTab: AppTab

    init(selectedTab: Binding<AppTab> = .constant(.backlog)) {
        _selectedTab = selectedTab
    }

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                BacklogContent(
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

private struct BacklogContent: View {
    private enum PromotionBanner: Equatable {
        case assigneeRequired
        case wipLimitReached(current: Int, limit: Int)
        case failed(String)

        var text: String {
            switch self {
            case .assigneeRequired:
                "Assign this item before moving it to Tasks/NEXT."
            case let .wipLimitReached(current, limit):
                "WIP limit reached (\(current)/\(limit)). Complete one active task first."
            case let .failed(message):
                message
            }
        }
    }

    private enum DeleteConfirmationTarget: Equatable {
        case item(UUID)
        case category(UUID)
    }

    @StateObject private var store: BacklogStore
    @StateObject private var memberStore: MemberStore
    @StateObject private var recurringStore: RecurringChoreStore
    private let householdId: UUID
    private let modelContext: ModelContext
    @Binding private var selectedTab: AppTab
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var syncCoordinator: HouseholdSyncCoordinator
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager
    @EnvironmentObject private var premiumSubscriptionManager: SubscriptionManager

    @State private var isAddingCategory = false
    @State private var isShowingRecurringChores = false
    @State private var newCategoryName = ""
    @State private var newCategoryColorHex = MemberColorToken.randomHex()
    @State private var activeBanner: PromotionBanner?
    @State private var pendingPromotionItemID: UUID?
    @State private var selectedAssigneeIdForPromotion: UUID?
    @State private var pendingAssignmentItemID: UUID?
    @State private var selectedAssigneeIdForAssignment: UUID?
    @State private var editingCategory: BacklogCategory?
    @State private var editingItemID: UUID?
    @State private var activeComposerCategoryId: UUID?
    @State private var composerText = ""
    @State private var pendingDeleteConfirmationTarget: DeleteConfirmationTarget?
    @State private var categoryDeletionBlockReason: BacklogStore.CategoryDeletionBlockReason?
    @State private var pendingDeletionItem: BacklogItem?
    @State private var deletionTask: _Concurrency.Task<Void, Never>?
    @State private var remoteHighlightedItemIDs: Set<UUID> = []
    @State private var remoteHighlightedCategoryIDs: Set<UUID> = []
    @State private var lastProcessedRemoteAnimationBatchToken: UUID?
    @State private var isApplyingRemoteSyncAnimation = false
    @State private var remoteSyncResetTask: _Concurrency.Task<Void, Never>?
    @State private var hiddenPendingDeleteIds: Set<UUID> = []
    @State private var hiddenPendingPromotionIds: Set<UUID> = []
    @State private var armedPromotionTipItemID: UUID?
    @State private var suppressPromotionTipUntil = Date.distantPast
    @State private var hasStartedInitialLoad = false
    @FocusState private var focusedComposerCategoryId: UUID?
    @AppStorage(AppTipProgressKey.ideasTutorialSeen) private var hasSeenIdeasTutorial = false
    @AppStorage(AppTipProgressKey.ideasAddIdeaCompleted)
    private var hasCompletedIdeasAddIdeaTip = false
    @AppStorage(AppTipProgressKey.ideasAssignOwnerCompleted)
    private var hasCompletedIdeasAssignOwnerTip = false
    @AppStorage(AppTipProgressKey.ideasPromoteCompleted)
    private var hasCompletedIdeasPromoteTip = false
    @AppStorage(AppTipProgressKey.ideasRecurringChoresCompleted)
    private var hasCompletedIdeasRecurringChoresTip = false
    @AppStorage(AppTips.runtimeGenerationDefaultsKey)
    private var appTipRuntimeGeneration = 0

    init(householdId: UUID, modelContext: ModelContext, selectedTab: Binding<AppTab>) {
        self.householdId = householdId
        self.modelContext = modelContext
        _store = StateObject(
            wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext)
        )
        _memberStore = StateObject(
            wrappedValue: MemberStore(householdId: householdId, modelContext: modelContext)
        )
        _recurringStore = StateObject(
            wrappedValue: RecurringChoreStore(householdId: householdId, modelContext: modelContext)
        )
        _selectedTab = selectedTab
    }

    var body: some View {
        screenContent
    }

    private var screenContent: some View {
        sheetPresentationContent
            .appAdaptiveWidth(
                maxWidth: AppChromeMetrics.regularContentMaxWidth,
                alignment: .topLeading
            )
            .alert(
                deleteConfirmationTitle,
                isPresented: Binding(
                    get: { pendingDeleteConfirmationTarget != nil },
                    set: { if !$0 { pendingDeleteConfirmationTarget = nil } }
                ),
                presenting: pendingDeleteConfirmationTarget
            ) { target in
                Button(deleteConfirmationPrimaryTitle(for: target), role: .destructive) {
                    confirmDeletion(target)
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteConfirmationTarget = nil
                }
            } message: { target in
                Text(deleteConfirmationMessage(for: target))
            }
            .background {
                Color.clear
                    .alert(
                        "Cannot delete category.",
                        isPresented: Binding(
                            get: { categoryDeletionBlockReason != nil },
                            set: { if !$0 { categoryDeletionBlockReason = nil } }
                        )
                    ) {
                        Button("OK", role: .cancel) {
                            categoryDeletionBlockReason = nil
                        }
                    } message: {
                        Text(categoryDeletionBlockReason?.alertDetail ?? "")
                    }
            }
            .overlay(alignment: .bottom) {
                if let pendingDeletionItem {
                    ToastView(
                        message: "\"\(pendingDeletionItem.title)\" deleted",
                        actionTitle: "Undo",
                        action: undoPendingDeleteItem
                    )
                    .padding(.horizontal, ToastView.Metrics.horizontalInset)
                    .padding(.bottom, AppChromeMetrics.compactCTAHeight + 22)
                    .transition(ToastView.AnimationTokens.transition)
                    .id(pendingDeletionItem.id)
                }
            }
            .animation(ToastView.AnimationTokens.curve, value: pendingDeletionItem?.id)
    }

    private var sheetPresentationContent: some View {
        syncReactiveContent
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
                        _ = _Concurrency.Task {
                            let previousCategoryCount = store.categories.count
                            let result = await store.addCategory(
                                name,
                                colorHex: colorHex,
                                isPremium: premiumSubscriptionManager.isPremium
                            )
                            await MainActor.run {
                                switch result {
                                case .created where store.categories.count > previousCategoryCount:
                                    AppTips.donateIdeasCategoryCreated()
                                case let .blocked(feature):
                                    premiumSubscriptionManager.presentUpsell(UpsellContext(feature: feature))
                                case .created, .ignored:
                                    break
                                }
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingRecurringChores) {
                RecurringChoresView(
                    store: recurringStore,
                    householdId: householdId,
                    modelContext: modelContext,
                    syncMode: userSession.syncMode,
                    categories: store.categories,
                    members: activeMembers
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
                    get: { pendingPromotionItemID != nil },
                    set: { isPresented in
                        if !isPresented {
                            cancelPendingPromotion()
                        }
                    }
                )
            ) {
                if let pendingPromotionItem = currentPendingPromotionItem {
                    BacklogAssigneePickerSheet(
                        title: "Assign before start",
                        actionTitle: "Promote",
                        members: activeMembers,
                        autoConfirmOnSelection: false,
                        showsUnassignedOption: false,
                        selectedAssigneeId: $selectedAssigneeIdForPromotion,
                        onCancel: {
                            cancelPendingPromotion()
                        },
                        onConfirm: {
                            guard let assigneeId = selectedAssigneeIdForPromotion else { return }
                            let itemID = pendingPromotionItem.id
                            pendingPromotionItemID = nil
                            selectedAssigneeIdForPromotion = nil
                            completePromotion(of: itemID, assigneeId: assigneeId)
                        }
                    )
                    .id(pendingPromotionItem.id)
                } else {
                    Color.clear
                        .presentationDetents([.height(1)])
                        .onAppear {
                            cancelPendingPromotion()
                        }
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { pendingAssignmentItemID != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingAssignmentItemID = nil
                            selectedAssigneeIdForAssignment = nil
                        }
                    }
                )
            ) {
                if let pendingAssignmentItem = currentPendingAssignmentItem {
                    BacklogAssigneePickerSheet(
                        title: "Assign owner",
                        actionTitle: "Save",
                        members: activeMembers,
                        autoConfirmOnSelection: true,
                        showsUnassignedOption: true,
                        selectedAssigneeId: $selectedAssigneeIdForAssignment,
                        onCancel: {
                            pendingAssignmentItemID = nil
                            selectedAssigneeIdForAssignment = nil
                        },
                        onConfirm: {
                            guard let item = currentPendingAssignmentItem else { return }
                            let selectedAssignee = selectedAssigneeIdForAssignment
                            let hadAssignee = item.assigneeId != nil
                            let pendingItemID = item.id
                            pendingAssignmentItemID = nil
                            selectedAssigneeIdForAssignment = nil
                            store.updateItem(
                                item,
                                title: item.title,
                                notes: item.notes,
                                assigneeId: selectedAssignee
                            )
                            guard !hadAssignee else { return }
                            if let updatedItem = store.items.first(where: { $0.id == pendingItemID }),
                               updatedItem.assigneeId != nil
                            {
                                AppTips.donateIdeasOwnerAssigned()
                                armPromotionTip(for: updatedItem.id)
                            }
                        }
                    )
                    .id(pendingAssignmentItem.id)
                } else {
                    Color.clear
                        .presentationDetents([.height(1)])
                        .onAppear {
                            pendingAssignmentItemID = nil
                            selectedAssigneeIdForAssignment = nil
                        }
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { editingItemID != nil },
                    set: { isPresented in
                        if !isPresented {
                            editingItemID = nil
                        }
                    }
                )
            ) {
                if let item = currentEditingItem {
                    BacklogItemEditSheet(
                        item: item,
                        members: activeMembers,
                        onSave: { title, notes, assigneeId in
                            let hadAssignee = item.assigneeId != nil
                            store.updateItem(
                                item,
                                title: title,
                                notes: notes,
                                assigneeId: assigneeId
                            )
                            if !hadAssignee,
                               let updatedItem = latestItem(withID: item.id),
                               updatedItem.assigneeId != nil
                            {
                                AppTips.donateIdeasOwnerAssigned()
                                armPromotionTip(for: updatedItem.id)
                            }
                        },
                        onDelete: {
                            performImmediateDeleteItem(withID: item.id)
                        }
                    )
                    .id(item.id)
                } else {
                    Color.clear
                        .presentationDetents([.height(1)])
                        .onAppear {
                            editingItemID = nil
                        }
                }
            }
    }

    private var syncReactiveContent: some View {
        layoutContent
            .onReceive(NotificationCenter.default.publisher(for: .backlogDataDidChange)) { notification in
                store.markLocalSnapshotStale()
                if selectedNotificationIsLocal(notification) {
                    store.rehydrateVisibleSnapshotFromCache()
                    // Un-suppress items that have returned to Ideas via demotion.
                    // subtract(_:) removes IDs that ARE in the store — keeping promoted-item
                    // suppressions intact for IDs no longer present locally.
                    let activeItemIds = Set(store.items.map(\.id))
                    hiddenPendingPromotionIds.subtract(activeItemIds)
                    syncPromotionTipAnchorWithVisibleItems()
                    markIdeasTutorialAsSeenIfNeeded()
                } else {
                    store.replayPendingMutationsIfNeeded()
                }
            }
            .onChange(of: syncCoordinator.latestBatch?.id) { _, _ in
                guard let batch = syncCoordinator.latestBatch,
                      !batch.domains.isDisjoint(with: [.ideas, .backlog, .members, .tasks])
                else {
                    return
                }

                store.markLocalSnapshotStale()
                if selectedTab == .backlog {
                    handleRemoteBacklogSyncBatch(batch)
                } else {
                    store.rehydrateVisibleSnapshotFromCache()
                    store.replayPendingMutationsIfNeeded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .memberProfileDidChange)) { notification in
                memberStore.markLocalSnapshotStale()
                if selectedNotificationIsLocal(notification) {
                    memberStore.rehydrateVisibleSnapshotFromCache()
                } else if selectedTab == .backlog {
                    _ = _Concurrency.Task {
                        await memberStore.loadMembersForDisplay()
                    }
                }
            }
            .onDisappear {
                cancelRemoteSyncAnimationReset()
            }
    }

    private var layoutContent: some View {
        let listBottomInset: CGFloat = 16

        return VStack(spacing: 0) {
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

            if store.categories.isEmpty {
                if store.hasHydratedLocalSnapshot {
                    emptyState
                        .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                        .padding(.bottom, listBottomInset)
                } else {
                    backlogLoadingState
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 40)
                }
            } else {
                BacklogCategoryListSection(
                    categories: store.categories,
                    listBottomInset: listBottomInset,
                    visibleItems: visibleItems(for:),
                    highlightedItemIDs: remoteHighlightedItemIDs,
                    highlightedCategoryIDs: remoteHighlightedCategoryIDs,
                    isApplyingRemoteSyncAnimation: isApplyingRemoteSyncAnimation,
                    appTipRuntimeGeneration: appTipRuntimeGeneration,
                    addIdeaTipCategoryID: addIdeaTipAnchorCategoryID,
                    ideaAssignTipItemID: ideaAssignTipAnchorItemID,
                    ideaPromotionTipItemID: ideaPromotionTipItemID,
                    hiddenPendingPromotionIds: hiddenPendingPromotionIds,
                    pendingPromotionItemID: pendingPromotionItemID,
                    assigneeFor: assignee(for:),
                    activeComposerCategoryId: activeComposerCategoryId,
                    composerText: $composerText,
                    focusedComposerCategoryId: $focusedComposerCategoryId,
                    onActivateComposer: activateComposer(for:scrollProxy:),
                    onSubmitItem: submitComposer(for:),
                    onCancelItem: cancelComposer(for:),
                    onDeleteItem: requestDeleteItem(withID:),
                    onEditItem: editItem(withID:),
                    onAssignItem: beginAssigningItem(withID:),
                    onPromoteItem: promoteItem(withID:),
                    onEditCategory: { editingCategory = $0 },
                    onDeleteCategory: requestDeleteCategory(withID:)
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            guard !hasStartedInitialLoad else { return }
            hasStartedInitialLoad = true
            await loadBacklogData()
            markIdeasTutorialAsSeenIfNeeded()
        }
        .onChange(of: userSession.syncMode) { _, _ in
            _ = _Concurrency.Task {
                await loadBacklogData()
                markIdeasTutorialAsSeenIfNeeded()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            guard newTab == .backlog else { return }
            _ = _Concurrency.Task {
                await loadBacklogData()
                markIdeasTutorialAsSeenIfNeeded()
            }
        }
        .onChange(of: userSession.userId) { _, _ in
            updateStoreCloudContext()
        }
        .onChange(of: householdStore.currentHousehold?.ownerId) { _, _ in
            updateStoreCloudContext()
        }
        .onChange(of: store.categories.isEmpty) { _, isEmpty in
            if !isEmpty {
                markIdeasTutorialAsSeenIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskBoardDataDidChange)) { notification in
            store.markLocalSnapshotStale()
            if selectedNotificationIsLocal(notification) {
                store.rehydrateVisibleSnapshotFromCache()
                markIdeasTutorialAsSeenIfNeeded()
            } else {
                store.replayPendingMutationsIfNeeded()
            }
        }
    }

    private func loadBacklogData() async {
        updateStoreCloudContext()
        store.setSyncMode(userSession.syncMode)
        memberStore.setSyncMode(userSession.syncMode)
        recurringStore.setSyncMode(userSession.syncMode)
        await store.loadDataForDisplay()
        await memberStore.loadMembersForDisplay()
        await recurringStore.loadChores()
        await ChoreScheduler.shared.runIfNeeded(
            householdId: householdId,
            modelContext: modelContext,
            syncMode: userSession.syncMode
        )
        syncPromotionTipAnchorWithVisibleItems()
    }

    private var backlogLoadingState: some View {
        ProgressView("Loading ideas...")
    }

    private func updateStoreCloudContext() {
        let syncContext = householdStore.currentSyncContext(userId: userSession.userId)
        store.setCloudContext(syncContext)
        memberStore.setCloudContext(syncContext)
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

    private func latestItem(withID id: UUID?) -> BacklogItem? {
        guard let id else { return nil }
        return store.items.first(where: { $0.id == id })
    }

    private func latestCategory(withID id: UUID?) -> BacklogCategory? {
        guard let id else { return nil }
        return store.categories.first(where: { $0.id == id })
    }

    private var currentPendingPromotionItem: BacklogItem? {
        latestItem(withID: pendingPromotionItemID)
    }

    private var currentPendingAssignmentItem: BacklogItem? {
        latestItem(withID: pendingAssignmentItemID)
    }

    private var currentEditingItem: BacklogItem? {
        latestItem(withID: editingItemID)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 8) {
                Text("Ideas")
                    .font(themeStore.font(for: .screenHeader))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                if subscriptionManager.ideasInlineIndicator != nil,
                   selectedTab == .backlog
                {
                    SyncStatusIcon()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                presentRecurringChoresSheet()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 20))
                    .foregroundStyle(themeStore.accentTabColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("backlogRecurringChoresButton")
            .accessibilityLabel("Recurring Chores")
            .contextualPopoverTip(
                activeIdeasTip == .recurringChoresDiscover,
                tipID: "ideas.recurringChores",
                IdeasRecurringChoresTip(),
                arrowEdge: .top,
                generation: appTipRuntimeGeneration
            )

            Button {
                presentNewCategorySheet()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(themeStore.accentTabColor)
                        .frame(width: 44, height: 44)

                    if isAtFreeCategoryLimit {
                        ProBadgeView()
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("backlogAddCategoryButton")
            .contextualPopoverTip(
                activeIdeasTip == .createCategory,
                tipID: "ideas.createCategory",
                IdeasCreateCategoryTip(),
                arrowEdge: .top,
                generation: appTipRuntimeGeneration
            )
        }
        .frame(minHeight: 44, alignment: .center)
    }

    private var emptyState: some View {
        Group {
            if #available(iOS 17, *) {
                ContentUnavailableView {
                    Label("No Categories Yet", systemImage: "folder.badge.plus")
                } description: {
                    Text("Create a category to start organizing your ideas.")
                } actions: {
                    Button("Create your first category") {
                        presentNewCategorySheet()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .buttonStyle(.borderedProminent)
                    .tint(themeStore.accentTabColor)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(themeStore.accentTabColor)

                    Text("No Categories Yet")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)

                    Text("Create a category to start organizing your ideas.")
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                        .multilineTextAlignment(.center)

                    Button("Create your first category") {
                        presentNewCategorySheet()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .buttonStyle(.borderedProminent)
                    .tint(themeStore.accentTabColor)
                }
                .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func markIdeasTutorialAsSeenIfNeeded() {
        guard !store.categories.isEmpty, !hasSeenIdeasTutorial else { return }
        hasSeenIdeasTutorial = true
    }

    private func editItem(withID itemID: UUID) {
        guard latestItem(withID: itemID) != nil else { return }
        editingItemID = itemID
    }

    private func beginAssigningItem(withID itemID: UUID) {
        guard !activeMembers.isEmpty else {
            showBanner(.failed("No members available to assign."))
            return
        }
        guard let item = latestItem(withID: itemID) else { return }

        pendingAssignmentItemID = item.id
        selectedAssigneeIdForAssignment =
            item.assigneeId ?? currentMember?.id ?? activeMembers.first?.id
    }

    private func promoteItem(withID itemID: UUID) {
        guard let item = latestItem(withID: itemID) else { return }
        guard !hiddenPendingPromotionIds.contains(item.id), pendingPromotionItemID != item.id else {
            return
        }

        if activeMembers.isEmpty {
            if let userId = userSession.userId, let assigneeId = UUID(uuidString: userId) {
                completePromotion(of: item.id, assigneeId: assigneeId)
            } else {
                showBanner(.assigneeRequired)
            }
            return
        }

        if let assignedId = item.assigneeId {
            completePromotion(of: item.id, assigneeId: assignedId)
            return
        }

        if activeMembers.count == 1, let assigneeId = activeMembers.first?.id {
            completePromotion(of: item.id, assigneeId: assigneeId)
            return
        }

        pendingPromotionItemID = item.id
        selectedAssigneeIdForPromotion = currentMember?.id
    }

    private func completePromotion(of itemID: UUID, assigneeId: UUID) {
        guard let item = latestItem(withID: itemID) else {
            clearPromotionTipAnchor(matching: itemID)
            hiddenPendingPromotionIds.remove(itemID)
            return
        }

        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
            hiddenPendingPromotionIds.insert(item.id)
        }

        let result = store.promoteItemToTask(item, assigneeId: assigneeId)
        switch result {
        case .success:
            // Keep the item hidden for the rest of the session so a delayed
            // cloud echo cannot briefly show the promoted idea again.
            clearPromotionTipAnchor(matching: item.id)
        case .assigneeRequired, .wipLimitReached, .failed:
            withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                hiddenPendingPromotionIds.remove(item.id)
            }
        }
        handlePromotionResult(result)
    }

    private func cancelPendingPromotion() {
        pendingPromotionItemID = nil
        selectedAssigneeIdForPromotion = nil
    }

    private func handlePromotionResult(_ result: BacklogStore.PromotionResult) {
        switch result {
        case .success:
            activeBanner = nil
            AppTips.donateIdeaPromoted()
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

    private func selectedNotificationIsLocal(_ notification: Notification) -> Bool {
        (notification.object as? String) == "local"
    }

    private func handleRemoteBacklogRefresh(_ notification: Notification) {
        let payload = notification.remoteSyncAnimationPayload
        if let batchToken = payload?.batchToken,
           lastProcessedRemoteAnimationBatchToken == batchToken
        {
            return
        }

        let beforeIdeaLocations = backlogIdeaLocations()
        cancelRemoteSyncAnimationReset()
        isApplyingRemoteSyncAnimation = true

        _ = _Concurrency.Task { @MainActor in
            let categoryRefreshTask = RemoteVisibleRefreshTask(
                changedIDs: payload?.backlogChangedCategoryIDs ?? [],
                captureVisibleLocations: backlogCategoryLocations,
                rehydratePrimaryStore: {
                    withAnimation(WowAnimation.spring) {
                        store.rehydrateVisibleSnapshotFromCache()
                    }
                },
                refreshDependentStores: {
                    memberStore.markLocalSnapshotStale()
                    memberStore.rehydrateVisibleSnapshotFromCache()
                }
            )
            let categoryDelta = await categoryRefreshTask.run()

            let itemDelta = RemoteSyncVisibleDeltaResolver.resolve(
                beforeLocations: beforeIdeaLocations,
                afterLocations: backlogIdeaLocations(),
                changedIDs: payload?.workItemChangedIDs ?? []
            )

            remoteHighlightedCategoryIDs = categoryDelta.highlightedIDs
            remoteHighlightedItemIDs = itemDelta.highlightedIDs

            if let batchToken = payload?.batchToken {
                lastProcessedRemoteAnimationBatchToken = batchToken
            }

            let activeItemIds = Set(store.items.map(\.id))
            hiddenPendingPromotionIds.subtract(activeItemIds)
            syncPromotionTipAnchorWithVisibleItems()
            logRemoteSyncVisibleRefreshLatency(screen: "Ideas", payload: payload)
            scheduleRemoteSyncAnimationReset()
            markIdeasTutorialAsSeenIfNeeded()
        }
    }

    private func handleRemoteBacklogSyncBatch(_ batch: HouseholdSyncBatch) {
        if batch.classification == .bootstrap {
            cancelRemoteSyncAnimationReset()
            _ = _Concurrency.Task { @MainActor in
                store.rehydrateVisibleSnapshotFromCache()
                memberStore.markLocalSnapshotStale()
                memberStore.rehydrateVisibleSnapshotFromCache()
                let activeItemIds = Set(store.items.map(\.id))
                hiddenPendingPromotionIds.subtract(activeItemIds)
                syncPromotionTipAnchorWithVisibleItems()
                markIdeasTutorialAsSeenIfNeeded()
            }
            return
        }

        if lastProcessedRemoteAnimationBatchToken == batch.id {
            return
        }

        let beforeIdeaLocations = backlogIdeaLocations()
        cancelRemoteSyncAnimationReset()
        isApplyingRemoteSyncAnimation = true

        _ = _Concurrency.Task { @MainActor in
            let categoryRefreshTask = RemoteVisibleRefreshTask(
                changedIDs: batch.backlogChangedCategoryIDs,
                captureVisibleLocations: backlogCategoryLocations,
                rehydratePrimaryStore: {
                    withAnimation(WowAnimation.spring) {
                        store.rehydrateVisibleSnapshotFromCache()
                    }
                },
                refreshDependentStores: {
                    memberStore.markLocalSnapshotStale()
                    memberStore.rehydrateVisibleSnapshotFromCache()
                }
            )
            let categoryDelta = await categoryRefreshTask.run()

            let itemDelta = RemoteSyncVisibleDeltaResolver.resolve(
                beforeLocations: beforeIdeaLocations,
                afterLocations: backlogIdeaLocations(),
                changedIDs: batch.ideaChangedIDs
            )

            remoteHighlightedCategoryIDs = categoryDelta.highlightedIDs
            remoteHighlightedItemIDs = itemDelta.highlightedIDs
            lastProcessedRemoteAnimationBatchToken = batch.id

            let activeItemIds = Set(store.items.map(\.id))
            hiddenPendingPromotionIds.subtract(activeItemIds)
            syncPromotionTipAnchorWithVisibleItems()
            scheduleRemoteSyncAnimationReset()
            markIdeasTutorialAsSeenIfNeeded()
        }
    }

    private func backlogCategoryLocations() -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: store.categories.map { ($0.id, 0) })
    }

    private func backlogIdeaLocations() -> [UUID: UUID] {
        let visibleIdeas = store.categories.flatMap { visibleItems(for: $0.id) }
        return Dictionary(uniqueKeysWithValues: visibleIdeas.map { ($0.id, $0.categoryId) })
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
            remoteHighlightedItemIDs.removeAll()
            remoteHighlightedCategoryIDs.removeAll()
            remoteSyncResetTask = nil
        }
    }

    private func cancelRemoteSyncAnimationReset() {
        remoteSyncResetTask?.cancel()
        remoteSyncResetTask = nil
        isApplyingRemoteSyncAnimation = false
        remoteHighlightedItemIDs.removeAll()
        remoteHighlightedCategoryIDs.removeAll()
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
            let previousCount = visibleItems(for: categoryId).count
            await store.addItem(to: categoryId, title: trimmedText)
            await MainActor.run {
                suppressPromotionTip(for: 1.25)
                if visibleItems(for: categoryId).count > previousCount {
                    AppTips.donateIdeasFirstIdeaAdded()
                }
            }
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

    private func suppressPromotionTip(for duration: TimeInterval) {
        suppressPromotionTipUntil = max(
            suppressPromotionTipUntil,
            Date().addingTimeInterval(duration)
        )
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

    private func performManualRefresh() async {
        if userSession.syncMode == .cloud {
            await syncCoordinator.performInteractiveManualRefresh()
        }
        await loadBacklogData()
    }

    private var activeIdeasTip: IdeasOnboardingTip? {
        AppTipVisibility.ideasTip(
            hasCategories: !store.categories.isEmpty,
            hasVisibleIdeas: hasVisibleIdeas,
            hasVisibleUnassignedIdea: ideaAssignTipItemID != nil,
            hasVisibleAssignedIdea: promoteTipItemID != nil,
            hasActiveBanner: activeBanner != nil,
            hasPresentedSheet: hasPresentedIdeasSheet,
            hasPendingDeletionToast: pendingDeletionItem != nil,
            hasCompletedAddIdea: hasCompletedIdeasAddIdeaTip,
            hasCompletedAssignOwner: hasCompletedIdeasAssignOwnerTip,
            hasCompletedPromote: hasCompletedIdeasPromoteTip,
            hasRecurringChores: !recurringStore.chores.isEmpty,
            hasCompletedRecurringChoresTip: hasCompletedIdeasRecurringChoresTip
        )
    }

    private func presentNewCategorySheet() {
        HapticManager.lightTap()
        guard canCreateCategory else {
            premiumSubscriptionManager.presentUpsell(.backlogCategoryLimit)
            return
        }
        newCategoryColorHex = MemberColorToken.randomHex()
        isAddingCategory = true
    }

    private func presentRecurringChoresSheet() {
        HapticManager.lightTap()
        isShowingRecurringChores = true
        AppTips.donateIdeasRecurringChoresOpened()
    }

    private var canCreateCategory: Bool {
        PremiumAccessPolicy.canCreateBacklogCategory(
            currentCount: store.categories.count,
            isPremium: premiumSubscriptionManager.isPremium
        )
    }

    private var isAtFreeCategoryLimit: Bool {
        !premiumSubscriptionManager.isPremium &&
            !PremiumAccessPolicy.canCreateBacklogCategory(
                currentCount: store.categories.count,
                isPremium: false
            )
    }

    private var hasVisibleIdeas: Bool {
        store.categories.contains { !visibleItems(for: $0.id).isEmpty }
    }

    private var addIdeaTipCategoryID: UUID? {
        for category in store.categories {
            if visibleItems(for: category.id).isEmpty {
                return category.id
            }
        }

        return nil
    }

    private var ideaAssignTipItemID: UUID? {
        guard !activeMembers.isEmpty else { return nil }

        for category in store.categories {
            if let unassignedItem = visibleItems(for: category.id).first(where: { $0.assigneeId == nil }) {
                return unassignedItem.id
            }
        }

        return nil
    }

    private var promoteTipItemID: UUID? {
        guard Date() >= suppressPromotionTipUntil,
              let armedPromotionTipItemID,
              let item = latestItem(withID: armedPromotionTipItemID),
              item.assigneeId != nil,
              isVisibleIdeaItem(item)
        else {
            return nil
        }

        return item.id
    }

    private var hasPresentedIdeasSheet: Bool {
        isAddingCategory ||
            isShowingRecurringChores ||
            editingCategory != nil ||
            editingItemID != nil ||
            pendingPromotionItemID != nil ||
            pendingAssignmentItemID != nil
    }

    private var addIdeaTipAnchorCategoryID: UUID? {
        guard activeIdeasTip == .addIdea else { return nil }
        return addIdeaTipCategoryID
    }

    private var ideaAssignTipAnchorItemID: UUID? {
        guard activeIdeasTip == .assignOwner else { return nil }
        return ideaAssignTipItemID
    }

    private var ideaPromotionTipItemID: UUID? {
        guard activeIdeasTip == .promote else { return nil }
        return promoteTipItemID
    }

    private func armPromotionTip(for itemID: UUID) {
        armedPromotionTipItemID = itemID
        suppressPromotionTipUntil = .distantPast
        appTipRuntimeGeneration += 1
    }

    private func clearPromotionTipAnchor(matching itemID: UUID? = nil) {
        guard itemID == nil || armedPromotionTipItemID == itemID else { return }
        armedPromotionTipItemID = nil
    }

    private func syncPromotionTipAnchorWithVisibleItems() {
        guard let armedPromotionTipItemID,
              let item = latestItem(withID: armedPromotionTipItemID),
              item.assigneeId != nil,
              isVisibleIdeaItem(item)
        else {
            armedPromotionTipItemID = nil
            return
        }
    }

    private func isVisibleIdeaItem(_ item: BacklogItem) -> Bool {
        visibleItems(for: item.categoryId).contains(where: { $0.id == item.id })
    }

    private var deleteConfirmationTitle: String {
        guard let target = pendingDeleteConfirmationTarget else { return "Are you sure?" }
        switch target {
        case .item:
            return "Are you sure you want to delete?"
        case .category:
            return "Are you sure?"
        }
    }

    private func requestDeleteItem(withID itemID: UUID) {
        guard latestItem(withID: itemID) != nil else { return }
        HapticManager.warning()
        pendingDeleteConfirmationTarget = .item(itemID)
    }

    private func performImmediateDeleteItem(withID itemID: UUID) {
        guard let item = latestItem(withID: itemID) else { return }
        queueDeleteItem(item)
    }

    private func requestDeleteCategory(withID categoryID: UUID) {
        guard latestCategory(withID: categoryID) != nil else { return }
        if let blockReason = store.categoryDeletionBlockReason(for: categoryID) {
            HapticManager.warning()
            categoryDeletionBlockReason = blockReason
            return
        }
        HapticManager.warning()
        pendingDeleteConfirmationTarget = .category(categoryID)
    }

    private func deleteConfirmationPrimaryTitle(for target: DeleteConfirmationTarget) -> String {
        switch target {
        case .item:
            return "Delete"
        case let .category(categoryID):
            _ = categoryID
            return "Delete Category"
        }
    }

    private func deleteConfirmationMessage(for target: DeleteConfirmationTarget) -> String {
        switch target {
        case let .item(itemID):
            if let item = latestItem(withID: itemID) {
                return "\"\(item.title)\" will be removed from Ideas."
            }
            return "This idea will be removed from Ideas."
        case let .category(categoryID):
            if let category = latestCategory(withID: categoryID) {
                return "\"\(category.title)\" will be permanently deleted."
            }
            return "This category will be permanently deleted."
        }
    }

    private func confirmDeletion(_ target: DeleteConfirmationTarget) {
        pendingDeleteConfirmationTarget = nil

        switch target {
        case let .item(itemID):
            performImmediateDeleteItem(withID: itemID)
        case let .category(categoryID):
            guard let category = latestCategory(withID: categoryID) else { return }
            _ = _Concurrency.Task {
                let result = await store.deleteCategory(category)
                if case let .blocked(reason) = result {
                    await MainActor.run {
                        categoryDeletionBlockReason = reason
                    }
                }
            }
        }
    }

    private func queueDeleteItem(_ item: BacklogItem) {
        clearPromotionTipAnchor(matching: item.id)
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
        }

        withAnimation(ToastView.AnimationTokens.curve) {
            pendingDeletionItem = item
            hiddenPendingDeleteIds.insert(item.id)
        }
        HapticManager.warning()

        deletionTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(5))
            guard !_Concurrency.Task.isCancelled else { return }
            _ = await store.deleteItem(item)
            await MainActor.run {
                withAnimation(ToastView.AnimationTokens.curve) {
                    if pendingDeletionItem?.id == item.id {
                        pendingDeletionItem = nil
                    }
                    hiddenPendingDeleteIds.remove(item.id)
                }
                deletionTask = nil
            }
        }
    }

    private func undoPendingDeleteItem() {
        guard let pendingDeletionItem else { return }
        deletionTask?.cancel()
        deletionTask = nil
        withAnimation(ToastView.AnimationTokens.curve) {
            hiddenPendingDeleteIds.remove(pendingDeletionItem.id)
            self.pendingDeletionItem = nil
        }
        HapticManager.lightTap()
    }
}

private struct BacklogCategoryListSection: View {
    let categories: [BacklogCategory]
    let listBottomInset: CGFloat
    let visibleItems: (UUID) -> [BacklogItem]
    let highlightedItemIDs: Set<UUID>
    let highlightedCategoryIDs: Set<UUID>
    let isApplyingRemoteSyncAnimation: Bool
    let appTipRuntimeGeneration: Int
    let addIdeaTipCategoryID: UUID?
    let ideaAssignTipItemID: UUID?
    let ideaPromotionTipItemID: UUID?
    let hiddenPendingPromotionIds: Set<UUID>
    let pendingPromotionItemID: UUID?
    let assigneeFor: (UUID?) -> Member?
    let activeComposerCategoryId: UUID?
    @Binding var composerText: String
    let focusedComposerCategoryId: FocusState<UUID?>.Binding
    let onActivateComposer: (UUID, ScrollViewProxy) -> Void
    let onSubmitItem: (UUID) -> Void
    let onCancelItem: (UUID) -> Void
    let onDeleteItem: (UUID) -> Void
    let onEditItem: (UUID) -> Void
    let onAssignItem: (UUID) -> Void
    let onPromoteItem: (UUID) -> Void
    let onEditCategory: (BacklogCategory) -> Void
    let onDeleteCategory: (UUID) -> Void

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(categories) { category in
                        BacklogCategoryCardContainer(
                            category: category,
                            items: visibleItems(category.id),
                            highlightedItemIDs: highlightedItemIDs,
                            isCategoryHighlighted: highlightedCategoryIDs.contains(category.id),
                            isApplyingRemoteSyncAnimation: isApplyingRemoteSyncAnimation,
                            appTipRuntimeGeneration: appTipRuntimeGeneration,
                            addIdeaTipCategoryID: addIdeaTipCategoryID,
                            ideaAssignTipItemID: ideaAssignTipItemID,
                            ideaPromotionTipItemID: ideaPromotionTipItemID,
                            isPromotingItem: {
                                hiddenPendingPromotionIds.contains($0) || pendingPromotionItemID == $0
                            },
                            assigneeFor: assigneeFor,
                            isAddingItem: activeComposerCategoryId == category.id,
                            composerText: $composerText,
                            focusedComposerCategoryId: focusedComposerCategoryId,
                            onActivateComposer: {
                                onActivateComposer(category.id, scrollProxy)
                            },
                            onSubmitItem: {
                                onSubmitItem(category.id)
                            },
                            onCancelItem: {
                                onCancelItem(category.id)
                            },
                            onDeleteItem: onDeleteItem,
                            onEditItem: onEditItem,
                            onAssignItem: onAssignItem,
                            onPromoteItem: onPromoteItem,
                            onEditCategory: {
                                onEditCategory(category)
                            },
                            onDeleteCategory: {
                                onDeleteCategory(category.id)
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
    }
}

private struct BacklogCategoryCardContainer: View {
    let category: BacklogCategory
    let items: [BacklogItem]
    let highlightedItemIDs: Set<UUID>
    let isCategoryHighlighted: Bool
    let isApplyingRemoteSyncAnimation: Bool
    let appTipRuntimeGeneration: Int
    let addIdeaTipCategoryID: UUID?
    let ideaAssignTipItemID: UUID?
    let ideaPromotionTipItemID: UUID?
    let isPromotingItem: (UUID) -> Bool
    let assigneeFor: (UUID?) -> Member?
    let isAddingItem: Bool
    @Binding var composerText: String
    let focusedComposerCategoryId: FocusState<UUID?>.Binding
    let onActivateComposer: () -> Void
    let onSubmitItem: () -> Void
    let onCancelItem: () -> Void
    let onDeleteItem: (UUID) -> Void
    let onEditItem: (UUID) -> Void
    let onAssignItem: (UUID) -> Void
    let onPromoteItem: (UUID) -> Void
    let onEditCategory: () -> Void
    let onDeleteCategory: () -> Void

    var body: some View {
        CategoryCard(
            category: category,
            items: items,
            highlightedItemIDs: highlightedItemIDs,
            isCategoryHighlighted: isCategoryHighlighted,
            isApplyingRemoteSyncAnimation: isApplyingRemoteSyncAnimation,
            appTipRuntimeGeneration: appTipRuntimeGeneration,
            addIdeaTipCategoryID: addIdeaTipCategoryID,
            ideaAssignTipItemID: ideaAssignTipItemID,
            ideaPromotionTipItemID: ideaPromotionTipItemID,
            isPromotingItem: isPromotingItem,
            assigneeFor: assigneeFor,
            isAddingItem: isAddingItem,
            newItemText: $composerText,
            focusedComposerCategoryId: focusedComposerCategoryId,
            onActivateComposer: onActivateComposer,
            onSubmitItem: onSubmitItem,
            onCancelItem: onCancelItem,
            onDeleteItem: onDeleteItem,
            onEditItem: onEditItem,
            onAssignItem: onAssignItem,
            onPromoteItem: onPromoteItem,
            onEditCategory: onEditCategory,
            onDeleteCategory: onDeleteCategory
        )
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
    let highlightedItemIDs: Set<UUID>
    let isCategoryHighlighted: Bool
    let isApplyingRemoteSyncAnimation: Bool
    let appTipRuntimeGeneration: Int
    let addIdeaTipCategoryID: UUID?
    let ideaAssignTipItemID: UUID?
    let ideaPromotionTipItemID: UUID?
    let isPromotingItem: (UUID) -> Bool
    let assigneeFor: (UUID?) -> Member?
    let isAddingItem: Bool
    @Binding var newItemText: String
    let focusedComposerCategoryId: FocusState<UUID?>.Binding
    let onActivateComposer: () -> Void
    let onSubmitItem: () -> Void
    let onCancelItem: () -> Void
    let onDeleteItem: (UUID) -> Void
    let onEditItem: (UUID) -> Void
    let onAssignItem: (UUID) -> Void
    let onPromoteItem: (UUID) -> Void
    let onEditCategory: () -> Void
    let onDeleteCategory: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

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
                        Label {
                            Text("Edit Category")
                                .font(themeStore.font(for: .bodyStrong))
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }

                    Button(role: .destructive) {
                        onDeleteCategory()
                    } label: {
                        Label {
                            Text("Delete Category")
                                .font(themeStore.font(for: .bodyStrong))
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .accessibilityIdentifier("backlogCategoryMenuButton_\(category.title)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .accessibilityIdentifier("backlogCategoryHeader_\(category.title)")

            VStack(spacing: 6) {
                ForEach(items) { item in
                    let canPromote = item.assigneeId != nil
                    let isPromoting = isPromotingItem(item.id)
                    BacklogItemRow(
                        item: item,
                        assignee: assigneeFor(item.assigneeId),
                        isHighlighted: highlightedItemIDs.contains(item.id),
                        appTipRuntimeGeneration: appTipRuntimeGeneration,
                        canPromote: canPromote,
                        isPromotionDisabled: isPromoting,
                        showsAssignOwnerTip: item.id == ideaAssignTipItemID,
                        showsIdeaPromotionTip: item.id == ideaPromotionTipItemID,
                        onEdit: { onEditItem(item.id) },
                        onAssign: { onAssignItem(item.id) },
                        onPromote: { onPromoteItem(item.id) },
                        onDelete: { onDeleteItem(item.id) }
                    )
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if canPromote {
                            Button {
                                onPromoteItem(item.id)
                            } label: {
                                Label("Promote", systemImage: "arrow.up.circle")
                            }
                            .tint(.blue)
                            .disabled(isPromoting)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDeleteItem(item.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .remoteSyncStructuralTransition(enabled: isApplyingRemoteSyncAnimation)
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
                        prompt: Text("Add an idea...").font(themeStore.font(for: .listRowTitle))
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
                    HapticManager.lightTap()
                    if #available(iOS 17, *) { IdeasAddIdeaTip().invalidate(reason: .actionPerformed) }
                    AppTips.donateIdeasFirstIdeaAdded()
                    onActivateComposer()
                } label: {
                    HStack(spacing: 10) {
                        addItemPlaceholderIcon

                        Text("Add idea")
                            .font(themeStore.font(for: .buttonLabel))
                            .foregroundStyle(themeStore.accentTabColor)
                    }
                    .overlay(alignment: .topLeading) {
                        BacklogTipAnchor(width: 112, height: 18)
                            .offset(x: 4, y: -8)
                            .contextualPopoverTip(
                                addIdeaTipCategoryID == category.id,
                                tipID: "ideas.addIdea",
                                IdeasAddIdeaTip(),
                                arrowEdge: .top,
                                generation: appTipRuntimeGeneration
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("backlogAddIdeaButton_\(category.id.uuidString)")
                .accessibilityHint("Tap to add an idea to this category.")
            }
        }
        .remoteSyncHighlight(
            isActive: isCategoryHighlighted,
            cornerRadius: 12
        )
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
    }

    private var cardBackground: Color {
        themeStore.surfaceColor
    }

    private var cardBorder: Color {
        colorScheme == .light ? themeStore.borderLightColor : .clear
    }

    @ViewBuilder
    private var composerPlaceholderIcon: some View {
        if themeStore.usesRetroChrome {
            Rectangle()
                .stroke(
                    themeStore.isRetroLight ? themeStore.borderLightColor : Color(hex: "F7D51D"),
                    lineWidth: 2.2
                )
                .frame(width: 20, height: 20)
                .overlay {
                    Rectangle()
                        .stroke(
                            (themeStore.isRetroLight ? themeStore.borderLightColor : Color.black)
                                .opacity(themeStore.isRetroLight ? 0.72 : 0.75),
                            lineWidth: 1
                        )
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
        if themeStore.usesRetroChrome {
            Rectangle()
                .stroke(themeStore.accentTabColor.opacity(0.9), lineWidth: 2.2)
                .frame(width: 20, height: 20)
                .overlay {
                    Rectangle()
                        .stroke(
                            (themeStore.isRetroLight ? themeStore.borderLightColor : Color.black)
                                .opacity(themeStore.isRetroLight ? 0.7 : 0),
                            lineWidth: themeStore.isRetroLight ? 1 : 0
                        )
                        .padding(0.9)
                }
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

struct BacklogItemRow: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let item: BacklogItem
    let assignee: Member?
    let isHighlighted: Bool
    let appTipRuntimeGeneration: Int
    let canPromote: Bool
    let isPromotionDisabled: Bool
    let showsAssignOwnerTip: Bool
    let showsIdeaPromotionTip: Bool
    let onEdit: () -> Void
    let onAssign: () -> Void
    let onPromote: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.lightTap()
                onEdit()
            } label: {
                Text(item.title)
                    .font(themeStore.font(for: .listRowTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                    .strikethrough(false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("backlogEditButton_\(item.title)")

            HStack(spacing: 10) {
                assignButton

                if canPromote {
                    Button {
                        HapticManager.lightTap()
                        if #available(iOS 17, *) { IdeaPromotionTip().invalidate(reason: .actionPerformed) }
                        onPromote()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .frame(width: 32, height: 32)
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .disabled(isPromotionDisabled)
                    .opacity(isPromotionDisabled ? 0.45 : 1)
                    .accessibilityIdentifier("backlogPromoteButton_\(item.title)")
                    .transition(.opacity.combined(with: .scale))
                    .contextualPopoverTip(
                        showsIdeaPromotionTip,
                        tipID: "ideas.promote",
                        IdeaPromotionTip(),
                        arrowEdge: .top,
                        generation: appTipRuntimeGeneration
                    )
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("backlogDeleteButton_\(item.title)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : .white)
        }
        .remoteSyncHighlight(isActive: isHighlighted, cornerRadius: 10)
        .animation(.easeInOut(duration: 0.2), value: canPromote)
    }

    private var assignButton: some View {
        Button(action: onAssign) {
            Group {
                if let assignee {
                    MemberNameChipView(
                        name: assignee.displayName,
                        colorHex: assignee.colorHex
                    )
                } else {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(themeStore.contentSecondaryColor)

                    Text("Assign")
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }
            }
            .modifier(BacklogAssignButtonChrome(
                showsBackground: assignee == nil
            ))
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
        .accessibilityIdentifier("backlogAssignButton_\(item.title)")
        .contextualPopoverTip(
            showsAssignOwnerTip,
            tipID: "ideas.assignOwner",
            IdeasAssignOwnerTip(),
            arrowEdge: .trailing,
            generation: appTipRuntimeGeneration
        )
    }
}

private struct BacklogTipAnchor: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct BacklogAssignButtonChrome: ViewModifier {
    let showsBackground: Bool

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        HStack(spacing: showsBackground ? 8 : 0) {
            content
        }
        .padding(.horizontal, showsBackground ? 12 : 0)
        .padding(.vertical, showsBackground ? 8 : 0)
        .background {
            if showsBackground {
                Capsule()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .overlay {
                        Capsule()
                            .stroke(themeStore.borderLightColor.opacity(0.35), lineWidth: 1)
                    }
            }
        }
    }
}

private enum RecurringChoreEditorDestination: Identifiable {
    case create
    case edit(RecurringChore)

    var id: String {
        switch self {
        case .create:
            "create"
        case let .edit(chore):
            chore.id.uuidString
        }
    }

    var chore: RecurringChore? {
        if case let .edit(chore) = self {
            return chore
        }
        return nil
    }
}

private struct RecurringChoresView: View {
    @ObservedObject var store: RecurringChoreStore
    let householdId: UUID
    let modelContext: ModelContext
    let syncMode: SyncMode
    let categories: [BacklogCategory]
    let members: [Member]

    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.dismiss) private var dismiss
    @State private var editorDestination: RecurringChoreEditorDestination?
    @State private var hasStartedInitialLoad = false

    private var activeChores: [RecurringChore] {
        store.chores.filter(\.isActive).sorted(by: sortChores)
    }

    private var pausedChores: [RecurringChore] {
        store.chores.filter { !$0.isActive }.sorted(by: sortChores)
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading, store.chores.isEmpty {
                    ProgressView("Loading recurring chores...")
                } else if store.chores.isEmpty {
                    recurringEmptyState
                } else {
                    choresList
                }
            }
            .background(themeStore.canvasColor.ignoresSafeArea())
            .navigationTitle("Recurring Chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticManager.lightTap()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Recurring Chores")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.lightTap()
                        editorDestination = .create
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityIdentifier("recurringChoresAddButton")
                }
            }
            .task {
                guard !hasStartedInitialLoad else { return }
                hasStartedInitialLoad = true
                store.setSyncMode(userSession.syncMode)
                await store.loadChores()
            }
            .onChange(of: userSession.syncMode) { _, mode in
                store.setSyncMode(mode)
                _ = _Concurrency.Task {
                    await store.loadChores()
                }
            }
            .sheet(item: $editorDestination) { destination in
                RecurringChoreEditorSheet(
                    store: store,
                    householdId: householdId,
                    modelContext: modelContext,
                    syncMode: syncMode,
                    categories: categories,
                    members: members,
                    chore: destination.chore
                )
            }
        }
    }

    private var choresList: some View {
        List {
            if !activeChores.isEmpty {
                Section {
                    ForEach(activeChores) { chore in
                        Button {
                            HapticManager.lightTap()
                            editorDestination = .edit(chore)
                        } label: {
                            RecurringChoreRow(
                                chore: chore,
                                category: category(for: chore.categoryId),
                                assignee: assignee(for: chore.assigneeId)
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                delete(chore)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Active")
                        .font(themeStore.font(for: .sectionHeader))
                }
            }

            if !pausedChores.isEmpty {
                Section {
                    ForEach(pausedChores) { chore in
                        Button {
                            HapticManager.lightTap()
                            editorDestination = .edit(chore)
                        } label: {
                            RecurringChoreRow(
                                chore: chore,
                                category: category(for: chore.categoryId),
                                assignee: assignee(for: chore.assigneeId)
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                delete(chore)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Paused")
                        .font(themeStore.font(for: .sectionHeader))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var recurringEmptyState: some View {
        ContentUnavailableView {
            Label("No Recurring Chores", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("Create chores that automatically return to your task board.")
                .font(themeStore.font(for: .listRowTitle))
        } actions: {
            Button {
                HapticManager.lightTap()
                editorDestination = .create
            } label: {
                Text("Create Chore")
                    .font(themeStore.font(for: .buttonLabel))
            }
        }
    }

    private func category(for id: UUID?) -> BacklogCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    private func assignee(for id: UUID?) -> Member? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }

    private func delete(_ chore: RecurringChore) {
        HapticManager.warning()
        _ = _Concurrency.Task {
            await store.deleteChore(chore)
        }
    }

    private func sortChores(_ lhs: RecurringChore, _ rhs: RecurringChore) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

private struct RecurringChoreRow: View {
    let chore: RecurringChore
    let category: BacklogCategory?
    let assignee: Member?

    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(themeStore.accentTabColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text(chore.title)
                    .font(themeStore.font(for: .listRowTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                HStack(spacing: 6) {
                    Text(recurrenceSummary)
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(themeStore.contentSecondaryColor)

                    if let assignee {
                        MemberNameChipView(name: assignee.displayName, colorHex: assignee.colorHex)
                    }

                    if let category {
                        Text(category.title)
                            .font(themeStore.font(for: .chip))
                            .foregroundStyle(Color(hex: category.colorHex))
                    }
                }
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var recurrenceSummary: String {
        let timeText = Self.timeText(hour: chore.scheduledHour, minute: chore.scheduledMinute)
        let nextText = chore.nextScheduledDate.map { "Next: \(Self.dateText($0))" }
        switch chore.recurrenceType {
        case .daily:
            let interval = max(chore.recurrenceInterval ?? 1, 1)
            let cadence = interval == 1 ? "Daily" : "Every \(interval) days"
            return ([cadence, timeText, nextText] as [String?]).compactMap(\.self).joined(separator: " · ")
        case .weekly:
            return (["Weekly", Self.weekdayName(for: chore.recurrenceDay ?? 2), timeText, nextText] as [String?])
                .compactMap(\.self)
                .joined(separator: " · ")
        case .monthly:
            return (["Monthly", "Day \(chore.recurrenceDayOfMonth ?? 1)", timeText, nextText] as [String?])
                .compactMap(\.self)
                .joined(separator: " · ")
        case .custom:
            let interval = max(chore.recurrenceInterval ?? chore.frequencyDays, 1)
            return (["Every \(interval) days", timeText, nextText] as [String?])
                .compactMap(\.self)
                .joined(separator: " · ")
        }
    }

    private static func weekdayName(for weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = min(max(weekday, 1), symbols.count) - 1
        return symbols[index]
    }

    private static func timeText(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        guard let date = Calendar.current.date(from: components) else { return "12:00" }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

enum RecurringChoreEditorValidation {
    static func canSave(
        title: String,
        assigneeId: UUID?,
        categoryId: UUID?,
        scheduledHour: Int,
        scheduledMinute: Int
    ) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            assigneeId != nil &&
            categoryId != nil &&
            (0 ... 23).contains(scheduledHour) &&
            (0 ... 59).contains(scheduledMinute)
    }
}

private struct RecurringChoreEditorSheet: View {
    @ObservedObject var store: RecurringChoreStore
    let householdId: UUID
    let modelContext: ModelContext
    let syncMode: SyncMode
    let categories: [BacklogCategory]
    let members: [Member]
    let chore: RecurringChore?

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var categoryId: UUID?
    @State private var assigneeId: UUID?
    @State private var recurrenceType: RecurringChore.RecurrenceType
    @State private var recurrenceInterval: Int
    @State private var recurrenceDay: Int
    @State private var recurrenceDayOfMonth: Int
    @State private var scheduleStartDate: Date
    @State private var scheduledTime: Date
    @State private var notes: String
    @State private var isActive: Bool

    init(
        store: RecurringChoreStore,
        householdId: UUID,
        modelContext: ModelContext,
        syncMode: SyncMode,
        categories: [BacklogCategory],
        members: [Member],
        chore: RecurringChore?
    ) {
        self.store = store
        self.householdId = householdId
        self.modelContext = modelContext
        self.syncMode = syncMode
        self.categories = categories
        self.members = members
        self.chore = chore
        _title = State(initialValue: chore?.title ?? "")
        _categoryId = State(initialValue: chore?.categoryId)
        _assigneeId = State(initialValue: chore?.assigneeId)
        _recurrenceType = State(initialValue: chore?.recurrenceType ?? .weekly)
        _recurrenceInterval = State(initialValue: max(chore?.recurrenceInterval ?? 1, 1))
        _recurrenceDay = State(initialValue: chore?.recurrenceDay ?? Calendar.current.component(.weekday, from: Date()))
        _recurrenceDayOfMonth = State(initialValue: chore?.recurrenceDayOfMonth ?? 1)
        _scheduleStartDate = State(initialValue: chore?.scheduleStartDate ?? chore?.nextScheduledDate ?? Date())
        _scheduledTime = State(
            initialValue: Self.timeDate(
                hour: chore?.scheduledHour ?? 12,
                minute: chore?.scheduledMinute ?? 0
            )
        )
        _notes = State(initialValue: chore?.notes ?? "")
        _isActive = State(initialValue: chore?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(themeStore.font(for: .listRowTitle))
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Chore")
                        .font(themeStore.font(for: .sectionHeader))
                }

                Section {
                    if categories.isEmpty {
                        Text("Create a category before adding recurring chores.")
                            .font(themeStore.font(for: .listRowTitle))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                    } else {
                        Picker("Category", selection: $categoryId) {
                            Text("Pick a category").tag(UUID?.none)
                            ForEach(categories) { category in
                                Text(category.title).tag(Optional(category.id))
                            }
                        }
                        .font(themeStore.font(for: .listRowTitle))
                    }

                    if members.isEmpty {
                        Text("Invite a household member before adding recurring chores.")
                            .font(themeStore.font(for: .listRowTitle))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                    } else {
                        Picker("Assignee", selection: $assigneeId) {
                            Text("Pick a household member").tag(UUID?.none)
                            ForEach(members) { member in
                                Text(member.displayName).tag(Optional(member.id))
                            }
                        }
                        .font(themeStore.font(for: .listRowTitle))
                    }
                } header: {
                    Text("Ownership")
                        .font(themeStore.font(for: .sectionHeader))
                }

                Section {
                    Picker("Frequency", selection: $recurrenceType) {
                        Text("Daily").tag(RecurringChore.RecurrenceType.daily)
                        Text("Weekly").tag(RecurringChore.RecurrenceType.weekly)
                        Text("Monthly").tag(RecurringChore.RecurrenceType.monthly)
                    }
                    .pickerStyle(.segmented)

                    recurrenceControls

                    DatePicker(
                        "Starts",
                        selection: $scheduleStartDate,
                        displayedComponents: .date
                    )
                    .font(themeStore.font(for: .listRowTitle))

                    DatePicker(
                        "Time",
                        selection: $scheduledTime,
                        displayedComponents: .hourAndMinute
                    )
                    .font(themeStore.font(for: .listRowTitle))
                } header: {
                    Text("Schedule")
                        .font(themeStore.font(for: .sectionHeader))
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .font(themeStore.font(for: .listRowTitle))
                        .lineLimit(2 ... 4)

                    Toggle(isOn: $isActive) {
                        Text("Active")
                            .font(themeStore.font(for: .listRowTitle))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(themeStore.canvasColor.ignoresSafeArea())
            .navigationTitle(chore == nil ? "New Chore" : "Edit Chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        HapticManager.lightTap()
                        dismiss()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(chore == nil ? "Create" : "Save") {
                        save()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private var recurrenceControls: some View {
        switch recurrenceType {
        case .daily:
            Stepper(value: $recurrenceInterval, in: 1 ... 30) {
                Text(recurrenceInterval == 1 ? "Every day" : "Every \(recurrenceInterval) days")
                    .font(themeStore.font(for: .listRowTitle))
            }
        case .weekly:
            Picker("Day", selection: $recurrenceDay) {
                ForEach(1 ... 7, id: \.self) { weekday in
                    Text(Self.weekdayName(for: weekday)).tag(weekday)
                }
            }
            .font(themeStore.font(for: .listRowTitle))
        case .monthly:
            Stepper(value: $recurrenceDayOfMonth, in: 1 ... 28) {
                Text("Day \(recurrenceDayOfMonth)")
                    .font(themeStore.font(for: .listRowTitle))
            }
        case .custom:
            Stepper(value: $recurrenceInterval, in: 1 ... 30) {
                Text("Every \(recurrenceInterval) days")
                    .font(themeStore.font(for: .listRowTitle))
            }
        }
    }

    private var canSave: Bool {
        RecurringChoreEditorValidation.canSave(
            title: title,
            assigneeId: assigneeId,
            categoryId: categoryId,
            scheduledHour: scheduledHour,
            scheduledMinute: scheduledMinute
        )
    }

    private var scheduledHour: Int {
        Calendar.current.component(.hour, from: scheduledTime)
    }

    private var scheduledMinute: Int {
        Calendar.current.component(.minute, from: scheduledTime)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let startDate = Calendar.current.startOfDay(for: scheduleStartDate)
        let hour = scheduledHour
        let minute = scheduledMinute
        HapticManager.lightTap()

        _ = _Concurrency.Task {
            if var existing = chore {
                existing.title = trimmedTitle
                existing.categoryId = categoryId
                existing.assigneeId = assigneeId
                existing.defaultAssigneeIds = assigneeId.map { [$0] } ?? []
                existing.recurrenceType = recurrenceType
                existing.recurrenceInterval = recurrenceInterval
                existing.recurrenceDay = recurrenceType == .weekly ? recurrenceDay : nil
                existing.recurrenceDayOfMonth = recurrenceType == .monthly ? recurrenceDayOfMonth : nil
                existing.scheduleStartDate = startDate
                existing.scheduledHour = hour
                existing.scheduledMinute = minute
                existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
                existing.isActive = isActive
                existing.nextScheduledDate = ChoreScheduler.nextScheduledDate(for: existing, from: Date())
                existing.updatedAt = Date()
                await store.updateChore(existing)
            } else {
                await store.addChore(
                    title: trimmedTitle,
                    recurrenceType: recurrenceType,
                    recurrenceInterval: recurrenceInterval,
                    recurrenceDay: recurrenceType == .weekly ? recurrenceDay : nil,
                    recurrenceDayOfMonth: recurrenceType == .monthly ? recurrenceDayOfMonth : nil,
                    assigneeId: assigneeId,
                    categoryId: categoryId,
                    scheduleStartDate: startDate,
                    scheduledHour: hour,
                    scheduledMinute: minute,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                    isActive: isActive
                )
            }
            await MainActor.run {
                dismiss()
            }
        }
    }

    private static func weekdayName(for weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = min(max(weekday, 1), symbols.count) - 1
        return symbols[index]
    }

    private static func timeDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        return Calendar.current.date(from: components) ?? Date()
    }
}

#Preview {
    BacklogView()
        .environmentObject(UserSession.shared)
        .environmentObject(ThemeStore())
}

// swiftlint:enable file_length type_body_length
