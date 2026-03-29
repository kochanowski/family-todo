import SwiftData
import SwiftUI
import UIKit

// swiftlint:disable file_length
/// Shopping List screen - quick capture and management of groceries
struct ShoppingListView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext
    @Binding private var selectedTab: AppTab

    init(selectedTab: Binding<AppTab> = .constant(.shopping)) {
        _selectedTab = selectedTab
    }

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                ShoppingListContent(
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
private struct ShoppingListContent: View {
    @StateObject private var store: ShoppingListStore
    @StateObject private var bundleStore: ShoppingBundleStore
    @StateObject private var restockPulse = RestockPulseState()
    @Binding private var selectedTab: AppTab
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager
    @EnvironmentObject private var syncCoordinator: HouseholdSyncCoordinator

    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var celebrationManager: CelebrationManager
    @Environment(\.colorScheme) private var colorScheme

    // Rapid entry state
    @State private var isRapidEntryActive = false
    @State private var rapidEntryText = ""
    @State private var rapidEntryFocused = false

    @State private var showRestock = false
    @State private var showClearToBuyConfirmation = false
    @State private var showQuickAddBundleChooser = false
    @State private var didTriggerQuickAddGesture = false
    @State private var itemBeingRemoved: UUID?
    @State private var editingItemId: UUID?
    @State private var editingItemText = ""
    @State private var inlineInsertAfterItemId: UUID?
    @State private var inlineInsertText = ""
    @State private var inlineInsertRowToken = UUID()
    @State private var isKeyboardVisible = false
    @State private var didPerformInitialLoad = false
    @State private var isScreenVisible = false
    @State private var pendingShoppingCompletionCelebrationTask: _Concurrency.Task<Void, Never>?
    @State private var activeToast: ShoppingToastState?
    @State private var activeToastDismissTask: _Concurrency.Task<Void, Never>?
    @State private var remoteHighlightedItemIDs: Set<UUID> = []
    @State private var isApplyingRemoteSyncAnimation = false
    @State private var remoteSyncResetTask: _Concurrency.Task<Void, Never>?
    @State private var shouldRearmBundleQuickAddTipOnNextAppear = false
    @AppStorage(AppTipProgressKey.shoppingTutorialSeen) private var hasSeenShoppingTutorial = false
    @AppStorage(AppTipProgressKey.shoppingFirstAddCompleted)
    private var hasCompletedShoppingFirstAddTip = false
    @AppStorage(AppTipProgressKey.shoppingRecentPurchasesCompleted)
    private var hasCompletedShoppingRecentPurchasesTip = false
    @AppStorage(AppTipProgressKey.shoppingBundlesLocationCompleted)
    private var hasCompletedShoppingBundlesLocationTip = false
    @AppStorage(AppTipProgressKey.shoppingBundleQuickAddCompleted)
    private var hasCompletedShoppingBundleQuickAddTip = false
    @AppStorage(AppTips.runtimeGenerationDefaultsKey)
    private var appTipRuntimeGeneration = 0

    init(householdId: UUID, modelContext: ModelContext, selectedTab: Binding<AppTab>) {
        _store = StateObject(
            wrappedValue: ShoppingListStore(householdId: householdId, modelContext: modelContext)
        )
        _bundleStore = StateObject(
            wrappedValue: ShoppingBundleStore(householdId: householdId, modelContext: modelContext)
        )
        _selectedTab = selectedTab
    }

    var body: some View {
        GeometryReader(content: shoppingGeometryContent)
            .task {
                guard !didPerformInitialLoad else { return }
                didPerformInitialLoad = true
                await loadShoppingData()
            }
            .onChange(of: userSession.syncMode) { _, mode in
                updateStoreCloudContext()
                store.setSyncMode(mode)
                bundleStore.setSyncMode(mode)
                _ = _Concurrency.Task {
                    await loadShoppingData()
                }
            }
            .onChange(of: userSession.userId) { _, _ in
                updateStoreCloudContext()
            }
            .onChange(of: householdStore.currentHousehold?.ownerId) { _, _ in
                updateStoreCloudContext()
            }
            .onChange(of: selectedTab) { _, newTab in
                guard newTab == .shopping else { return }
                _ = _Concurrency.Task {
                    await loadShoppingData()
                }
            }
            .onChange(of: store.toBuyItems.isEmpty) { _, isEmpty in
                if !isEmpty {
                    markShoppingTutorialAsSeenIfNeeded()
                }
            }
            .onChange(of: quickAddBundles.isEmpty) { oldIsEmpty, newIsEmpty in
                guard oldIsEmpty, !newIsEmpty else { return }
                if isScreenVisible {
                    rearmBundleQuickAddTipIfNeeded()
                } else {
                    shouldRearmBundleQuickAddTipOnNextAppear = true
                }
            }
            .onChange(of: isKeyboardVisible) { _, visible in
                guard !visible else { return }
                if let editingItem = currentEditingItem {
                    commitEditingItem(editingItem)
                } else if inlineInsertAfterItemId != nil, inlineInsertText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    dismissInlineInsert()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            ) { _ in
                isKeyboardVisible = true
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .shoppingListDataDidChange)
            ) { notification in
                store.markLocalSnapshotStale()
                if isLocalStoreNotification(notification) {
                    store.rehydrateVisibleSnapshotFromCache()
                } else {
                    store.replayPendingMutationsIfNeeded()
                }
            }
            .onChange(of: syncCoordinator.latestBatch?.id) { _, _ in
                guard let batch = syncCoordinator.latestBatch,
                      batch.domains.contains(.shopping)
                else {
                    return
                }

                store.markLocalSnapshotStale()
                if selectedTab == .shopping {
                    handleRemoteShoppingSyncBatch(batch)
                } else {
                    store.replayPendingMutationsIfNeeded()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in
                isKeyboardVisible = false
            }
            .sheet(isPresented: $showClearToBuyConfirmation) {
                AppConfirmationSheet(
                    title: "Clear shopping list?",
                    message: "This removes current To Buy items. Recently Purchased stays unchanged.",
                    primaryTitle: "Clear",
                    titleFontToken: .profileName,
                    messageFontToken: .bodyStrong,
                    primaryStyle: .destructive,
                    onPrimary: clearToBuy
                )
            }
            .sheet(isPresented: $showQuickAddBundleChooser) {
                ShoppingQuickAddBundleSheet(
                    bundles: quickAddBundles,
                    onSelectBundle: { bundle in
                        showQuickAddBundleChooser = false
                        handleBundleQuickAdd(bundle)
                    }
                )
            }
            .overlay(alignment: .bottom) {
                if let activeToast {
                    ToastView(message: activeToast.message)
                        .padding(.horizontal, ToastView.Metrics.horizontalInset)
                        .padding(.bottom, AppChromeMetrics.compactCTAHeight + 22)
                        .transition(ToastView.AnimationTokens.transition)
                        .id(activeToast.id)
                }
            }
            .animation(ToastView.AnimationTokens.curve, value: activeToast?.id)
            .onAppear {
                isScreenVisible = true
                if didPerformInitialLoad {
                    _ = _Concurrency.Task {
                        await bundleStore.loadBundlesForDisplay()
                        await MainActor.run {
                            if shouldRearmBundleQuickAddTipOnNextAppear {
                                rearmBundleQuickAddTipIfNeeded()
                                shouldRearmBundleQuickAddTipOnNextAppear = false
                            }
                        }
                    }
                }
            }
            .onDisappear {
                isScreenVisible = false
                cancelPendingShoppingCompletionCelebration()
                cancelToastDismiss()
                cancelRemoteSyncAnimationReset()
            }
            .onChange(of: showQuickAddBundleChooser) { _, isPresented in
                if !isPresented {
                    didTriggerQuickAddGesture = false
                }
            }
    }

    private func shoppingGeometryContent(_ proxy: GeometryProxy) -> some View {
        let listBottomInset =
            isKeyboardVisible
                ? CGFloat(16)
                : AppChromeMetrics.compactCTAHeight + 28
        let floatingButtonInset: CGFloat = 16
        let rapidEntryTapHeight = max(0, proxy.size.height - listBottomInset)
        let shouldShowLoadingState =
            !store.hasHydratedLocalSnapshot &&
            store.toBuyItems.isEmpty &&
            !isRapidEntryActive
        let shouldShowEmptyState =
            store.hasHydratedLocalSnapshot &&
            store.toBuyItems.isEmpty &&
            !isRapidEntryActive

        return ZStack(alignment: .bottomTrailing) {
            rapidEntryDismissOverlay(maxHeight: rapidEntryTapHeight)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                    .padding(.top, AppChromeMetrics.screenHeaderTopPadding)
                    .padding(.bottom, AppChromeMetrics.screenHeaderBottomPadding)

                if shouldShowLoadingState {
                    shoppingLoadingState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                        .padding(.bottom, listBottomInset)
                } else if shouldShowEmptyState {
                    shoppingEmptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                        .padding(.bottom, listBottomInset)
                } else {
                    shoppingList(listBottomInset: listBottomInset)
                }
            }

            floatingAddButton(bottomInset: floatingButtonInset)
        }
        .appAdaptiveWidth(
            maxWidth: AppChromeMetrics.regularContentMaxWidth,
            alignment: .topLeading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func rapidEntryDismissOverlay(maxHeight: CGFloat) -> some View {
        if isRapidEntryActive {
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .top)
                .onTapGesture {
                    commitOrDismissRapidEntry()
                }
        }
    }

    @ViewBuilder
    private func floatingAddButton(bottomInset: CGFloat) -> some View {
        if !isRapidEntryActive, !isKeyboardVisible {
            addPillButton
                .padding(.trailing, AppChromeMetrics.horizontalInset)
                .padding(.bottom, bottomInset)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func shoppingList(listBottomInset: CGFloat) -> some View {
        ScrollViewReader { proxy in
            List {
                ForEach(store.toBuyItems) { item in
                    shoppingListRow(for: item)

                    if inlineInsertAfterItemId == item.id {
                        ShoppingItemInlineComposerRow(
                            text: $inlineInsertText,
                            onSubmit: { commitInlineInsertedItem(after: item.id) },
                            onCancel: dismissInlineInsert
                        )
                        .id(inlineInsertRowToken)
                        .listRowInsets(shoppingRowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("shoppingInlineInsertRow")
                    }
                }
                .onMove(perform: moveToBuyItems)

                if isRapidEntryActive {
                    rapidEntryRow
                        .id("rapidEntry")
                        .listRowInsets(shoppingRowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .environment(\.defaultMinListRowHeight, 10)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(.bottom, listBottomInset)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await performManualRefresh()
            }
            .onChange(of: rapidEntryFocused) { _, focused in
                guard focused else { return }
                withAnimation(WowAnimation.spring) {
                    proxy.scrollTo("rapidEntry", anchor: .bottom)
                }
            }
            .onChange(of: inlineInsertRowToken) { _, _ in
                guard inlineInsertAfterItemId != nil else { return }
                withAnimation(WowAnimation.spring) {
                    proxy.scrollTo(inlineInsertRowToken, anchor: .center)
                }
            }
            .onChange(of: store.toBuyItems.count) { _, _ in
                if isRapidEntryActive {
                    withAnimation(WowAnimation.spring) {
                        proxy.scrollTo("rapidEntry", anchor: .bottom)
                    }
                } else if inlineInsertAfterItemId != nil {
                    withAnimation(WowAnimation.spring) {
                        proxy.scrollTo(inlineInsertRowToken, anchor: .center)
                    }
                }
            }
        }
    }

    private func shoppingListRow(for item: ShoppingItem) -> some View {
        Group {
            if itemBeingRemoved != item.id {
                if editingItemId == item.id {
                    ShoppingItemInlineEditRow(
                        text: $editingItemText,
                        isBought: item.isBought,
                        onToggle: {
                            cancelEditingItem()
                            dismissInlineInsert()
                            toggleItem(item)
                        },
                        onSubmit: {
                            commitEditingItem(
                                item,
                                openInlineComposer: true
                            )
                        },
                        onFocusLossCommit: {
                            commitEditingItem(item)
                        },
                        onCancel: cancelEditingItem
                    )
                    .accessibilityIdentifier("shoppingItemEdit_\(item.title)")
                } else {
                    ShoppingItemRow(
                        item: item,
                        onToggle: { toggleItem(item) },
                        onEdit: { startEditingItem(item) }
                    )
                    .accessibilityIdentifier("shoppingItem_\(item.title)")
                }
            }
        }
        .remoteSyncStructuralTransition(enabled: isApplyingRemoteSyncAnimation)
        .remoteSyncHighlight(
            isActive: remoteHighlightedItemIDs.contains(item.id),
            cornerRadius: 10
        )
        .listRowInsets(shoppingRowInsets)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var shoppingRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
    }

    // MARK: - Empty State

    private var shoppingEmptyState: some View {
        Group {
            if hasSeenShoppingTutorial {
                ThemedEmptyStateView(
                    title: "Your List is Empty",
                    systemImage: "cart.badge.plus",
                    description: "Time to restock! Add groceries or household items you need to buy."
                )
            } else {
                ThemedEmptyStateView(
                    title: "Welcome to Shopping!",
                    systemImage: "cart.fill.badge.plus",
                    description: "Add groceries and household items here. Once bought, they save to your history for quick re-adding later!"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: -40)
    }

    private var shoppingLoadingState: some View {
        ProgressView("Loading shopping...")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
    }

    // MARK: - Header

    private var header: some View {
        AppScreenHeader(title: "Shopping") {
            HStack(spacing: 8) {
                if !store.toBuyItems.isEmpty {
                    ShoppingCountBadge(count: store.toBuyItems.count)
                }

                if subscriptionManager.shoppingInlineIndicator != nil,
                   selectedTab == .shopping
                {
                    SyncStatusIcon()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        } trailing: {
            HStack(alignment: .center, spacing: 8) {
                // Clear To Buy button
                if !store.toBuyItems.isEmpty {
                    Button {
                        HapticManager.lightTap()
                        showClearToBuyConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(themeStore.accentTabColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shoppingClearButton")
                }

                NavigationLink {
                    BundlesManagementView(store: bundleStore, shoppingStore: store)
                } label: {
                    Image(systemName: ShoppingBundle.featureIcon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(themeStore.accentTabColor)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shoppingBundlesButton")
                .simultaneousGesture(TapGesture().onEnded {
                    HapticManager.lightTap()
                    AppTips.donateShoppingBundlesVisited()
                })
                .contextualPopoverTip(
                    activeShoppingTip == .bundlesLocation,
                    tipID: "shopping.bundlesLocation",
                    ShoppingBundlesLocationTip(),
                    arrowEdge: .top,
                    generation: appTipRuntimeGeneration
                )

                // Recently purchased
                Button {
                    HapticManager.lightTap()
                    AppTips.donateShoppingRecentPurchasesOpened()
                    showRestock = true
                } label: {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(themeStore.accentTabColor)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shoppingRestockButton")
                .pulseAnimation(trigger: restockPulse.pulseToken)
                .contextualPopoverTip(
                    activeShoppingTip == .recentPurchases,
                    tipID: "shopping.recentPurchases",
                    ShoppingRecentlyPurchasedTip(),
                    arrowEdge: .top,
                    generation: appTipRuntimeGeneration
                )
                .sheet(isPresented: $showRestock) {
                    RestockSheet(
                        store: store,
                        onRestore: restoreRecentItem,
                        onDeleteItem: deleteRecentItem,
                        onClearAll: clearRecentItems
                    )
                }
            }
        }
    }

    // MARK: - Add Pill Button

    private var addPillButton: some View {
        addPillButtonBase
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        guard !quickAddBundles.isEmpty else { return }
                        didTriggerQuickAddGesture = true
                        HapticManager.lightTap()
                        showQuickAddBundleChooser = true
                    }
            )
    }

    private var addPillButtonBase: some View {
        let foreground = themeStore.foregroundOnAccent(
            for: themeStore.accentTabColor, colorScheme: colorScheme
        )

        return Button {
            if didTriggerQuickAddGesture {
                didTriggerQuickAddGesture = false
                return
            }
            startRapidEntry()
        } label: {
            HStack(spacing: 0) {
                Text("Add item")
                    .font(themeStore.font(for: .buttonLabel))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, AppChromeMetrics.compactCTAHorizontalPadding)
            .frame(height: AppChromeMetrics.compactCTAHeight)
            .background {
                Capsule()
                    .fill(themeStore.accentTabColor)
                    .shadow(color: themeStore.accentTabColor.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shoppingAddItemButton")
        .accessibilityHint(
            quickAddBundles.isEmpty
                ? "Double tap to add a shopping item."
                : "Double tap to add a shopping item. Long press to quickly add a shopping bundle."
        )
        .contextualPopoverTip(
            activeShoppingTip == .firstAdd,
            tipID: "shopping.firstAdd",
            ShoppingFirstAddTip(),
            arrowEdge: .bottom,
            generation: appTipRuntimeGeneration
        )
        .contextualPopoverTip(
            activeShoppingTip == .bundleQuickAdd,
            tipID: "shopping.bundleQuickAdd",
            ShoppingBundleQuickAddTip(),
            arrowEdge: .bottom,
            generation: appTipRuntimeGeneration
        )
    }

    private var rapidEntryRow: some View {
        HStack(spacing: ShoppingRowLayout.spacing) {
            ThemedCheckbox(
                isChecked: false,
                onToggle: {},
                size: 20,
                style: .circle
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            RapidEntryTextField(
                text: $rapidEntryText,
                isFocused: $rapidEntryFocused,
                placeholder: "Add item",
                actionColor: UIColor(themeStore.accentTabColor),
                actionForegroundColor: UIColor(
                    themeStore.foregroundOnAccent(
                        for: themeStore.accentTabColor, colorScheme: colorScheme
                    )
                ),
                onSubmit: handleRapidEntrySubmit,
                onDone: commitOrDismissRapidEntry,
                themeStore: themeStore
            )
            .accessibilityIdentifier("shoppingRapidEntryField")
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: ShoppingRowLayout.trailingSlotWidth, height: 24)
        }
        .frame(minHeight: ShoppingRowLayout.minRowHeight)
        .padding(.vertical, ShoppingRowLayout.verticalPadding)
        .background(cardBackground.opacity(0.01)) // Tap target
    }

    // MARK: - Rapid Entry Logic

    private func startRapidEntry() {
        cancelEditingItem()
        dismissInlineInsert()
        HapticManager.lightTap()
        withAnimation(WowAnimation.spring) {
            isRapidEntryActive = true
        }
        // Delay focus to allow animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            rapidEntryFocused = true
        }
    }

    private func handleRapidEntrySubmit() {
        let trimmedText = rapidEntryText.trimmingCharacters(in: .whitespaces)

        if trimmedText.isEmpty {
            // Empty submit: exit rapid entry
            dismissRapidEntry()
        } else {
            // Commit item and continue
            commitRapidEntryItem(trimmedText)
            rapidEntryText = ""
            HapticManager.selection()
            // Keep focus for next item
            rapidEntryFocused = true
        }
    }

    private func commitOrDismissRapidEntry() {
        let trimmedText = rapidEntryText.trimmingCharacters(in: .whitespaces)

        if !trimmedText.isEmpty {
            commitRapidEntryItem(trimmedText)
        }

        dismissRapidEntry()
    }

    private func commitRapidEntryItem(_ text: String) {
        _Concurrency.Task {
            let shouldDonateFirstAdd = store.toBuyItems.isEmpty && store.recentItems.isEmpty
            let createdItem = await store.createItem(title: text)

            guard createdItem != nil else { return }

            if shouldDonateFirstAdd {
                await MainActor.run {
                    AppTips.donateShoppingFirstItemCreated()
                }
            }
        }
    }

    private func dismissRapidEntry() {
        rapidEntryFocused = false
        rapidEntryText = ""
        withAnimation(WowAnimation.spring) {
            isRapidEntryActive = false
        }
    }

    private var currentEditingItem: ShoppingItem? {
        guard let editingItemId else { return nil }
        return store.toBuyItems.first(where: { $0.id == editingItemId })
    }

    private func startEditingItem(_ item: ShoppingItem) {
        dismissRapidEntry()
        dismissInlineInsert()
        editingItemId = item.id
        editingItemText = item.title
    }

    private func cancelEditingItem() {
        editingItemId = nil
        editingItemText = ""
    }

    private func commitEditingItem(_ item: ShoppingItem, openInlineComposer: Bool = false) {
        guard editingItemId == item.id else { return }
        let trimmed = editingItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { cancelEditingItem() }

        guard !trimmed.isEmpty else { return }

        if trimmed != item.title {
            var updatedItem = item
            updatedItem.title = trimmed
            _ = _Concurrency.Task {
                await store.updateItem(updatedItem)
            }
        }

        guard openInlineComposer else { return }
        startInlineInsert(after: item.id)
    }

    private func startInlineInsert(after itemId: UUID) {
        dismissRapidEntry()
        cancelEditingItem()
        inlineInsertAfterItemId = itemId
        inlineInsertText = ""
        inlineInsertRowToken = UUID()
    }

    private func dismissInlineInsert() {
        inlineInsertAfterItemId = nil
        inlineInsertText = ""
    }

    private func commitInlineInsertedItem(after itemId: UUID) {
        let trimmed = inlineInsertText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismissInlineInsert()
            return
        }

        let anchorId = itemId
        let title = trimmed
        inlineInsertText = ""

        _ = _Concurrency.Task {
            let createdItem = await store.createItem(title: title, afterItemId: anchorId)
            guard let createdItem else { return }

            await MainActor.run {
                inlineInsertAfterItemId = createdItem.id
                inlineInsertRowToken = UUID()
                HapticManager.selection()
            }
        }
    }

    // MARK: - Data Actions

    private func moveToBuyItems(from source: IndexSet, to destination: Int) {
        store.moveToBuyItems(from: source, to: destination, persist: true)
        HapticManager.lightTap()
    }

    private func toggleItem(_ item: ShoppingItem) {
        HapticManager.lightTap()
        let shouldCelebrateCompletion = store.toBuyItems.count == 1 && !item.isBought

        cancelPendingShoppingCompletionCelebration()
        cancelEditingItem()
        dismissInlineInsert()

        // Animate item removal
        withAnimation(WowAnimation.easeOut) {
            itemBeingRemoved = item.id
        }

        // Pulse restock icon
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            restockPulse.pulse()
            HapticManager.selection()
        }

        // Actually toggle after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            _Concurrency.Task {
                await store.toggleBought(item)
                await MainActor.run {
                    itemBeingRemoved = nil
                }
            }
        }

        if shouldCelebrateCompletion, themeStore.celebrationsEnabled {
            scheduleShoppingCompletionCelebration()
        }
    }

    private func restoreRecentItem(_ item: ShoppingItem) {
        _Concurrency.Task {
            await store.restoreRecentItem(item)
        }
        HapticManager.lightTap()
    }

    private func deleteRecentItem(_ item: ShoppingItem) {
        _Concurrency.Task {
            await store.deleteRecentItem(item)
        }
        HapticManager.lightTap()
    }

    private func clearRecentItems() {
        _Concurrency.Task {
            await store.clearRecentItems()
        }
        HapticManager.success()
    }

    private func clearToBuy() {
        _Concurrency.Task {
            await store.clearToBuy()
        }
        HapticManager.success()
    }

    private func loadShoppingData() async {
        updateStoreCloudContext()
        store.setSyncMode(userSession.syncMode)
        bundleStore.setSyncMode(userSession.syncMode)
        await store.loadItemsForDisplay()
        await bundleStore.loadBundlesForDisplay()
        markShoppingTutorialAsSeenIfNeeded()
    }

    private func performManualRefresh() async {
        if userSession.syncMode == .cloud {
            await syncCoordinator.performInteractiveManualRefresh()
        }
        await loadShoppingData()
    }

    private func updateStoreCloudContext() {
        let ownerId = householdStore.currentHousehold?.ownerId
        store.setCloudContext(currentUserId: userSession.userId, householdOwnerId: ownerId)
        bundleStore.setCloudContext(currentUserId: userSession.userId, householdOwnerId: ownerId)
    }

    private func isLocalStoreNotification(_ notification: Notification) -> Bool {
        (notification.object as? String) == "local"
    }

    private func handleRemoteShoppingListChange(_ notification: Notification) {
        let payload = notification.remoteSyncAnimationPayload
        let changedIDs = payload?.shoppingChangedItemIDs ?? []

        cancelRemoteSyncAnimationReset()
        isApplyingRemoteSyncAnimation = true

        _ = _Concurrency.Task { @MainActor in
            let refreshTask = RemoteVisibleRefreshTask(
                changedIDs: changedIDs,
                captureVisibleLocations: { shoppingVisibleLocations(from: store.toBuyItems) },
                rehydratePrimaryStore: {
                    withAnimation(WowAnimation.spring) {
                        store.rehydrateVisibleSnapshotFromCache()
                    }
                },
                refreshDependentStores: {
                    await bundleStore.loadBundlesForDisplay()
                }
            )

            let delta = await refreshTask.run()
            remoteHighlightedItemIDs = delta.highlightedIDs
            logRemoteSyncVisibleRefreshLatency(screen: "Shopping", payload: payload)
            scheduleRemoteSyncAnimationReset()
            markShoppingTutorialAsSeenIfNeeded()
        }
    }

    private func handleRemoteShoppingSyncBatch(_ batch: HouseholdSyncBatch) {
        if batch.classification == .bootstrap {
            cancelRemoteSyncAnimationReset()
            _ = _Concurrency.Task { @MainActor in
                store.rehydrateVisibleSnapshotFromCache()
                await bundleStore.loadBundlesForDisplay()
                markShoppingTutorialAsSeenIfNeeded()
            }
            return
        }

        let changedIDs = batch.shoppingChangedItemIDs

        cancelRemoteSyncAnimationReset()
        isApplyingRemoteSyncAnimation = true

        _ = _Concurrency.Task { @MainActor in
            let refreshTask = RemoteVisibleRefreshTask(
                changedIDs: changedIDs,
                captureVisibleLocations: { shoppingVisibleLocations(from: store.toBuyItems) },
                rehydratePrimaryStore: {
                    withAnimation(WowAnimation.spring) {
                        store.rehydrateVisibleSnapshotFromCache()
                    }
                },
                refreshDependentStores: {
                    await bundleStore.loadBundlesForDisplay()
                }
            )

            let delta = await refreshTask.run()
            remoteHighlightedItemIDs = delta.highlightedIDs
            scheduleRemoteSyncAnimationReset()
            markShoppingTutorialAsSeenIfNeeded()
        }
    }

    private func shoppingVisibleLocations(from items: [ShoppingItem]) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, 0) })
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
            remoteSyncResetTask = nil
        }
    }

    private func cancelRemoteSyncAnimationReset() {
        remoteSyncResetTask?.cancel()
        remoteSyncResetTask = nil
        isApplyingRemoteSyncAnimation = false
        remoteHighlightedItemIDs.removeAll()
    }

    private func scheduleShoppingCompletionCelebration() {
        pendingShoppingCompletionCelebrationTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(nanoseconds: 320_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            guard isScreenVisible else { return }
            celebrationManager.celebrateShoppingComplete()
            pendingShoppingCompletionCelebrationTask = nil
        }
    }

    private func cancelPendingShoppingCompletionCelebration() {
        pendingShoppingCompletionCelebrationTask?.cancel()
        pendingShoppingCompletionCelebrationTask = nil
    }

    private var quickAddBundles: [ShoppingBundle] {
        bundleStore.quickAddBundles
    }

    private func handleBundleQuickAdd(_ bundle: ShoppingBundle) {
        cancelEditingItem()
        dismissRapidEntry()
        dismissInlineInsert()

        _ = _Concurrency.Task {
            let addedCount = await store.createItems(fromTitles: bundle.normalizedItems)
            guard addedCount > 0 else { return }

            await MainActor.run {
                AppTips.donateBundleQuickAddUsed()
                HapticManager.success()
                showQuickAddToast(
                    message: quickAddToastMessage(
                        for: bundle.name,
                        itemCount: addedCount
                    )
                )
            }
        }
    }

    private func showQuickAddToast(message: String) {
        showToast(
            ShoppingToastState(message: message),
            durationNanoseconds: 2_000_000_000
        )
    }

    private func showToast(_ toast: ShoppingToastState, durationNanoseconds: UInt64) {
        cancelToastDismiss()

        withAnimation(ToastView.AnimationTokens.curve) {
            activeToast = toast
        }

        let toastID = toast.id
        activeToastDismissTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(nanoseconds: durationNanoseconds)
            guard !_Concurrency.Task.isCancelled else { return }
            guard activeToast?.id == toastID else { return }

            withAnimation(ToastView.AnimationTokens.curve) {
                activeToast = nil
            }
            activeToastDismissTask = nil
        }
    }

    private func cancelToastDismiss() {
        activeToastDismissTask?.cancel()
        activeToastDismissTask = nil
    }

    private func quickAddToastMessage(for bundleName: String, itemCount: Int) -> String {
        let noun = itemCount == 1 ? "item" : "items"
        return "Added \(bundleName) (\(itemCount) \(noun))"
    }

    private func markShoppingTutorialAsSeenIfNeeded() {
        guard !store.toBuyItems.isEmpty, !hasSeenShoppingTutorial else { return }
        hasSeenShoppingTutorial = true
    }

    private func rearmBundleQuickAddTipIfNeeded() {
        guard !hasCompletedShoppingBundleQuickAddTip else { return }
        guard !quickAddBundles.isEmpty else { return }
        appTipRuntimeGeneration += 1
    }

    private var activeShoppingTip: ShoppingOnboardingTip? {
        AppTipVisibility.shoppingTip(
            hasActiveItems: !store.toBuyItems.isEmpty,
            hasRecentItems: !store.recentItems.isEmpty,
            hasBundles: !bundleStore.bundles.isEmpty,
            hasQuickAddBundles: !quickAddBundles.isEmpty,
            isRapidEntryActive: isRapidEntryActive,
            isKeyboardVisible: isKeyboardVisible,
            hasActiveToast: activeToast != nil,
            hasPresentedSheet: showRestock || showClearToBuyConfirmation,
            hasCompletedFirstAdd: hasCompletedShoppingFirstAddTip,
            hasCompletedRecentPurchases: hasCompletedShoppingRecentPurchasesTip,
            hasCompletedBundlesLocation: hasCompletedShoppingBundlesLocationTip,
            hasCompletedBundleQuickAdd: hasCompletedShoppingBundleQuickAddTip
        )
    }

    private var cardBackground: Color {
        themeStore.surfaceColor
    }
}

// swiftlint:enable type_body_length

private struct ShoppingToastState: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

// MARK: - Shopping Item Row

struct ShoppingItemRow: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let item: ShoppingItem
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: ShoppingRowLayout.spacing) {
            ThemedCheckbox(
                isChecked: item.isBought,
                onToggle: onToggle,
                size: 20,
                style: .circle
            )
            .accessibilityIdentifier("shoppingToggle_\(item.title)")

            Button(action: onEdit) {
                Text(item.title)
                    .font(themeStore.font(for: .listRowTitle))
                    .foregroundStyle(
                        item.isBought
                            ? themeStore.contentSecondaryColor : themeStore.contentPrimaryColor
                    )
                    .strikethrough(item.isBought)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Color.clear
                .frame(width: ShoppingRowLayout.trailingSlotWidth, height: 24)
        }
        .frame(minHeight: ShoppingRowLayout.minRowHeight)
        .contentShape(Rectangle())
        .padding(.vertical, ShoppingRowLayout.verticalPadding)
        .accessibilityIdentifier("shoppingItemRow_\(item.title)")
    }
}

private enum ShoppingRowLayout {
    static let spacing: CGFloat = 10
    static let verticalPadding: CGFloat = 0
    static let minRowHeight: CGFloat = 30
    static let trailingSlotWidth: CGFloat = 24
}

private struct ShoppingItemInlineEditRow: View {
    @Binding var text: String
    let isBought: Bool
    let onToggle: () -> Void
    let onSubmit: () -> Void
    let onFocusLossCommit: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @FocusState private var isFocused: Bool
    @State private var isCancelling = false

    var body: some View {
        HStack(spacing: ShoppingRowLayout.spacing) {
            ThemedCheckbox(
                isChecked: isBought,
                onToggle: onToggle,
                size: 20,
                style: .circle
            )
            .accessibilityIdentifier("shoppingInlineEditToggle")

            TextField("Item name", text: $text)
                .font(themeStore.font(for: .listRowTitle))
                .submitLabel(.next)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onChange(of: isFocused) { _, focused in
                    if !focused, !isCancelling {
                        onFocusLossCommit()
                    }
                }
                .autocorrectionDisabled()

            Button {
                isCancelling = true
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: ShoppingRowLayout.trailingSlotWidth, height: 24)
        }
        .frame(minHeight: ShoppingRowLayout.minRowHeight)
        .contentShape(Rectangle())
        .padding(.vertical, ShoppingRowLayout.verticalPadding)
        .onAppear {
            isCancelling = false
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}

private struct ShoppingItemInlineComposerRow: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @FocusState private var isFocused: Bool
    @State private var isCancelling = false

    var body: some View {
        HStack(spacing: ShoppingRowLayout.spacing) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(themeStore.accentTabColor)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            TextField("Add item", text: $text)
                .font(themeStore.font(for: .listRowTitle))
                .submitLabel(.next)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onChange(of: isFocused) { _, focused in
                    guard !focused, !isCancelling else { return }
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onCancel()
                    } else {
                        onSubmit()
                    }
                }
                .autocorrectionDisabled()

            Button {
                isCancelling = true
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: ShoppingRowLayout.trailingSlotWidth, height: 24)
        }
        .frame(minHeight: ShoppingRowLayout.minRowHeight)
        .contentShape(Rectangle())
        .padding(.vertical, ShoppingRowLayout.verticalPadding)
        .onAppear {
            isCancelling = false
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}

private struct RapidEntryTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let actionColor: UIColor
    let actionForegroundColor: UIColor
    let onSubmit: () -> Void
    let onDone: () -> Void
    let themeStore: ThemeStore

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator

        let customFont = themeStore.uiFont(for: .listRowTitle)
        textField.font = customFont

        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: customFont,
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )

        textField.returnKeyType = .done
        textField.autocapitalizationType = .sentences
        textField.autocorrectionType = .yes
        textField.enablesReturnKeyAutomatically = false
        textField.addTarget(
            context.coordinator, action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        textField.inputAccessoryView = context.coordinator.makeAccessoryToolbar()
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.updateParent(self)

        if uiView.text != text {
            uiView.text = text
        }

        let customFont = themeStore.uiFont(for: .listRowTitle)
        if uiView.font != customFont {
            uiView.font = customFont
            uiView.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [
                    .font: customFont,
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
        }

        context.coordinator.updateAccessoryAppearance()

        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private var parent: RapidEntryTextField
        private weak var accessoryButton: UIButton?

        init(_ parent: RapidEntryTextField) {
            self.parent = parent
        }

        func updateParent(_ parent: RapidEntryTextField) {
            self.parent = parent
        }

        @objc
        func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_: UITextField) {
            parent.isFocused = false
        }

        func textFieldShouldReturn(_: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        func updateAccessoryAppearance() {
            guard let button = accessoryButton else { return }

            let title = NSAttributedString(
                string: "Done",
                attributes: [
                    .font: parent.themeStore.uiFont(for: .buttonLabel),
                    .foregroundColor: parent.actionForegroundColor,
                ]
            )
            button.setAttributedTitle(title, for: .normal)
            button.setAttributedTitle(title, for: .highlighted)
            button.backgroundColor = parent.actionColor
            button.layer.shadowColor = parent.actionColor.withAlphaComponent(0.3).cgColor
            button.layer.borderWidth = shouldShowAccessoryBorder ? 1.2 : 0
            button.layer.borderColor = accessoryBorderColor?.cgColor
            button.tintColor = parent.actionForegroundColor
        }

        func makeAccessoryToolbar() -> UIView {
            let topInset: CGFloat = 6
            let buttonHeight = AppChromeMetrics.compactCTAHeight
            let bottomInset = AppChromeMetrics.keyboardAccessoryBottomInset
            let containerHeight = topInset + buttonHeight + bottomInset

            let container = UIView(
                frame: CGRect(
                    x: 0, y: 0, width: 0, height: containerHeight
                )
            )
            container.backgroundColor = .clear

            // "Done" pill button matching the "Add item" style
            let button = UIButton(type: .custom)
            button.setTitle("Done", for: .normal)
            accessoryButton = button
            button.titleLabel?.font = parent.themeStore.uiFont(for: .buttonLabel)
            button.layer.cornerRadius = buttonHeight / 2
            button.contentEdgeInsets = UIEdgeInsets(
                top: 0,
                left: AppChromeMetrics.compactCTAHorizontalPadding,
                bottom: 0,
                right: AppChromeMetrics.compactCTAHorizontalPadding
            )
            button.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
            button.layer.shadowRadius = 8
            button.layer.shadowOffset = CGSize(width: 0, height: 4)
            button.layer.shadowOpacity = 1.0

            button.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(button)

            updateAccessoryAppearance()

            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(
                    equalTo: container.trailingAnchor,
                    constant: -AppChromeMetrics.horizontalInset
                ),
                button.bottomAnchor.constraint(
                    equalTo: container.bottomAnchor, constant: -bottomInset
                ),
                button.heightAnchor.constraint(equalToConstant: buttonHeight),
            ])

            return container
        }

        @objc
        private func doneTapped() {
            parent.onDone()
        }

        private var shouldShowAccessoryBorder: Bool {
            parent.themeStore.usesRetroChrome || parent.themeStore.preset == .paper
        }

        private var accessoryBorderColor: UIColor? {
            guard shouldShowAccessoryBorder else { return nil }
            return UIColor(parent.themeStore.borderLightColor.opacity(0.85))
        }
    }
}

// MARK: - Restock Sheet

struct RestockSheet: View {
    @ObservedObject var store: ShoppingListStore
    let onRestore: (ShoppingItem) -> Void
    let onDeleteItem: (ShoppingItem) -> Void
    let onClearAll: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var showClearAllConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                restockHeader

                Group {
                    if store.recentItems.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "cart")
                                .font(.system(size: 40, weight: .regular))
                                .foregroundStyle(themeStore.contentSecondaryColor)

                            Text("No Recent Purchases")
                                .font(themeStore.font(for: .inlineTitle))
                                .foregroundStyle(themeStore.contentPrimaryColor)

                            Text("Items marked as bought appear here for one-tap restore.")
                                .font(themeStore.font(for: .bodyStrong))
                                .foregroundStyle(themeStore.contentSecondaryColor)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        List {
                            ForEach(store.recentItems) { item in
                                RestockItemRow(
                                    item: item,
                                    onRestore: { onRestore(item) },
                                    onDelete: { onDeleteItem(item) }
                                )
                                .listRowInsets(
                                    EdgeInsets(top: -4, leading: 20, bottom: -4, trailing: 20)
                                )
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(themeStore.canvasColor)
                        .environment(\.font, themeStore.font(for: .listRowTitle))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(
                themeStore.canvasColor.ignoresSafeArea()
            )
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showClearAllConfirmation) {
                AppConfirmationSheet(
                    title: "Clear all recently purchased?",
                    message: "This permanently removes all items from the recently purchased list.",
                    primaryTitle: "Clear All",
                    primaryStyle: .destructive,
                    onPrimary: onClearAll
                )
            }
        }
        .background(themeStore.canvasColor.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(themeStore.canvasColor)
    }

    private var restockHeader: some View {
        ZStack {
            Text("Recently Purchased")
                .font(themeStore.font(for: .inlineTitle))
                .foregroundStyle(themeStore.contentPrimaryColor)

            HStack {
                if !store.recentItems.isEmpty {
                    Button(role: .destructive) {
                        showClearAllConfirmation = true
                    } label: {
                        Text("Clear")
                            .font(themeStore.font(for: .buttonLabel))
                            .foregroundStyle(.red)
                    }
                    .tint(.red)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .font(themeStore.font(for: .buttonLabel))
                .fontWeight(.semibold)
                .tint(themeStore.accentTabColor)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
}

private struct ShoppingQuickAddBundleSheet: View {
    let bundles: [ShoppingBundle]
    let onSelectBundle: (ShoppingBundle) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        NavigationStack {
            List(bundles) { bundle in
                Button {
                    onSelectBundle(bundle)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: bundle.resolvedIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(themeStore.accentTabColor)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(bundle.name)
                                .font(themeStore.font(for: .inlineTitle))
                                .foregroundStyle(themeStore.contentPrimaryColor)
                                .lineLimit(2)

                            Text(bundle.itemCount == 1 ? "1 item" : "\(bundle.itemCount) items")
                                .font(themeStore.font(for: .bodySmall))
                                .foregroundStyle(themeStore.contentSecondaryColor)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .background(themeStore.canvasColor.ignoresSafeArea())
            .navigationTitle("Quick Add Bundle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Quick Add Bundle")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(themeStore.canvasColor)
    }
}

private struct RestockItemRow: View {
    let item: ShoppingItem
    let onRestore: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        HStack {
            Text(item.title)
                .font(themeStore.font(for: .listRowTitle))
                .foregroundStyle(themeStore.contentPrimaryColor)
                .lineLimit(1)

            Spacer()

            Button {
                onRestore()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(themeStore.accentTabColor)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    ShoppingListView(selectedTab: .constant(.shopping))
        .environmentObject(UserSession.shared)
        .environmentObject(ThemeStore())
}
