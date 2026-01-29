// swiftlint:disable file_length
import SwiftData
import SwiftUI
import UIKit

// MARK: - Hybrid Navigation View (Redesign 2026-01-28)

/// Replaces card pager with tab-based navigation (3 main + More menu)
struct CardsPagerView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var userSession: UserSession
    @ObservedObject var householdStore: HouseholdStore
    @StateObject private var taskStore: TaskStore
    @StateObject private var shoppingListStore: ShoppingListStore
    @StateObject private var recurringChoreStore: RecurringChoreStore
    @StateObject private var areaStore: AreaStore
    @StateObject private var memberStore: MemberStore

    private let householdId: UUID

    // MARK: - Navigation State

    @State private var currentKind: CardKind = .todo
    @State private var moreMenuPresented = false
    @State private var keyboardHeight: CGFloat = 0

    // Legacy: keep for backward compatibility with card pager
    private let cardKinds = CardKind.displayOrder
    @State private var currentIndex = CardKind.defaultIndex
    @State private var dragOffset: CGFloat = 0
    @State private var swipeHapticTriggered = false

    private let edgeWidth: CGFloat = 6
    private let edgeOverlap: CGFloat = 3
    private let maxVisibleEdges = 3
    private let swipeThreshold: CGFloat = 50

    init(householdStore: HouseholdStore, householdId: UUID, modelContext: ModelContext) {
        self.householdStore = householdStore
        self.householdId = householdId
        _taskStore = StateObject(wrappedValue: TaskStore(modelContext: modelContext))
        _shoppingListStore = StateObject(
            wrappedValue: ShoppingListStore(householdId: householdId, modelContext: modelContext)
        )
        _recurringChoreStore = StateObject(
            wrappedValue: RecurringChoreStore(householdId: householdId, modelContext: modelContext)
        )
        _areaStore = StateObject(
            wrappedValue: AreaStore(householdId: householdId, modelContext: modelContext)
        )
        _memberStore = StateObject(
            wrappedValue: MemberStore(householdId: householdId, modelContext: modelContext)
        )
    }

    private var edgeSpacing: CGFloat {
        edgeWidth - edgeOverlap
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let safeInsets = proxy.safeAreaInsets
            let palette = themeStore.palette
            let theme = palette.theme(for: currentKind)
            let surfacePalette = AppColors.palette(for: themeStore.preset)
            let keyboardPadding = max(0, keyboardHeight - safeInsets.bottom)

            ZStack {
                // Warm canvas to match the journal-like reference UI
                surfacePalette.canvas
                    .ignoresSafeArea()

                // Main content based on selected tab
                mainContentView(for: currentKind, theme: theme, safeAreaInsets: safeInsets)
                    .frame(width: size.width, height: size.height)
                    .padding(
                        .top,
                        safeInsets.top + LayoutConstants.headerHeight + LayoutConstants.contentTopPadding
                    ) // Space for header
                    .padding(
                        .bottom,
                        safeInsets.bottom + LayoutConstants.footerHeight
                            + LayoutConstants.contentBottomPadding
                    ) // Space for tab bar - no keyboard padding here to keep tab bar at bottom

                // Simple Header (not floating, fixed at top)
                VStack(spacing: 0) {
                    SimpleHeaderView(
                        title: currentKind.title,
                        subtitle: cardSubtitle(for: currentKind)
                    )
                    .padding(.top, safeInsets.top + LayoutConstants.headerSafePadding)
                    .background(surfacePalette.canvas)

                    Spacer()
                }

                // Tab Bar at bottom (like in screenshot)
                VStack {
                    Spacer()
                    ModernTabBarView(
                        currentKind: currentKind,
                        badgeProvider: { badgeCount(for: $0) },
                        onSelect: { kind in
                            withAnimation(CardAnimations.cardSwitch) {
                                currentKind = kind
                            }
                            EnhancedHaptics.cardChanged()
                        },
                        onMoreTap: {
                            moreMenuPresented = true
                        }
                    )
                    .padding(.bottom, safeInsets.bottom + LayoutConstants.footerSafePadding)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .frame(width: size.width, height: size.height)
            .sheet(isPresented: $moreMenuPresented) {
                MoreMenuView(
                    currentKind: $currentKind,
                    themeProvider: { palette.theme(for: $0) },
                    badgeProvider: { badgeCount(for: $0) },
                    isPresented: $moreMenuPresented
                )
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillShowNotification
                )
            ) { notification in
                guard
                    let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect
                else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    keyboardHeight = frame.height
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillHideNotification
                )
            ) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    keyboardHeight = 0
                }
            }
        }
        .environment(\.colorScheme, themeStore.preset == .night ? .dark : .light)
        .task(id: householdId) {
            await loadAllData()
        }
        .onChange(of: userSession.syncMode) { _, newMode in
            updateSyncMode(newMode)
        }
    }

    // MARK: - Main Content View

    @ViewBuilder
    private func mainContentView(for kind: CardKind, theme: CardTheme, safeAreaInsets: EdgeInsets)
        -> some View
    {
        switch kind {
        case .shoppingList:
            shoppingListCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .todo:
            todoCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .household:
            householdCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .backlog:
            backlogCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .recurring:
            recurringCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .areas:
            areasCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .settings:
            settingsCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        }
    }

    // MARK: - Badge Count Helper

    private func badgeCount(for kind: CardKind) -> Int {
        switch kind {
        case .shoppingList:
            shoppingListStore.toBuyItems.count
        case .todo:
            taskStore.nextTasks.count
        case .backlog:
            taskStore.backlogTasks.count
        case .recurring:
            recurringChoreStore.chores.count
        case .household:
            memberStore.members.count
        case .areas:
            areaStore.areas.count
        case .settings:
            0
        }
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        taskStore.setSyncMode(userSession.syncMode)
        shoppingListStore.setSyncMode(userSession.syncMode)
        recurringChoreStore.setSyncMode(userSession.syncMode)
        areaStore.setSyncMode(userSession.syncMode)
        memberStore.setSyncMode(userSession.syncMode)
        taskStore.setHousehold(householdId)

        await taskStore.loadTasks()
        await shoppingListStore.loadItems()
        await recurringChoreStore.loadChores()
        await areaStore.loadAreas()
        await memberStore.loadMembers()
    }

    private func updateSyncMode(_ mode: SyncMode) {
        taskStore.setSyncMode(mode)
        shoppingListStore.setSyncMode(mode)
        recurringChoreStore.setSyncMode(mode)
        areaStore.setSyncMode(mode)
        memberStore.setSyncMode(mode)
    }

    // MARK: - Legacy Card Pager (kept for reference - not used in hybrid navigation)

    /// Note: All card pager logic is preserved but not used. Remove in future cleanup.
    private var legacyCardPager: some View {
        EmptyView()
    }

    // MARK: - Smart Header Helpers (Redesign 2026-01-28)

    private func cardSubtitle(for kind: CardKind) -> String? {
        switch kind {
        case .shoppingList:
            let count = shoppingListStore.toBuyItems.count
            return count == 1 ? "1 item to buy" : "\(count) items to buy"
        case .todo:
            let count = taskStore.nextTasks.count
            return count == 1 ? "1 task remaining" : "\(count) tasks remaining"
        case .backlog:
            let count = taskStore.backlogTasks.count
            return count == 1 ? "1 idea in backlog" : "\(count) ideas in backlog"
        case .recurring:
            let count = recurringChoreStore.chores.count
            return count == 1 ? "1 recurring task" : "\(count) recurring tasks"
        case .household:
            let count = memberStore.members.count
            return count == 1 ? "1 member" : "\(count) members"
        case .areas:
            let count = areaStore.areas.count
            return count == 1 ? "1 area" : "\(count) areas"
        case .settings:
            return "Theme & preferences"
        }
    }

    private func cardProgress(for kind: CardKind) -> Double {
        switch kind {
        case .shoppingList:
            let total = shoppingListStore.items.count
            let bought = shoppingListStore.boughtItems.count
            return total > 0 ? Double(bought) / Double(total) : 0
        case .todo:
            let total = taskStore.tasks.count
            let done = taskStore.tasks.filter { $0.status == .done }.count
            return total > 0 ? Double(done) / Double(total) : 0
        default:
            return 0
        }
    }

    @ViewBuilder
    private func cardView(for kind: CardKind, theme: CardTheme, safeAreaInsets: EdgeInsets)
        -> some View
    {
        switch kind {
        case .shoppingList:
            shoppingListCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .todo:
            todoCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .backlog:
            backlogCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .recurring:
            recurringCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .household:
            householdCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .areas:
            areasCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        case .settings:
            settingsCard(kind: kind, theme: theme, safeAreaInsets: safeAreaInsets)
        }
    }

    private func shoppingListCard(kind: CardKind, theme: CardTheme, safeAreaInsets: EdgeInsets)
        -> some View
    {
        ShoppingListCardView(
            kind: kind,
            theme: theme,
            store: shoppingListStore,
            safeAreaInsets: safeAreaInsets
        )
    }

    private func todoCard(kind: CardKind, theme: CardTheme, safeAreaInsets: EdgeInsets) -> some View {
        TodoCardView(
            kind: kind,
            theme: theme,
            taskStore: taskStore,
            memberStore: memberStore,
            currentMemberId: householdStore.currentMember?.id,
            safeAreaInsets: safeAreaInsets
        )
    }

    private func backlogCard(kind: CardKind, theme: CardTheme, safeAreaInsets: EdgeInsets)
        -> some View
    {
        BacklogCardView(
            kind: kind,
            theme: theme,
            taskStore: taskStore,
            memberStore: memberStore,
            currentMemberId: householdStore.currentMember?.id,
            safeAreaInsets: safeAreaInsets
        )
    }

    private func recurringCard(kind: CardKind, theme: CardTheme, safeAreaInsets: EdgeInsets)
        -> some View
    {
        RecurringCardView(
            kind: kind,
            theme: theme,
            choreStore: recurringChoreStore,
            memberStore: memberStore,
            taskStore: taskStore,
            currentMemberId: householdStore.currentMember?.id,
            safeAreaInsets: safeAreaInsets
        )
    }

    private func householdCard(kind: CardKind, theme: CardTheme, safeAreaInsets: EdgeInsets)
        -> some View
    {
        HouseholdCardView(
            kind: kind,
            theme: theme,
            householdStore: householdStore,
            memberStore: memberStore,
            safeAreaInsets: safeAreaInsets
        )
    }

    private func areasCard(kind: CardKind, theme: CardTheme, safeAreaInsets: EdgeInsets)
        -> some View
    {
        AreasCardView(
            kind: kind,
            theme: theme,
            areaStore: areaStore,
            safeAreaInsets: safeAreaInsets
        )
    }

    private func settingsCard(kind: CardKind, theme: CardTheme, safeAreaInsets: EdgeInsets)
        -> some View
    {
        SettingsCardView(
            kind: kind,
            theme: theme,
            themeStore: themeStore,
            safeAreaInsets: safeAreaInsets
        )
    }

    private func cardOffset(for index: Int, width: CGFloat) -> CGFloat {
        if index == currentIndex {
            return dragOffset
        }

        if index > currentIndex {
            let rightCount = cardKinds.count - 1 - currentIndex
            let visibleCount = min(maxVisibleEdges, rightCount)
            let relative = index - currentIndex

            guard relative <= visibleCount else {
                return width + edgeWidth
            }

            let baseOffset = width - (edgeWidth + edgeSpacing * CGFloat(relative - 1))
            let dragAdjustment = dragOffset < 0 ? dragOffset * 0.3 : 0
            return baseOffset + dragAdjustment
        }

        let leftCount = currentIndex
        let visibleCount = min(maxVisibleEdges, leftCount)
        let relative = currentIndex - index

        guard relative <= visibleCount else {
            return -(width + edgeWidth)
        }

        let baseOffset = -(width - (edgeWidth + edgeSpacing * CGFloat(relative - 1)))
        let dragAdjustment = dragOffset > 0 ? dragOffset * 0.3 : 0
        return baseOffset + dragAdjustment
    }

    private func cardOpacity(for index: Int) -> Double {
        if index == currentIndex {
            return 1
        }

        // Enhanced opacity with blur-like effect for non-active cards
        let baseOpacity = 0.75
        let progress = min(1, abs(dragOffset) / 120)

        if index == currentIndex + 1, dragOffset < 0 {
            return baseOpacity + (1 - baseOpacity) * Double(progress)
        }

        if index == currentIndex - 1, dragOffset > 0 {
            return baseOpacity + (1 - baseOpacity) * Double(progress)
        }

        // Further reduce opacity for cards further away
        let distance = abs(index - currentIndex)
        return max(0.4, baseOpacity - Double(distance) * 0.15)
    }

    private func cardScale(for index: Int) -> CGFloat {
        if index == currentIndex {
            return 1.0
        }

        let distance = abs(index - currentIndex)
        let baseScale: CGFloat = 0.95
        let progress = CGFloat(min(1, abs(dragOffset) / 120))

        if distance == 1 {
            // Neighboring cards scale up when dragging towards them
            if (index == currentIndex + 1 && dragOffset < 0) ||
                (index == currentIndex - 1 && dragOffset > 0)
            {
                return baseScale + (1.0 - baseScale) * progress
            }
        }

        return max(0.9, baseScale - CGFloat(distance - 1) * 0.03)
    }

    private func zIndex(for index: Int) -> Double {
        if index == currentIndex {
            return 0
        }

        return Double(index + cardKinds.count)
    }

    private func cardDragGesture(width _: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let translation = value.translation.width
                let isAtStart = currentIndex == 0
                let isAtEnd = currentIndex == cardKinds.count - 1

                if (translation > 0 && isAtStart) || (translation < 0 && isAtEnd) {
                    dragOffset = translation * 0.2
                } else {
                    dragOffset = translation
                }

                if !swipeHapticTriggered {
                    EnhancedHaptics.cardChanged()
                    swipeHapticTriggered = true
                }
            }
            .onEnded { value in
                swipeHapticTriggered = false

                let translation = value.translation.width
                if translation < -swipeThreshold, currentIndex < cardKinds.count - 1 {
                    withAnimation(CardAnimations.cardSwitch) {
                        currentIndex += 1
                    }
                    EnhancedHaptics.cardChanged()
                } else if translation > swipeThreshold, currentIndex > 0 {
                    withAnimation(CardAnimations.cardSwitch) {
                        currentIndex -= 1
                    }
                    EnhancedHaptics.cardChanged()
                }

                withAnimation(CardAnimations.cardSwitch) {
                    dragOffset = 0
                }
            }
    }

    @ViewBuilder
    private func edgeTapZones(size: CGSize) -> some View {
        let leftCount = min(maxVisibleEdges, currentIndex)
        let rightCount = min(maxVisibleEdges, cardKinds.count - 1 - currentIndex)

        ZStack {
            HStack(spacing: -edgeOverlap) {
                ForEach(0 ..< leftCount, id: \.self) { offset in
                    let targetIndex = currentIndex - leftCount + offset
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: edgeWidth, height: size.height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            switchTo(index: targetIndex)
                        }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: -edgeOverlap) {
                Spacer(minLength: 0)
                ForEach(0 ..< rightCount, id: \.self) { offset in
                    let targetIndex = currentIndex + offset + 1
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: edgeWidth, height: size.height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            switchTo(index: targetIndex)
                        }
                }
            }
        }
    }

    private func switchTo(index: Int) {
        guard index != currentIndex, cardKinds.indices.contains(index) else { return }
        EnhancedHaptics.cardChanged()
        withAnimation(CardAnimations.cardSwitch) {
            currentIndex = index
        }
    }
}

