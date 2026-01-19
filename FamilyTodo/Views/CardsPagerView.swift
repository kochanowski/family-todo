import SwiftData
import SwiftUI

struct CardsPagerView: View {
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

    private let edgeWidth: CGFloat = 25
    private let maxVisibleEdges = 3
    private let swipeThreshold: CGFloat = 50

    init(householdStore: HouseholdStore, householdId: UUID, modelContext: ModelContext) {
        self.householdStore = householdStore
        self.householdId = householdId
        _taskStore = StateObject(wrappedValue: TaskStore(modelContext: modelContext))
        _shoppingListStore = StateObject(wrappedValue: ShoppingListStore(householdId: householdId))
        _recurringChoreStore = StateObject(wrappedValue: RecurringChoreStore(householdId: householdId))
        _areaStore = StateObject(wrappedValue: AreaStore(householdId: householdId))
        _memberStore = StateObject(wrappedValue: MemberStore(householdId: householdId))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let safeInsets = proxy.safeAreaInsets

            ZStack {
                ForEach(cardKinds.indices, id: \.self) { index in
                    let kind = cardKinds[index]
                    cardView(for: kind, safeAreaInsets: safeInsets)
                        .frame(width: size.width, height: size.height)
                        .background(
                            LinearGradient(
                                colors: kind.gradientColors,
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
        .ignoresSafeArea()
        .task(id: householdId) {
            taskStore.setHousehold(householdId)
            await taskStore.loadTasks()
            await shoppingListStore.loadItems()
            await recurringChoreStore.loadChores()
            await areaStore.loadAreas()
            await memberStore.loadMembers()
        }
    }

    @ViewBuilder
    private func cardView(for kind: CardKind, safeAreaInsets: EdgeInsets) -> some View {
        switch kind {
        case .shoppingList:
            ShoppingListCardView(
                kind: kind,
                store: shoppingListStore,
                safeAreaInsets: safeAreaInsets
            )
        case .todo:
            TodoCardView(
                kind: kind,
                taskStore: taskStore,
                areaStore: areaStore,
                currentMemberId: householdStore.currentMember?.id,
                safeAreaInsets: safeAreaInsets
            )
        case .backlog:
            BacklogCardView(
                kind: kind,
                taskStore: taskStore,
                areaStore: areaStore,
                currentMemberId: householdStore.currentMember?.id,
                safeAreaInsets: safeAreaInsets
            )
        case .recurring:
            RecurringCardView(
                kind: kind,
                choreStore: recurringChoreStore,
                taskStore: taskStore,
                currentMemberId: householdStore.currentMember?.id,
                safeAreaInsets: safeAreaInsets
            )
        case .household:
            HouseholdCardView(
                kind: kind,
                areaStore: areaStore,
                memberStore: memberStore,
                safeAreaInsets: safeAreaInsets
            )
        }
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

            let position = visibleCount - relative + 1
            let baseOffset = width - edgeWidth * CGFloat(position)
            let dragAdjustment = dragOffset < 0 ? dragOffset * 0.3 : 0
            return baseOffset + dragAdjustment
        }

        let leftCount = currentIndex
        let visibleCount = min(maxVisibleEdges, leftCount)
        let relative = currentIndex - index

        guard relative <= visibleCount else {
            return -(width + edgeWidth)
        }

        let position = visibleCount - relative + 1
        let baseOffset = -(width - edgeWidth * CGFloat(position))
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
            HStack(spacing: 0) {
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

            HStack(spacing: 0) {
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
        Haptics.light()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            currentIndex = index
        }
    }
}

struct ShoppingListCardView: View {
    let kind: CardKind
    @ObservedObject var store: ShoppingListStore
    let safeAreaInsets: EdgeInsets

    private var itemLookup: [UUID: ShoppingItem] {
        Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0) })
    }

    private var cardItems: [CardListItem] {
        let ordered = store.toBuyItems + store.boughtItems
        return ordered.map { item in
            CardListItem(
                id: item.id,
                title: item.title,
                isCompleted: item.isBought,
                secondaryText: item.quantityDisplay,
                quantityValue: item.quantityValue,
                quantityUnit: item.quantityUnit
            )
        }
    }

    private var subtitle: String {
        kind.subtitle(for: store.toBuyItems.count)
    }

    var body: some View {
        CardPageView(
            kind: kind,
            subtitle: subtitle,
            items: cardItems,
            safeAreaInsets: safeAreaInsets,
            isLoading: store.isLoading,
            showsQuantity: true,
            emptyMessage: "Add your first item",
            onAdd: { title in
                _Concurrency.Task {
                    await store.createItem(title: title)
                }
            },
            onToggle: { item in
                guard let shoppingItem = itemLookup[item.id] else { return }
                _Concurrency.Task {
                    await store.toggleBought(shoppingItem)
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
    }
}

struct TodoCardView: View {
    let kind: CardKind
    @ObservedObject var taskStore: TaskStore
    @ObservedObject var areaStore: AreaStore
    let currentMemberId: UUID?
    let safeAreaInsets: EdgeInsets

    @State private var wipAlertPresented = false

    private var taskLookup: [UUID: Task] {
        Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    }

    private var tasks: [Task] {
        guard let currentMemberId else {
            return taskStore.nextTasks
        }
        return taskStore.nextTasks.filter { $0.assigneeId == currentMemberId }
    }

    private var areaLookup: [UUID: String] {
        Dictionary(uniqueKeysWithValues: areaStore.areas.map { ($0.id, $0.name) })
    }

    private var cardItems: [CardListItem] {
        tasks.map { task in
            CardListItem(
                id: task.id,
                title: task.title,
                secondaryText: areaLookup[task.areaId]
            )
        }
    }

    private var subtitle: String {
        kind.subtitle(for: tasks.count)
    }

    var body: some View {
        CardPageView(
            kind: kind,
            subtitle: subtitle,
            items: cardItems,
            safeAreaInsets: safeAreaInsets,
            isLoading: taskStore.isLoading,
            showsQuantity: false,
            emptyMessage: "All clear",
            onAdd: { title in
                guard canAddToNext() else {
                    wipAlertPresented = true
                    return
                }
                _Concurrency.Task {
                    await taskStore.createTask(title: title, status: .next, assigneeId: currentMemberId)
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
}

struct BacklogCardView: View {
    let kind: CardKind
    @ObservedObject var taskStore: TaskStore
    @ObservedObject var areaStore: AreaStore
    let currentMemberId: UUID?
    let safeAreaInsets: EdgeInsets

    @State private var wipAlertPresented = false

    private var taskLookup: [UUID: Task] {
        Dictionary(uniqueKeysWithValues: taskStore.backlogTasks.map { ($0.id, $0) })
    }

    private var areaLookup: [UUID: String] {
        Dictionary(uniqueKeysWithValues: areaStore.areas.map { ($0.id, $0.name) })
    }

    private var cardItems: [CardListItem] {
        taskStore.backlogTasks.map { task in
            CardListItem(
                id: task.id,
                title: task.title,
                secondaryText: areaLookup[task.areaId]
            )
        }
    }

    private var subtitle: String {
        kind.subtitle(for: taskStore.backlogTasks.count)
    }

    var body: some View {
        CardPageView(
            kind: kind,
            subtitle: subtitle,
            items: cardItems,
            safeAreaInsets: safeAreaInsets,
            isLoading: taskStore.isLoading,
            showsQuantity: false,
            emptyMessage: kind.emptyMessage,
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
        if updatedTask.assigneeId == nil {
            updatedTask.assigneeId = currentMemberId
        }

        _Concurrency.Task {
            await taskStore.updateTask(updatedTask)
        }
    }
}

struct RecurringCardView: View {
    let kind: CardKind
    @ObservedObject var choreStore: RecurringChoreStore
    @ObservedObject var taskStore: TaskStore
    let currentMemberId: UUID?
    let safeAreaInsets: EdgeInsets

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

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
                secondaryText: secondaryText(for: chore),
                iconName: chore.isActive ? nil : "pause.circle.fill",
                iconColor: chore.isActive ? nil : .secondary,
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
            subtitle: subtitle,
            items: cardItems,
            safeAreaInsets: safeAreaInsets,
            isLoading: choreStore.isLoading,
            showsQuantity: false,
            emptyMessage: "Add a recurring chore",
            onAdd: { title in
                let weekday = Calendar.current.component(.weekday, from: Date())
                _Concurrency.Task {
                    await choreStore.createChore(
                        title: title,
                        recurrenceType: .weekly,
                        recurrenceDay: weekday,
                        defaultAssigneeId: currentMemberId
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

    private func secondaryText(for chore: RecurringChore) -> String? {
        guard chore.isActive else { return "Paused" }
        guard let nextDate = chore.nextScheduledDate else { return "Next scheduled" }
        let formatted = Self.dateFormatter.string(from: nextDate)
        return "Next: \(formatted)"
    }
}

struct HouseholdCardView: View {
    let kind: CardKind
    @ObservedObject var areaStore: AreaStore
    @ObservedObject var memberStore: MemberStore
    let safeAreaInsets: EdgeInsets

    private var areaLookup: [UUID: Area] {
        Dictionary(uniqueKeysWithValues: areaStore.areas.map { ($0.id, $0) })
    }

    private var activeMembers: [Member] {
        memberStore.members.filter(\.isActive)
    }

    private var cardItems: [CardListItem] {
        let areaItems = areaStore.areas.map { area in
            CardListItem(
                id: area.id,
                title: area.name,
                secondaryText: "Area",
                iconName: area.icon ?? "folder",
                iconColor: kind.accentColor,
                allowsToggle: false
            )
        }

        let memberItems = activeMembers.map { member in
            CardListItem(
                id: member.id,
                title: member.displayName,
                secondaryText: member.role == .owner ? "Owner" : "Member",
                iconName: "person.fill",
                iconColor: kind.accentColor,
                allowsToggle: false,
                allowsEdit: false,
                allowsDelete: false
            )
        }

        return areaItems + memberItems
    }

    private var subtitle: String {
        let areaLabel = countLabel(areaStore.areas.count, singular: "area", plural: "areas")
        let memberLabel = countLabel(activeMembers.count, singular: "member", plural: "members")
        return "\(areaLabel) · \(memberLabel)"
    }

    var body: some View {
        CardPageView(
            kind: kind,
            subtitle: subtitle,
            items: cardItems,
            safeAreaInsets: safeAreaInsets,
            isLoading: areaStore.isLoading || memberStore.isLoading,
            showsQuantity: false,
            emptyMessage: "Add your first area",
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

    private func countLabel(_ count: Int, singular: String, plural: String) -> String {
        if count == 1 {
            return "1 \(singular)"
        }
        return "\(count) \(plural)"
    }
}

#Preview {
    let householdStore = HouseholdStore()
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: CachedTask.self, configurations: config)

    return CardsPagerView(
        householdStore: householdStore,
        householdId: UUID(),
        modelContext: container.mainContext
    )
    .environmentObject(UserSession.shared)
    .modelContainer(container)
}
