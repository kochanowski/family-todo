import SwiftData
import SwiftUI
import UIKit

// swiftlint:disable file_length
/// Shopping List screen - quick capture and management of groceries
struct ShoppingListView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                ShoppingListContent(householdId: householdId, modelContext: modelContext)
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
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager

    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var celebrationManager: CelebrationManager
    @Environment(\.colorScheme) private var colorScheme

    // Rapid entry state
    @State private var isRapidEntryActive = false
    @State private var rapidEntryText = ""
    @State private var rapidEntryFocused = false

    @State private var showRestock = false
    @State private var showClearToBuyConfirmation = false
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
    @AppStorage("hasSeenShoppingTutorial") private var hasSeenShoppingTutorial = false
    @AppStorage(AppTipProgressKey.shoppingFirstAddCompleted)
    private var hasCompletedShoppingFirstAddTip = false
    @AppStorage(AppTipProgressKey.shoppingRecentPurchasesCompleted)
    private var hasCompletedShoppingRecentPurchasesTip = false
    @AppStorage(AppTipProgressKey.shoppingBundlesLocationCompleted)
    private var hasCompletedShoppingBundlesLocationTip = false
    @AppStorage(AppTipProgressKey.shoppingBundleQuickAddCompleted)
    private var hasCompletedShoppingBundleQuickAddTip = false

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(
            wrappedValue: ShoppingListStore(householdId: householdId, modelContext: modelContext)
        )
        _bundleStore = StateObject(
            wrappedValue: ShoppingBundleStore(householdId: householdId, modelContext: modelContext)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let listBottomInset =
                isKeyboardVisible
                    ? CGFloat(16)
                    : AppChromeMetrics.compactCTAHeight + 28
            let floatingButtonInset: CGFloat = 16
            let rapidEntryTapHeight = max(0, proxy.size.height - listBottomInset)
            let shouldShowEmptyState = store.toBuyItems.isEmpty && !isRapidEntryActive

            ZStack(alignment: .bottomTrailing) {
                if isRapidEntryActive {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: rapidEntryTapHeight, alignment: .top)
                        .onTapGesture {
                            commitOrDismissRapidEntry()
                        }
                }

                VStack(spacing: 0) {
                    // Header
                    header
                        .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                        .padding(.top, AppChromeMetrics.screenHeaderTopPadding)
                        .padding(.bottom, AppChromeMetrics.screenHeaderBottomPadding)

                    if shouldShowEmptyState {
                        shoppingEmptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                            .padding(.bottom, listBottomInset)
                    } else {
                        // Items list with rapid entry
                        ScrollViewReader { proxy in
                            List {
                                ForEach(store.toBuyItems) { item in
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
                                                .accessibilityIdentifier(
                                                    "shoppingItemEdit_\(item.title)"
                                                )
                                            } else {
                                                ShoppingItemRow(
                                                    item: item,
                                                    onToggle: { toggleItem(item) },
                                                    onEdit: { startEditingItem(item) }
                                                )
                                                .accessibilityIdentifier(
                                                    "shoppingItem_\(item.title)"
                                                )
                                            }
                                        }
                                    }
                                    .listRowInsets(
                                        EdgeInsets(
                                            top: 0,
                                            leading: 16,
                                            bottom: 0,
                                            trailing: 16
                                        )
                                    )
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)

                                    if inlineInsertAfterItemId == item.id {
                                        ShoppingItemInlineComposerRow(
                                            text: $inlineInsertText,
                                            onSubmit: { commitInlineInsertedItem(after: item.id) },
                                            onCancel: dismissInlineInsert
                                        )
                                        .id(inlineInsertRowToken)
                                        .listRowInsets(
                                            EdgeInsets(
                                                top: 0,
                                                leading: 16,
                                                bottom: 0,
                                                trailing: 16
                                            )
                                        )
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .accessibilityIdentifier("shoppingInlineInsertRow")
                                    }
                                }
                                .onMove(perform: moveToBuyItems)

                                // Rapid entry row (stable at bottom, no insert animation)
                                if isRapidEntryActive {
                                    rapidEntryRow
                                        .id("rapidEntry")
                                        .listRowInsets(
                                            EdgeInsets(
                                                top: 0,
                                                leading: 16,
                                                bottom: 0,
                                                trailing: 16
                                            )
                                        )
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
                                await loadShoppingData()
                            }
                            .onChange(of: rapidEntryFocused) { _, focused in
                                if focused {
                                    withAnimation(WowAnimation.spring) {
                                        proxy.scrollTo("rapidEntry", anchor: .bottom)
                                    }
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
                }

                // Compact floating add button
                if !isRapidEntryActive, !isKeyboardVisible {
                    addPillButton
                        .padding(.trailing, AppChromeMetrics.horizontalInset)
                        .padding(.bottom, floatingButtonInset)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            guard !didPerformInitialLoad else { return }
            didPerformInitialLoad = true
            await loadShoppingData()
        }
        .onChange(of: userSession.syncMode) { _, mode in
            store.setSyncMode(mode)
            bundleStore.setSyncMode(mode)
            _ = _Concurrency.Task {
                await loadShoppingData()
            }
        }
        .onChange(of: store.toBuyItems.isEmpty) { _, isEmpty in
            if !isEmpty {
                markShoppingTutorialAsSeenIfNeeded()
            }
        }
        .newItemsBanner(manager: subscriptionManager)
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
        ) { _ in
            _ = _Concurrency.Task {
                await loadShoppingData()
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
                primaryStyle: .destructive,
                onPrimary: clearToBuy
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
        }
        .onDisappear {
            isScreenVisible = false
            cancelPendingShoppingCompletionCelebration()
            cancelToastDismiss()
        }
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

    // MARK: - Header

    private var header: some View {
        AppScreenHeader(title: "Shopping") {
            if !store.toBuyItems.isEmpty {
                ShoppingCountBadge(count: store.toBuyItems.count)
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
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shoppingClearButton")
                }

                NavigationLink {
                    BundlesManagementView(store: bundleStore)
                } label: {
                    Image(systemName: ShoppingBundle.defaultIcon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(themeStore.contentSecondaryColor)
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
                    ShoppingBundlesLocationTip(),
                    arrowEdge: .top
                )

                // Recently purchased
                Button {
                    HapticManager.lightTap()
                    AppTips.donateShoppingRecentPurchasesOpened()
                    showRestock = true
                } label: {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shoppingRestockButton")
                .pulseAnimation(trigger: restockPulse.pulseToken)
                .contextualPopoverTip(
                    activeShoppingTip == .recentPurchases,
                    ShoppingRecentlyPurchasedTip(),
                    arrowEdge: .top
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

    @ViewBuilder
    private var addPillButton: some View {
        if quickAddBundles.isEmpty {
            addPillButtonBase
        } else {
            addPillButtonBase
                .contextMenu {
                    ForEach(quickAddBundles) { bundle in
                        Button {
                            handleBundleQuickAdd(bundle)
                        } label: {
                            Label(
                                "\(bundle.name) (\(bundle.itemCount))",
                                systemImage: bundle.resolvedIcon
                            )
                        }
                    }
                }
        }
    }

    private var addPillButtonBase: some View {
        let foreground = themeStore.foregroundOnAccent(
            for: themeStore.accentTabColor, colorScheme: colorScheme
        )

        return Button {
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
            ShoppingFirstAddTip(),
            arrowEdge: .bottom
        )
        .contextualPopoverTip(
            activeShoppingTip == .bundleQuickAdd,
            ShoppingBundleQuickAddTip(),
            arrowEdge: .bottom
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
        store.setSyncMode(userSession.syncMode)
        bundleStore.setSyncMode(userSession.syncMode)
        await store.loadItems()
        await bundleStore.loadBundles()
        markShoppingTutorialAsSeenIfNeeded()
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

            button.setTitleColor(parent.actionForegroundColor, for: .normal)
            button.backgroundColor = parent.actionColor
            button.titleLabel?.font = parent.themeStore.uiFont(for: .buttonLabel)
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
                    x: 0, y: 0, width: UIScreen.main.bounds.width, height: containerHeight
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
                                .font(themeStore.font(for: .sectionHeader))
                                .foregroundStyle(themeStore.contentPrimaryColor)

                            Text("Items marked as bought appear here for one-tap restore.")
                                .font(themeStore.font(for: .bodySmall))
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
    ShoppingListView()
        .environmentObject(UserSession.shared)
        .environmentObject(ThemeStore())
}