struct ShoppingListCardView: View {
    let kind: CardKind
    let theme: CardTheme
    @ObservedObject var store: ShoppingListStore
    let safeAreaInsets: EdgeInsets

    @EnvironmentObject private var settingsStore: ShoppingListSettingsStore
    @State private var restockPresented = false
    @State private var showClearConfirmation = false
    @State private var pendingDrops: Set<UUID> = []

    private var itemLookup: [UUID: ShoppingItem] {
        Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0) })
    }

    private var restockItems: [ShoppingItem] {
        Array(store.boughtItems.prefix(settingsStore.suggestionLimit))
    }

    private var cardItems: [CardListItem] {
        store.toBuyItems.map { item in
            CardListItem(
                id: item.id,
                title: item.title,
                isCompleted: item.isBought || pendingDrops.contains(item.id),
                secondaryText: item.quantityDisplay,
                quantityValue: item.quantityValue,
                quantityUnit: item.quantityUnit
            )
        }
    }

    private var subtitle: String {
        kind.subtitle(for: store.toBuyItems.count)
    }

    private var restockAccessory: AnyView? {
        let hasRestock = !restockItems.isEmpty
        let hasToBuy = !store.toBuyItems.isEmpty

        guard hasRestock || hasToBuy else { return nil }

        return AnyView(
            VStack(spacing: 12) {
                if hasRestock {
                    restockSection
                }
                if hasToBuy {
                    clearToBuyButton
                }
            }
        )
    }

    var body: some View {
        ZStack {
            CardPageView(
                kind: kind,
                theme: theme,
                layout: .compactShopping,
                subtitle: subtitle,
                items: cardItems,
                safeAreaInsets: safeAreaInsets,
                isLoading: store.isLoading,
                showsQuantity: true,
                emptyMessage: "Add your first item",
                showsInput: true,
                accessoryView: restockAccessory,
                onAdd: { title in
                    _Concurrency.Task {
                        await store.createItem(title: title)
                    }
                },
                onToggle: { item in
                    guard let shoppingItem = itemLookup[item.id] else { return }

                    // If marking as bought, add to pending drops
                    if !shoppingItem.isBought {
                        pendingDrops.insert(item.id)

                        // Auto-drop after 0.25s (faster animation)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            // Check if still pending (user didn't undo)
                            if pendingDrops.contains(item.id) {
                                _Concurrency.Task {
                                    await store.toggleBought(shoppingItem)
                                }
                                pendingDrops.remove(item.id)
                            }
                        }
                    } else {
                        // Unmarking - toggle immediately, cancel pending drop
                        pendingDrops.remove(item.id)
                        _Concurrency.Task {
                            await store.toggleBought(shoppingItem)
                        }
                    }
                },
                onDelete: { item in
                    guard let shoppingItem = itemLookup[item.id] else { return }
                    _Concurrency.Task {
                        await store.deleteItem(shoppingItem)
                    }
                },
                onUpdate: { item, title, quantityValue, quantityUnit in
                    guard var shoppingItem = itemLookup[item.id] else { return }
                    shoppingItem.title = title
                    shoppingItem.quantityValue = quantityValue
                    shoppingItem.quantityUnit = quantityUnit
                    _Concurrency.Task {
                        await store.updateItem(shoppingItem)
                    }
                }
            )

            if restockPresented {
                RestockModalView(
                    theme: theme,
                    items: restockItems,
                    onRestore: { item in
                        let isLastItem = restockItems.count == 1
                        _Concurrency.Task {
                            await store.toggleBought(item)
                        }
                        if isLastItem {
                            restockPresented = false
                        }
                    },
                    onDismiss: {
                        restockPresented = false
                    }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: restockPresented)
        .confirmationDialog(
            "Clear all items from To Buy list?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                _Concurrency.Task {
                    await store.clearToBuy()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var clearToBuyButton: some View {
        Button {
            Haptics.light()
            showClearConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(PressableIconButtonStyle())
    }

    private var restockSection: some View {
        Button {
            Haptics.light()
            restockPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bag.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Restock List (\(restockItems.count))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(restockPreview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(Color.gray.opacity(0.1))
            )
            .overlay(
                Rectangle()
                    .fill(theme.accentColor.opacity(0.15))
                    .frame(height: 0.5),
                alignment: .top
            )
        }
        .buttonStyle(PressableCardButtonStyle())
    }

    private var restockPreview: String {
        let names = restockItems.prefix(3).map(\.title)
        if names.isEmpty {
            return ""
        }
        let joined = names.joined(separator: ", ")
        return restockItems.count > 3 ? "\(joined)..." : joined
    }
}

struct RestockModalView: View {
    let theme: CardTheme
    let items: [ShoppingItem]
    let onRestore: (ShoppingItem) -> Void
    let onDismiss: () -> Void
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width * 0.9
            let maxHeight = proxy.size.height * 0.7
            let palette = AppColors.palette(for: themeStore.preset)

            ZStack {
                Color.black.opacity(0.4)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }

                VStack(spacing: 16) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "bag.fill")
                            Text("Restock List")
                        }
                        .font(.headline.weight(.bold))

                        Spacer()

                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .background(Color.secondary.opacity(0.15), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if items.isEmpty {
                        Text("Restock list is empty")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            FlowLayout(spacing: 12) {
                                ForEach(items) { item in
                                    Button {
                                        Haptics.light()
                                        onRestore(item)
                                    } label: {
                                        Text(item.title)
                                            .font(
                                                wordCloudFont(for: item.id).weight(
                                                    wordCloudWeight(for: item.id)
                                                )
                                            )
                                            .foregroundStyle(theme.primaryTextColor)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                theme.accentColor.opacity(0.2), in: Capsule()
                                            )
                                            .shadow(
                                                color: Color.black.opacity(0.1), radius: 3, x: 0,
                                                y: 2
                                            )
                                    }
                                    .buttonStyle(RestockChipButtonStyle())
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            }
        }
        .ignoresSafeArea()
    }

    private func wordCloudFont(for id: UUID) -> Font {
        let hash = abs(id.uuidString.hashValue)
        let size = 12 + (hash % 7)
        return .system(size: CGFloat(size))
    }

    private func wordCloudWeight(for id: UUID) -> Font.Weight {
        let hash = abs(id.uuidString.hashValue)
        return hash % 2 == 0 ? .regular : .semibold
    }
}

struct RestockChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.05 : 1)
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.2 : 0.1),
                radius: configuration.isPressed ? 6 : 3, x: 0, y: 2
            )
    }
}

