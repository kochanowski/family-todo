import SwiftUI
import UIKit

struct CardsPagerView: View {
    @ObservedObject var householdStore: HouseholdStore
    @State private var cards: [CardData] = CardData.sampleCards
    @State private var currentIndex: Int = CardData.defaultIndex
    @State private var dragOffset: CGFloat = 0
    @State private var settingsPresented = false
    @State private var swipeHapticTriggered = false

    private let edgeWidth: CGFloat = 25
    private let maxVisibleEdges = 3
    private let swipeThreshold: CGFloat = 50

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let safeInsets = proxy.safeAreaInsets

            ZStack {
                ForEach(cards.indices, id: \.self) { index in
                    CardPageView(card: $cards[index], safeAreaInsets: safeInsets)
                        .frame(width: size.width, height: size.height)
                        .background(
                            LinearGradient(
                                colors: cards[index].kind.gradientColors,
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
                    cards: cards,
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
    }

    private func cardOffset(for index: Int, width: CGFloat) -> CGFloat {
        if index == currentIndex {
            return dragOffset
        }

        if index > currentIndex {
            let rightCount = cards.count - 1 - currentIndex
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

        return Double(index + cards.count)
    }

    private func cardDragGesture(width _: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let translation = value.translation.width
                let isAtStart = currentIndex == 0
                let isAtEnd = currentIndex == cards.count - 1

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
                if translation < -swipeThreshold, currentIndex < cards.count - 1 {
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
        let rightCount = min(maxVisibleEdges, cards.count - 1 - currentIndex)

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
        guard index != currentIndex, cards.indices.contains(index) else { return }
        Haptics.light()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            currentIndex = index
        }
    }
}

struct CardPageView: View {
    @Binding var card: CardData
    let safeAreaInsets: EdgeInsets

    @State private var inputText = ""
    @State private var inputScale: CGFloat = 1
    @State private var addButtonRotation: Angle = .zero
    @State private var editingItemID: UUID?
    @State private var editTitle = ""
    @State private var editQuantityValue = ""
    @State private var editQuantityUnit = ""
    @State private var editPresented = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                header
                itemsSection
                Spacer(minLength: 0)
                inputSection
            }
            .padding(.horizontal, 24)
            .padding(.top, LayoutConstants.headerHeight + safeAreaInsets.top + 12)
            .padding(.bottom, LayoutConstants.footerHeight + safeAreaInsets.bottom + 12)

            if card.kind == .backlog, card.items.isEmpty {
                ConfettiView(isActive: true)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $editPresented) {
            EditItemView(
                title: editTitle,
                quantityValue: editQuantityValue,
                quantityUnit: editQuantityUnit,
                showsQuantity: card.kind.supportsQuantity,
                onSave: { newTitle, newValue, newUnit in
                    updateItem(title: newTitle, quantityValue: newValue, quantityUnit: newUnit)
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.kind.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(card.kind.primaryTextColor)

            Text(card.kind.subtitle(for: remainingCount))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(card.kind.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private var itemsSection: some View {
        Group {
            if card.items.isEmpty, let emptyMessage = card.kind.emptyMessage {
                VStack(spacing: 12) {
                    Spacer(minLength: 20)
                    Text(emptyMessage)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(card.kind.secondaryTextColor)
                        .scaleEffect(1.02)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: emptyMessage)
                    Spacer(minLength: 20)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(card.items) { item in
                            CardItemRow(
                                item: item,
                                accentColor: card.kind.accentColor,
                                showsQuantity: card.kind.supportsQuantity,
                                onToggle: {
                                    toggleItem(item)
                                },
                                onDelete: {
                                    removeItem(item)
                                },
                                onEdit: {
                                    startEditing(item)
                                }
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .trailing)
                                        .combined(with: .opacity)
                                        .combined(with: .scale(scale: 0.8))
                                )
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var inputSection: some View {
        HStack(spacing: 12) {
            TextField(card.kind.placeholder, text: $inputText)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(Color.white.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            inputFocused ? card.kind.accentColor.opacity(0.8) : Color.white.opacity(0.3),
                            lineWidth: inputFocused ? 2 : 1
                        )
                )
                .scaleEffect(inputFocused ? 1.02 : inputScale)
                .shadow(
                    color: inputFocused ? card.kind.accentColor.opacity(0.3) : .clear,
                    radius: inputFocused ? 20 : 0,
                    x: 0,
                    y: 0
                )
                .focused($inputFocused)
                .onSubmit {
                    addItem()
                }
                .onChange(of: inputText) { _, _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        inputScale = 1.02
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.05)) {
                        inputScale = 1
                    }
                }

            AddItemButton(
                accentGradient: card.kind.buttonGradient,
                rotation: addButtonRotation,
                action: {
                    addItem()
                }
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 0.5),
            alignment: .top
        )
    }

    private var remainingCount: Int {
        card.items.filter { !$0.isCompleted }.count
    }

    private func addItem() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            let newItem = CardItem(title: trimmed)
            card.items.insert(newItem, at: 0)
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            addButtonRotation += .degrees(90)
        }

        Haptics.medium()
        inputText = ""
    }

    private func toggleItem(_ item: CardItem) {
        guard let index = card.items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            card.items[index].isCompleted.toggle()
        }
    }

    private func removeItem(_ item: CardItem) {
        guard let index = card.items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            card.items.remove(at: index)
        }
    }

    private func startEditing(_ item: CardItem) {
        editingItemID = item.id
        editTitle = item.title
        editQuantityValue = item.quantityValue ?? ""
        editQuantityUnit = item.quantityUnit ?? ""
        editPresented = true
    }

    private func updateItem(title: String, quantityValue: String, quantityUnit: String) {
        guard let editingItemID,
              let index = card.items.firstIndex(where: { $0.id == editingItemID })
        else {
            return
        }

        card.items[index].title = title
        if card.kind.supportsQuantity {
            card.items[index].quantityValue = quantityValue.isEmpty ? nil : quantityValue
            card.items[index].quantityUnit = quantityUnit.isEmpty ? nil : quantityUnit
        }
    }
}

struct CardItemRow: View {
    let item: CardItem
    let accentColor: Color
    let showsQuantity: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    @State private var pulse: CGFloat = 1

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    pulse = 1.2
                }
                onToggle()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.05)) {
                    pulse = 1
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(accentColor.opacity(item.isCompleted ? 0.3 : 0.6), lineWidth: 2)
                        .background(
                            Circle()
                                .fill(item.isCompleted ? accentColor : Color.clear)
                        )
                        .frame(width: 26, height: 26)

                    if item.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .scaleEffect(pulse)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .strikethrough(item.isCompleted, color: .primary.opacity(0.6))

                if showsQuantity, let quantityDisplay = item.quantityDisplay {
                    Text(quantityDisplay)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            .buttonStyle(PressableIconButtonStyle())

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(DeleteButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Color.white.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct GlassHeaderView: View {
    let onSettingsTap: () -> Void

    var body: some View {
        HStack {
            Text("Tasks")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                onSettingsTap()
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(PressableIconButtonStyle())
        }
        .padding(.horizontal, 20)
        .frame(height: LayoutConstants.headerHeight)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

struct GlassFooterView: View {
    let cards: [CardData]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(cards.indices, id: \.self) { index in
                let isActive = index == currentIndex
                Capsule(style: .continuous)
                    .fill(isActive ? cards[index].kind.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: isActive ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: currentIndex)
                    .onTapGesture {
                        onSelect(index)
                    }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

struct AddItemButton: View {
    let accentGradient: LinearGradient
    let rotation: Angle
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(accentGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .blendMode(.overlay)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    ShimmerView()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .blendMode(.screen)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                .rotationEffect(rotation)
        }
        .buttonStyle(AddButtonStyle())
    }
}

struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss

    @State var title: String
    @State var quantityValue: String
    @State var quantityUnit: String
    let showsQuantity: Bool
    let onSave: (String, String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Item name", text: $title)
                }

                if showsQuantity {
                    Section("Quantity") {
                        TextField("Value", text: $quantityValue)
                            .keyboardType(.decimalPad)
                        TextField("Unit", text: $quantityUnit)
                    }
                }
            }
            .navigationTitle("Edit Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, quantityValue, quantityUnit)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            LinearGradient(
                colors: [
                    Color.white.opacity(0),
                    Color.white.opacity(0.6),
                    Color.white.opacity(0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .rotationEffect(.degrees(20))
            .offset(x: phase * width * 2)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.6)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct ConfettiView: UIViewRepresentable {
    let isActive: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterCells = ConfettiView.makeConfettiCells()
        view.layer.addSublayer(emitter)
        context.coordinator.emitter = emitter
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let emitter = context.coordinator.emitter else { return }
        emitter.emitterPosition = CGPoint(x: uiView.bounds.midX, y: -10)
        emitter.emitterSize = CGSize(width: uiView.bounds.width, height: 1)
        #if CI
            emitter.birthRate = 0
        #else
            emitter.birthRate = isActive ? 1 : 0
        #endif
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var emitter: CAEmitterLayer?
    }

    private static func makeConfettiCells() -> [CAEmitterCell] {
        let colors: [UIColor] = [
            UIColor.systemPink,
            UIColor.systemBlue,
            UIColor.systemYellow,
            UIColor.systemGreen,
            UIColor.systemPurple,
            UIColor.systemOrange,
        ]

        return colors.map { color in
            let cell = CAEmitterCell()
            cell.birthRate = 3
            cell.lifetime = 6
            cell.velocity = 120
            cell.velocityRange = 40
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 5
            cell.spinRange = 2
            cell.scale = 0.025
            cell.scaleRange = 0.02
            cell.contents = ConfettiView.makeConfettiImage(color: color).cgImage
            return cell
        }
    }

    private static func makeConfettiImage(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
        return renderer.image { context in
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
    }
}

struct PressableIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
    }
}

struct AddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .brightness(configuration.isPressed ? 0.1 : 0)
    }
}

struct DeleteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .rotationEffect(configuration.isPressed ? .degrees(-90) : .degrees(0))
    }
}

enum Haptics {
    static func light() {
        #if !CI
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func medium() {
        #if !CI
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

struct CardData: Identifiable {
    let id = UUID()
    let kind: CardKind
    var items: [CardItem]

    static var sampleCards: [CardData] {
        [
            CardData(
                kind: .shoppingList,
                items: [
                    CardItem(title: "Milk"),
                    CardItem(title: "Bread"),
                    CardItem(title: "Sugar"),
                ]
            ),
            CardData(
                kind: .todo,
                items: [
                    CardItem(title: "Fix the faucet"),
                    CardItem(title: "Take down the Christmas tree"),
                ]
            ),
            CardData(kind: .backlog, items: []),
            CardData(
                kind: .recurring,
                items: [
                    CardItem(title: "Take out trash every Monday"),
                    CardItem(title: "Vacuum living room weekly"),
                ]
            ),
            CardData(
                kind: .household,
                items: [
                    CardItem(title: "Kitchen"),
                    CardItem(title: "Bathroom"),
                    CardItem(title: "Garden"),
                ]
            ),
        ]
    }

    static var defaultIndex: Int {
        sampleCards.firstIndex(where: { $0.kind == .todo }) ?? 0
    }
}

struct CardItem: Identifiable {
    let id = UUID()
    var title: String
    var quantityValue: String?
    var quantityUnit: String?
    var isCompleted = false

    init(title: String, quantityValue: String? = nil, quantityUnit: String? = nil) {
        self.title = title
        self.quantityValue = quantityValue
        self.quantityUnit = quantityUnit
    }

    var quantityDisplay: String? {
        guard let quantityValue, !quantityValue.isEmpty else { return nil }
        if let quantityUnit, !quantityUnit.isEmpty {
            return "\(quantityValue) \(quantityUnit)"
        }
        return quantityValue
    }
}

enum CardKind: String, CaseIterable {
    case shoppingList
    case todo
    case backlog
    case recurring
    case household

    var title: String {
        switch self {
        case .shoppingList:
            "Shopping List"
        case .todo:
            "Todo"
        case .backlog:
            "Backlog"
        case .recurring:
            "Recurring"
        case .household:
            "Household"
        }
    }

    var placeholder: String {
        switch self {
        case .shoppingList:
            "Add product..."
        case .todo:
            "Add task..."
        case .backlog:
            "Add idea..."
        case .recurring:
            "Add recurring chore..."
        case .household:
            "Add area..."
        }
    }

    var supportsQuantity: Bool {
        self == .shoppingList
    }

    var gradientColors: [Color] {
        switch self {
        case .shoppingList:
            [Color(hex: "E9D5FF"), Color(hex: "DDD6FE")]
        case .todo:
            [Color(hex: "DCFCE7"), Color(hex: "BBF7D0")]
        case .backlog:
            [Color(hex: "FEF9C3"), Color(hex: "FEF08A")]
        case .recurring:
            [Color(hex: "FFEDD5"), Color(hex: "FED7AA")]
        case .household:
            [Color(hex: "DBEAFE"), Color(hex: "BFDBFE")]
        }
    }

    var accentColor: Color {
        switch self {
        case .shoppingList:
            Color(hex: "C084FC")
        case .todo:
            Color(hex: "4ADE80")
        case .backlog:
            Color(hex: "FACC15")
        case .recurring:
            Color(hex: "FB923C")
        case .household:
            Color(hex: "60A5FA")
        }
    }

    var primaryTextColor: Color {
        switch self {
        case .shoppingList:
            Color(hex: "581C87")
        case .todo:
            Color(hex: "166534")
        case .backlog:
            Color(hex: "713F12")
        case .recurring:
            Color(hex: "9A3412")
        case .household:
            Color(hex: "1E3A8A")
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .shoppingList:
            Color(hex: "6B21A8")
        case .todo:
            Color(hex: "15803D")
        case .backlog:
            Color(hex: "A16207")
        case .recurring:
            Color(hex: "C2410C")
        case .household:
            Color(hex: "1D4ED8")
        }
    }

    var buttonGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor, accentColor.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var emptyMessage: String? {
        switch self {
        case .backlog:
            "Everything is done!"
        default:
            nil
        }
    }

    func subtitle(for count: Int) -> String {
        switch self {
        case .shoppingList:
            count == 1 ? "1 item to buy" : "\(count) items to buy"
        case .todo:
            count == 1 ? "1 task remaining" : "\(count) tasks remaining"
        case .backlog:
            count == 1 ? "1 idea in backlog" : "\(count) ideas in backlog"
        case .recurring:
            count == 1 ? "1 recurring chore" : "\(count) recurring chores"
        case .household:
            count == 1 ? "1 area" : "\(count) areas"
        }
    }
}

enum LayoutConstants {
    static let headerHeight: CGFloat = 60
    static let footerHeight: CGFloat = 60
    static let cardCornerRadius: CGFloat = 24
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (1, 1, 1)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

#Preview {
    let householdStore = HouseholdStore()
    return CardsPagerView(householdStore: householdStore)
        .environmentObject(UserSession.shared)
}
