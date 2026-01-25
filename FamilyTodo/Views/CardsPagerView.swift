// swiftlint:disable file_length
import SwiftData
import SwiftUI

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
    private let cardKinds = CardKind.displayOrder
    @State private var currentIndex = CardKind.defaultIndex
    @State private var dragOffset: CGFloat = 0
    @State private var settingsPresented = false
    @State private var swipeHapticTriggered = false

    private let edgeWidth: CGFloat = 12
    private let edgeOverlap: CGFloat = 5
    private let maxVisibleEdges = 3
    private let swipeThreshold: CGFloat = 50

    init(householdStore: HouseholdStore, householdId: UUID, modelContext: ModelContext) {
        self.householdStore = householdStore
        self.householdId = householdId
        _taskStore = StateObject(wrappedValue: TaskStore(modelContext: modelContext))
        _shoppingListStore = StateObject(
            wrappedValue: ShoppingListStore(householdId: householdId, modelContext: modelContext))
        _recurringChoreStore = StateObject(
            wrappedValue: RecurringChoreStore(householdId: householdId, modelContext: modelContext))
        _areaStore = StateObject(
            wrappedValue: AreaStore(householdId: householdId, modelContext: modelContext))
        _memberStore = StateObject(
            wrappedValue: MemberStore(householdId: householdId, modelContext: modelContext))
    }

    private var edgeSpacing: CGFloat {
        edgeWidth - edgeOverlap
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let safeInsets = proxy.safeAreaInsets
            let palette = themeStore.palette

            ZStack {
                ForEach(cardKinds.indices, id: \.self) { index in
                    let kind = cardKinds[index]
                    let theme = palette.theme(for: kind)
                    cardView(for: kind, theme: theme, safeAreaInsets: safeInsets)
                        .frame(width: size.width, height: size.height)
                        .background(
                            LinearGradient(
                                colors: theme.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: LayoutConstants.cardCornerRadius,
                                style: .continuous
                            )
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: LayoutConstants.cardCornerRadius,
                                style: .continuous
                            )
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .offset(x: cardOffset(for: index, width: size.width))
                        .opacity(cardOpacity(for: index))
                        .zIndex(zIndex(for: index))
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color(.systemBackground))
            .gesture(cardDragGesture(width: size.width))
            .overlay(alignment: .top) {
                GlassHeaderView(onSettingsTap: {
                    settingsPresented = true
                })
                .padding(.top, safeInsets.top)
            }
            .overlay(alignment: .bottom) {
                GlassFooterView(
                    cardKinds: cardKinds,
                    currentIndex: currentIndex,
                    themeProvider: { palette.theme(for: $0) },
                    onSelect: { index in
                        Haptics.light()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            currentIndex = index
                        }
                    }
                )
                .padding(.bottom, safeInsets.bottom)
            }
            .overlay(edgeTapZones(size: size))
            .sheet(isPresented: $settingsPresented) {
                SettingsView(householdStore: householdStore)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
        }
        .ignoresSafeArea(.all, edges: .all)
        .task(id: householdId) {
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
        .onChange(of: userSession.syncMode) { _, newMode in
            taskStore.setSyncMode(newMode)
            shoppingListStore.setSyncMode(newMode)
            recurringChoreStore.setSyncMode(newMode)
            areaStore.setSyncMode(newMode)
            memberStore.setSyncMode(newMode)
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

    @ViewBuilder
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

    @ViewBuilder
    private func todoCard(kind: CardKind, theme: CardTheme, safeAreaInsets: EdgeInsets) -> some View
    {
        TodoCardView(
            kind: kind,
            theme: theme,
            taskStore: taskStore,
            memberStore: memberStore,
            currentMemberId: householdStore.currentMember?.id,
            safeAreaInsets: safeAreaInsets
        )
    }

    @ViewBuilder
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

    @ViewBuilder
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

    @ViewBuilder
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

    @ViewBuilder
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

    @ViewBuilder
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

        let baseOpacity = 0.78
        let progress = min(1, abs(dragOffset) / 120)

        if index == currentIndex + 1, dragOffset < 0 {
            return baseOpacity + (1 - baseOpacity) * Double(progress)
        }

        if index == currentIndex - 1, dragOffset > 0 {
            return baseOpacity + (1 - baseOpacity) * Double(progress)
        }

        return baseOpacity
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
                    Haptics.light()
                    swipeHapticTriggered = true
                }
            }
            .onEnded { value in
                swipeHapticTriggered = false

                let translation = value.translation.width
                if translation < -swipeThreshold, currentIndex < cardKinds.count - 1 {
                    currentIndex += 1
                    Haptics.medium()
                } else if translation > swipeThreshold, currentIndex > 0 {
                    currentIndex -= 1
                    Haptics.medium()
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                ForEach(0..<leftCount, id: \.self) { offset in
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
                ForEach(0..<rightCount, id: \.self) { offset in
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
        Haptics.light()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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

                        // Auto-drop after 0.5s
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.red.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Clear To Buy List")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PressableCardButtonStyle())
    }

    private var restockSection: some View {
        Button {
            Haptics.light()
            restockPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bag.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Restock List (\(restockItems.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(restockPreview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(Color.gray.opacity(0.2))
            )
            .overlay(
                Rectangle()
                    .fill(theme.accentColor.opacity(0.2))
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

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width * 0.9
            let maxHeight = proxy.size.height * 0.7

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
                                                    wordCloudWeight(for: item.id))
                                            )
                                            .foregroundStyle(theme.primaryTextColor)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                theme.accentColor.opacity(0.2), in: Capsule()
                                            )
                                            .shadow(
                                                color: Color.black.opacity(0.1), radius: 3, x: 0,
                                                y: 2)
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
                .background(Color(.systemBackground))
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
                radius: configuration.isPressed ? 6 : 3, x: 0, y: 2)
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
            emptyMessage: "All clear",
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
                        assigneeIds: assigneeIds)
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
        let initials = ids.compactMap { id in
            members.first { $0.id == id }?.displayName.initials
        }
        return initials
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
    let safeAreaInsets: EdgeInsets

    private var subtitle: String {
        householdStore.currentHousehold?.name ?? kind.subtitle(for: memberStore.members.count)
    }

    var body: some View {
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
                .padding(.top, LayoutConstants.headerHeight + safeAreaInsets.top + 16)

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
                                        member.role == .owner ? .yellow : theme.secondaryTextColor)

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
                                        .fill(.ultraThinMaterial)
                                        .overlay(Color.white.opacity(0.4))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
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
                .padding(.top, LayoutConstants.headerHeight + safeAreaInsets.top + 16)
                .padding(.bottom, LayoutConstants.footerHeight + safeAreaInsets.bottom + 16)
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

                Stepper(
                    "\(shoppingListSettingsStore.suggestionLimit)",
                    value: $shoppingListSettingsStore.suggestionLimit,
                    in: ShoppingListSettingsStore.suggestionLimitRange
                )
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Color.white.opacity(0.4))
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
                    .fill(.ultraThinMaterial)
                    .overlay(Color.white.opacity(0.4))
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
                            isOn ? theme.accentColor : theme.secondaryTextColor.opacity(0.4))
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
                .fill(.ultraThinMaterial)
                .overlay(Color.white.opacity(0.4))
        )
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