struct TodoCardView: View {
    let kind: CardKind
    let theme: CardTheme
    @ObservedObject var taskStore: TaskStore
    @ObservedObject var memberStore: MemberStore
    let currentMemberId: UUID?
    let safeAreaInsets: EdgeInsets

    @State private var wipAlertPresented = false

    private var taskLookup: [UUID: Task] {
        Dictionary(uniqueKeysWithValues: taskStore.nextTasks.map { ($0.id, $0) })
    }

    private var cardItems: [CardListItem] {
        taskStore.nextTasks.map { task in
            CardListItem(
                id: task.id,
                title: task.title,
                assigneeInitials: assigneeInitials(for: task)
            )
        }
    }

    private var subtitle: String {
        kind.subtitle(for: taskStore.nextTasks.count)
    }

    var body: some View {
        CardPageView(
            kind: kind,
            theme: theme,
            layout: .standard,
            subtitle: subtitle,
            items: cardItems,
            safeAreaInsets: safeAreaInsets,
            isLoading: taskStore.isLoading,
            showsQuantity: false,
            emptyMessage: nil,
            showsInput: true,
            accessoryView: nil,
            onAdd: { title in
                guard canAddToNext() else {
                    wipAlertPresented = true
                    return
                }
                let assigneeIds = currentMemberId.map { [$0] } ?? []
                _Concurrency.Task {
                    await taskStore.createTask(
                        title: title, status: .next, assigneeId: currentMemberId,
                        assigneeIds: assigneeIds
                    )
                }
            },
            onToggle: { item in
                guard let task = taskLookup[item.id] else { return }
                _Concurrency.Task {
                    await taskStore.moveTask(task, to: .done)
                }
            },
            onDelete: { item in
                guard let task = taskLookup[item.id] else { return }
                _Concurrency.Task {
                    await taskStore.deleteTask(task)
                }
            },
            onUpdate: { item, title, _, _ in
                guard var task = taskLookup[item.id] else { return }
                task.title = title
                _Concurrency.Task {
                    await taskStore.updateTask(task)
                }
            }
        )
        .alert("WIP limit reached", isPresented: $wipAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Complete or move tasks before adding more to Next.")
        }
    }

    private func canAddToNext() -> Bool {
        guard let currentMemberId else { return true }
        return taskStore.canMoveToNext(assigneeId: currentMemberId)
    }

    private func assigneeInitials(for task: Task) -> [String] {
        let ids = resolvedAssigneeIds(for: task)
        let members = memberStore.members
        return ids.compactMap { id in
            members.first { $0.id == id }?.displayName.initials
        }
    }

    private func resolvedAssigneeIds(for task: Task) -> [UUID] {
        if !task.assigneeIds.isEmpty {
            return task.assigneeIds
        }
        if let assigneeId = task.assigneeId {
            return [assigneeId]
        }
        return memberStore.members.map(\.id)
    }
}

struct BacklogCardView: View {
    let kind: CardKind
    let theme: CardTheme
    @ObservedObject var taskStore: TaskStore
    @ObservedObject var memberStore: MemberStore
    let currentMemberId: UUID?
    let safeAreaInsets: EdgeInsets

    @State private var wipAlertPresented = false

    private var taskLookup: [UUID: Task] {
        Dictionary(uniqueKeysWithValues: taskStore.backlogTasks.map { ($0.id, $0) })
    }

    private var cardItems: [CardListItem] {
        taskStore.backlogTasks.map { task in
            CardListItem(
                id: task.id,
                title: task.title,
                assigneeInitials: assigneeInitials(for: task)
            )
        }
    }

    private var subtitle: String {
        kind.subtitle(for: taskStore.backlogTasks.count)
    }

    var body: some View {
        CardPageView(
            kind: kind,
            theme: theme,
            layout: .standard,
            subtitle: subtitle,
            items: cardItems,
            safeAreaInsets: safeAreaInsets,
            isLoading: taskStore.isLoading,
            showsQuantity: false,
            emptyMessage: "Everything is done!",
            showsInput: true,
            accessoryView: nil,
            onAdd: { title in
                _Concurrency.Task {
                    await taskStore.createTask(title: title, status: .backlog)
                }
            },
            onToggle: { item in
                guard let task = taskLookup[item.id] else { return }
                promoteToNext(task)
            },
            onDelete: { item in
                guard let task = taskLookup[item.id] else { return }
                _Concurrency.Task {
                    await taskStore.deleteTask(task)
                }
            },
            onUpdate: { item, title, _, _ in
                guard var task = taskLookup[item.id] else { return }
                task.title = title
                _Concurrency.Task {
                    await taskStore.updateTask(task)
                }
            }
        )
        .alert("WIP limit reached", isPresented: $wipAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Complete or move tasks before adding more to Next.")
        }
    }

    private func promoteToNext(_ task: Task) {
        if let currentMemberId, !taskStore.canMoveToNext(assigneeId: currentMemberId) {
            wipAlertPresented = true
            return
        }

        var updatedTask = task
        updatedTask.status = .next
        if let currentMemberId {
            updatedTask.assigneeId = currentMemberId
            updatedTask.assigneeIds = [currentMemberId]
        }

        _Concurrency.Task {
            await taskStore.updateTask(updatedTask)
        }
    }

    private func assigneeInitials(for task: Task) -> [String] {
        let ids = resolvedAssigneeIds(for: task)
        let members = memberStore.members
        return ids.compactMap { id in
            members.first { $0.id == id }?.displayName.initials
        }
    }

    private func resolvedAssigneeIds(for task: Task) -> [UUID] {
        if !task.assigneeIds.isEmpty {
            return task.assigneeIds
        }
        if let assigneeId = task.assigneeId {
            return [assigneeId]
        }
        return memberStore.members.map(\.id)
    }
}

struct RecurringCardView: View {
    let kind: CardKind
    let theme: CardTheme
    @ObservedObject var choreStore: RecurringChoreStore
    @ObservedObject var memberStore: MemberStore
    @ObservedObject var taskStore: TaskStore
    let currentMemberId: UUID?
    let safeAreaInsets: EdgeInsets

    private var choreLookup: [UUID: RecurringChore] {
        Dictionary(uniqueKeysWithValues: choreStore.chores.map { ($0.id, $0) })
    }

    private var orderedChores: [RecurringChore] {
        let active = choreStore.chores.filter(\.isActive).sorted { $0.title < $1.title }
        let paused = choreStore.chores.filter { !$0.isActive }.sorted { $0.title < $1.title }
        return active + paused
    }

    private var cardItems: [CardListItem] {
        orderedChores.map { chore in
            CardListItem(
                id: chore.id,
                title: chore.title,
                secondaryText: recurrenceDescription(for: chore),
                detailIconName: "calendar.badge.clock",
                assigneeInitials: assigneeInitials(for: chore),
                allowsToggle: chore.isActive
            )
        }
    }

    private var subtitle: String {
        kind.subtitle(for: choreStore.chores.count)
    }

    var body: some View {
        CardPageView(
            kind: kind,
            theme: theme,
            layout: .standard,
            subtitle: subtitle,
            items: cardItems,
            safeAreaInsets: safeAreaInsets,
            isLoading: choreStore.isLoading,
            showsQuantity: false,
            emptyMessage: "Add a recurring task",
            showsInput: true,
            accessoryView: nil,
            onAdd: { title in
                let assigneeIds = currentMemberId.map { [$0] } ?? []
                _Concurrency.Task {
                    await choreStore.createChore(
                        title: title,
                        recurrenceType: .everyNWeeks,
                        recurrenceInterval: 2,
                        defaultAssigneeIds: assigneeIds
                    )
                }
            },
            onToggle: { item in
                guard let chore = choreLookup[item.id] else { return }
                _Concurrency.Task {
                    await choreStore.generateTask(from: chore, taskStore: taskStore)
                }
            },
            onDelete: { item in
                guard let chore = choreLookup[item.id] else { return }
                _Concurrency.Task {
                    await choreStore.deleteChore(chore)
                }
            },
            onUpdate: { item, title, _, _ in
                guard var chore = choreLookup[item.id] else { return }
                chore.title = title
                _Concurrency.Task {
                    await choreStore.updateChore(chore)
                }
            }
        )
    }

    private func recurrenceDescription(for chore: RecurringChore) -> String {
        switch chore.recurrenceType {
        case .daily:
            return "Every day"
        case .weekly:
            if let weekday = chore.recurrenceDay {
                let formatter = DateFormatter()
                let name = formatter.weekdaySymbols[weekday - 1]
                return "Every \(name)"
            }
            return "Every week"
        case .biweekly:
            return "Every 2 weeks"
        case .monthly:
            if let day = chore.recurrenceDayOfMonth {
                return "Every month on day \(day)"
            }
            return "Every month"
        case .everyNDays:
            let interval = chore.recurrenceInterval ?? 1
            return "Every \(interval) day\(interval == 1 ? "" : "s")"
        case .everyNWeeks:
            let interval = chore.recurrenceInterval ?? 1
            return "Every \(interval) week\(interval == 1 ? "" : "s")"
        case .everyNMonths:
            let interval = chore.recurrenceInterval ?? 1
            return "Every \(interval) month\(interval == 1 ? "" : "s")"
        }
    }

    private func assigneeInitials(for chore: RecurringChore) -> [String] {
        let ids = resolvedAssigneeIds(for: chore)
        let members = memberStore.members
        return ids.compactMap { id in
            members.first { $0.id == id }?.displayName.initials
        }
    }

    private func resolvedAssigneeIds(for chore: RecurringChore) -> [UUID] {
        if !chore.defaultAssigneeIds.isEmpty {
            return chore.defaultAssigneeIds
        }
        return memberStore.members.map(\.id)
    }
}

struct HouseholdCardView: View {
    let kind: CardKind
    let theme: CardTheme
    @ObservedObject var householdStore: HouseholdStore
    @ObservedObject var memberStore: MemberStore
    @EnvironmentObject var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    let safeAreaInsets: EdgeInsets

    private var subtitle: String {
        householdStore.currentHousehold?.name ?? kind.subtitle(for: memberStore.members.count)
    }

    var body: some View {
        let surfacePalette = AppColors.palette(for: themeStore.preset)
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.primaryTextColor)

                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.secondaryTextColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, LayoutConstants.contentTopPadding)

                // Navigation to Member Management
                NavigationLink {
                    MemberManagementView(
                        memberStore: memberStore,
                        householdStore: householdStore
                    )
                    .environmentObject(userSession)
                } label: {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Members (\(memberStore.members.count))")
                            .font(.subheadline.bold())
                            .foregroundStyle(theme.primaryTextColor)

                        if memberStore.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if memberStore.members.isEmpty {
                            Text("Invite your first member")
                                .font(.body)
                                .foregroundStyle(theme.secondaryTextColor)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(memberStore.members.prefix(3)) { member in
                                HStack(spacing: 12) {
                                    Image(
                                        systemName: member.role == .owner
                                            ? "star.fill" : "person.fill"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        member.role == .owner ? .yellow : theme.secondaryTextColor
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.displayName)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(theme.primaryTextColor)
                                        Text(member.role == .owner ? "Owner" : "Member")
                                            .font(.caption)
                                            .foregroundStyle(theme.secondaryTextColor)
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(surfacePalette.surfaceElevated)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(surfacePalette.borderLight, lineWidth: 1)
                                        )
                                )
                            }

                            if memberStore.members.count > 3 {
                                Text("+ \(memberStore.members.count - 3) more")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryTextColor.opacity(0.7))
                                    .padding(.top, 4)
                            }
                        }

                        // Tap to manage hint
                        HStack {
                            Spacer()
                            Text("Tap to manage members")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct AreasCardView: View {
    let kind: CardKind
    let theme: CardTheme
    @ObservedObject var areaStore: AreaStore
    let safeAreaInsets: EdgeInsets

    private var areaLookup: [UUID: Area] {
        Dictionary(uniqueKeysWithValues: areaStore.areas.map { ($0.id, $0) })
    }

    private var cardItems: [CardListItem] {
        areaStore.areas.map { area in
            CardListItem(
                id: area.id,
                title: area.name,
                secondaryText: "Area",
                allowsToggle: false
            )
        }
    }

    private var subtitle: String {
        kind.subtitle(for: areaStore.areas.count)
    }

    var body: some View {
        CardPageView(
            kind: kind,
            theme: theme,
            layout: .standard,
            subtitle: subtitle,
            items: cardItems,
            safeAreaInsets: safeAreaInsets,
            isLoading: areaStore.isLoading,
            showsQuantity: false,
            emptyMessage: "Add your first area",
            showsInput: true,
            accessoryView: nil,
            onAdd: { title in
                _Concurrency.Task {
                    await areaStore.createArea(name: title, icon: "folder")
                }
            },
            onToggle: nil,
            onDelete: { item in
                guard let area = areaLookup[item.id] else { return }
                _Concurrency.Task {
                    await areaStore.deleteArea(area)
                }
            },
            onUpdate: { item, title, _, _ in
                guard var area = areaLookup[item.id] else { return }
                area.name = title
                _Concurrency.Task {
                    await areaStore.updateArea(area)
                }
            }
        )
    }
}

struct SettingsCardView: View {
    let kind: CardKind
    let theme: CardTheme
    @ObservedObject var themeStore: ThemeStore
    let safeAreaInsets: EdgeInsets

    @EnvironmentObject private var notificationSettingsStore: NotificationSettingsStore
    @EnvironmentObject private var shoppingListSettingsStore: ShoppingListSettingsStore

    private var surfacePalette: AppColorPalette {
        AppColors.palette(for: themeStore.preset)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    headerSection

                    // Theme Section
                    themeSection

                    // Notifications Section
                    notificationsSection

                    // Shopping List Section
                    shoppingListSection

                    // About Section
                    aboutSection
                }
                .padding(.horizontal, 24)
                .padding(.top, LayoutConstants.contentTopPadding)
                .padding(.bottom, LayoutConstants.contentBottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(theme.primaryTextColor)

            Text("App configuration")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.secondaryTextColor)
        }
    }

    private var themeSection: some View {
        SettingsSectionView(title: "Appearance", theme: theme) {
            ForEach(ThemePreset.allCases) { preset in
                SettingsToggleRow(
                    title: preset.displayName,
                    isOn: themeStore.preset == preset,
                    theme: theme,
                    onToggle: { themeStore.preset = preset }
                )
            }
        }
    }

    private var notificationsSection: some View {
        SettingsSectionView(title: "Notifications", theme: theme) {
            SettingsToggleRow(
                title: "Task Reminders",
                isOn: $notificationSettingsStore.taskRemindersEnabled,
                theme: theme
            )

            SettingsToggleRow(
                title: "Daily Digest",
                isOn: $notificationSettingsStore.dailyDigestEnabled,
                theme: theme
            )

            SettingsToggleRow(
                title: "Celebrations",
                isOn: $notificationSettingsStore.celebrationsEnabled,
                theme: theme
            )

            SettingsToggleRow(
                title: "Sound",
                isOn: $notificationSettingsStore.soundEnabled,
                theme: theme
            )
        }
    }

    private var shoppingListSection: some View {
        SettingsSectionView(title: "Shopping List", theme: theme) {
            HStack {
                Text("Suggestions")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.primaryTextColor)

                Spacer()

                Text("\(shoppingListSettingsStore.suggestionLimit)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryTextColor)

                Stepper(
                    "",
                    value: $shoppingListSettingsStore.suggestionLimit,
                    in: ShoppingListSettingsStore.suggestionLimitRange
                )
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(surfacePalette.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(surfacePalette.borderLight, lineWidth: 1)
                    )
            )
        }
    }

    private var aboutSection: some View {
        SettingsSectionView(title: "About", theme: theme) {
            HStack {
                Text("Version")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.primaryTextColor)

                Spacer()

                Text("1.0.0")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(surfacePalette.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(surfacePalette.borderLight, lineWidth: 1)
                    )
            )
        }
    }
}

struct SettingsSectionView<Content: View>: View {
    let title: String
    let theme: CardTheme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(theme.primaryTextColor)

            VStack(spacing: 8) {
                content
            }
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let theme: CardTheme
    var onToggle: (() -> Void)?
    @EnvironmentObject private var themeStore: ThemeStore

    init(title: String, isOn: Binding<Bool>, theme: CardTheme, onToggle: (() -> Void)? = nil) {
        self.title = title
        _isOn = isOn
        self.theme = theme
        self.onToggle = onToggle
    }

    init(title: String, isOn: Bool, theme: CardTheme, onToggle: @escaping () -> Void) {
        self.title = title
        _isOn = .constant(isOn)
        self.theme = theme
        self.onToggle = onToggle
    }

    var body: some View {
        let surfacePalette = AppColors.palette(for: themeStore.preset)
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.primaryTextColor)

            Spacer()

            if let onToggle {
                Button(action: {
                    Haptics.light()
                    onToggle()
                }) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            isOn ? theme.accentColor : theme.secondaryTextColor.opacity(0.4)
                        )
                }
            } else {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(theme.accentColor)
                    .onChange(of: isOn) { _, _ in
                        Haptics.light()
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(surfacePalette.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(surfacePalette.borderLight, lineWidth: 1)
                )
        )
    }
}

// MARK: - More Menu View (Redesign 2026-01-28)

struct MoreMenuView: View {
    @Binding var currentKind: CardKind
    let themeProvider: (CardKind) -> CardTheme
    let badgeProvider: (CardKind) -> Int
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("More Options") {
                    ForEach(CardKind.moreMenuItems, id: \.self) { kind in
                        let theme = themeProvider(kind)
                        let badge = badgeProvider(kind)

                        Button {
                            withAnimation(CardAnimations.cardSwitch) {
                                currentKind = kind
                            }
                            isPresented = false
                            EnhancedHaptics.cardChanged()
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: kind.iconName)
                                    .font(.title2)
                                    .foregroundStyle(theme.accentColor)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text(kind.subtitle(for: badge))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if badge > 0 {
                                    TabBadgeView(count: badge, color: theme.accentColor)
                                }

                                if currentKind == kind {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(theme.accentColor)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

extension String {
    var initials: String {
        let components = split(separator: " ").filter { !$0.isEmpty }
        if components.isEmpty {
            return ""
        }
        if components.count == 1 {
            return String(components[0].prefix(2)).uppercased()
        }
        let first = components[0].prefix(1)
        let second = components[1].prefix(1)
        return "\(first)\(second)".uppercased()
    }
}

#Preview {
    let householdStore = HouseholdStore()
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: CachedTask.self, configurations: config)
    } catch {
        fatalError("Failed to create preview container: \(error)")
    }

    return CardsPagerView(
        householdStore: householdStore,
        householdId: UUID(),
        modelContext: container.mainContext
    )
    .environmentObject(UserSession.shared)
    .environmentObject(ThemeStore())
    .environmentObject(ShoppingListSettingsStore())
    .modelContainer(container)
}
