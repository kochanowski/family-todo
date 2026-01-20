import SwiftUI
import UIKit

struct CardLayout {
    let horizontalPadding: CGFloat
    let headerTopPadding: CGFloat
    let headerBottomPadding: CGFloat
    let headerTitleFont: Font
    let headerSubtitleFont: Font
    let sectionSpacing: CGFloat
    let rowSpacing: CGFloat
    let rowPadding: CGFloat
    let rowCornerRadius: CGFloat
    let checkboxSize: CGFloat
    let itemTitleFont: Font
    let itemDetailFont: Font
    let inputFieldPadding: CGFloat
    let inputFont: Font
    let inputCornerRadius: CGFloat
    let inputContainerPadding: CGFloat
    let addButtonSize: CGFloat
    let addButtonIconSize: CGFloat

    static let standard = CardLayout(
        horizontalPadding: 24,
        headerTopPadding: 16,
        headerBottomPadding: 12,
        headerTitleFont: .title2.weight(.bold),
        headerSubtitleFont: .subheadline.weight(.semibold),
        sectionSpacing: 16,
        rowSpacing: 8,
        rowPadding: 16,
        rowCornerRadius: 16,
        checkboxSize: 26,
        itemTitleFont: .body.weight(.semibold),
        itemDetailFont: .caption,
        inputFieldPadding: 12,
        inputFont: .body.weight(.semibold),
        inputCornerRadius: 12,
        inputContainerPadding: 16,
        addButtonSize: 48,
        addButtonIconSize: 22
    )

    static let compactShopping = CardLayout(
        horizontalPadding: 20,
        headerTopPadding: 12,
        headerBottomPadding: 8,
        headerTitleFont: .headline.weight(.bold),
        headerSubtitleFont: .caption.weight(.semibold),
        sectionSpacing: 12,
        rowSpacing: 6,
        rowPadding: 12,
        rowCornerRadius: 12,
        checkboxSize: 20,
        itemTitleFont: .callout.weight(.semibold),
        itemDetailFont: .caption2,
        inputFieldPadding: 10,
        inputFont: .callout.weight(.semibold),
        inputCornerRadius: 10,
        inputContainerPadding: 12,
        addButtonSize: 40,
        addButtonIconSize: 18
    )
}

struct CardPageView: View {
    let kind: CardKind
    let theme: CardTheme
    let layout: CardLayout
    let subtitle: String
    let items: [CardListItem]
    let safeAreaInsets: EdgeInsets
    let isLoading: Bool
    let showsQuantity: Bool
    let emptyMessage: String?
    let showsInput: Bool
    let accessoryView: AnyView?
    let onAdd: (String) -> Void
    let onToggle: ((CardListItem) -> Void)?
    let onDelete: ((CardListItem) -> Void)?
    let onUpdate: ((CardListItem, String, String?, String?) -> Void)?

    @State private var inputText = ""
    @State private var inputScale: CGFloat = 1
    @State private var addButtonRotation: Angle = .zero
    @State private var editingItem: CardListItem?
    @State private var editTitle = ""
    @State private var editQuantityValue = ""
    @State private var editQuantityUnit = ""
    @State private var editPresented = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: layout.sectionSpacing) {
                header
                itemsSection
                if let accessoryView {
                    accessoryView
                }
                Spacer(minLength: 0)
                if showsInput {
                    inputSection
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, LayoutConstants.headerHeight + safeAreaInsets.top + layout.headerTopPadding)
            .padding(.bottom, LayoutConstants.footerHeight + safeAreaInsets.bottom + layout.headerBottomPadding)

            if kind == .backlog, items.isEmpty {
                ConfettiView(isActive: true)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $editPresented) {
            EditItemView(
                title: editTitle,
                quantityValue: editQuantityValue,
                quantityUnit: editQuantityUnit,
                showsQuantity: showsQuantity,
                onSave: { newTitle, newValue, newUnit in
                    updateItem(title: newTitle, quantityValue: newValue, quantityUnit: newUnit)
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind.title)
                .font(layout.headerTitleFont)
                .foregroundStyle(theme.primaryTextColor)

            Text(subtitle)
                .font(layout.headerSubtitleFont)
                .foregroundStyle(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var itemsSection: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 20)
                    if isLoading {
                        ProgressView("Loading...")
                    } else if let emptyMessage {
                        Text(emptyMessage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(theme.secondaryTextColor)
                            .scaleEffect(1.02)
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: emptyMessage)
                    }
                    Spacer(minLength: 20)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: layout.rowSpacing) {
                        ForEach(items) { item in
                            CardItemRow(
                                item: item,
                                theme: theme,
                                layout: layout,
                                onToggle: toggleAction(for: item),
                                onDelete: deleteAction(for: item),
                                onEdit: editAction(for: item)
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom)
                                        .combined(with: .opacity)
                                        .combined(with: .scale(scale: 0.8)),
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
            TextField(kind.placeholder, text: $inputText)
                .font(layout.inputFont)
                .padding(layout.inputFieldPadding)
                .background(
                    RoundedRectangle(cornerRadius: layout.inputCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(Color.white.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: layout.inputCornerRadius, style: .continuous)
                        .stroke(
                            inputFocused ? theme.accentColor.opacity(0.8) : Color.white.opacity(0.3),
                            lineWidth: inputFocused ? 2 : 1
                        )
                )
                .scaleEffect(inputFocused ? 1.02 : inputScale)
                .shadow(
                    color: inputFocused ? theme.accentColor.opacity(0.3) : .clear,
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
                accentGradient: LinearGradient(
                    colors: [theme.accentColor, theme.accentColor.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                rotation: addButtonRotation,
                size: layout.addButtonSize,
                iconSize: layout.addButtonIconSize,
                action: {
                    addItem()
                }
            )
        }
        .padding(layout.inputContainerPadding)
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

    private func toggleAction(for item: CardListItem) -> (() -> Void)? {
        guard item.allowsToggle, let onToggle else { return nil }
        return {
            onToggle(item)
        }
    }

    private func deleteAction(for item: CardListItem) -> (() -> Void)? {
        guard item.allowsDelete, let onDelete else { return nil }
        return {
            Haptics.medium()
            onDelete(item)
        }
    }

    private func editAction(for item: CardListItem) -> (() -> Void)? {
        guard item.allowsEdit, onUpdate != nil else { return nil }
        return {
            startEditing(item)
        }
    }

    private func addItem() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        onAdd(trimmed)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            addButtonRotation += .degrees(90)
        }

        Haptics.medium()
        inputText = ""
    }

    private func startEditing(_ item: CardListItem) {
        guard onUpdate != nil else { return }
        editingItem = item
        editTitle = item.title
        editQuantityValue = item.quantityValue ?? ""
        editQuantityUnit = item.quantityUnit ?? ""
        editPresented = true
    }

    private func updateItem(title: String, quantityValue: String, quantityUnit: String) {
        guard let editingItem, let onUpdate else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let normalizedValue = quantityValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUnit = quantityUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        onUpdate(
            editingItem,
            trimmedTitle,
            normalizedValue.isEmpty ? nil : normalizedValue,
            normalizedUnit.isEmpty ? nil : normalizedUnit
        )
    }
}

struct CardItemRow: View {
    let item: CardListItem
    let theme: CardTheme
    let layout: CardLayout
    let onToggle: (() -> Void)?
    let onDelete: (() -> Void)?
    let onEdit: (() -> Void)?

    @State private var pulse: CGFloat = 1
    @State private var checkmarkRotation: Angle = .zero

    var body: some View {
        HStack(spacing: 12) {
            leadingView

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(layout.itemTitleFont)
                    .foregroundStyle(.primary)
                    .strikethrough(item.isCompleted, color: .primary.opacity(0.6))

                if let secondaryText = item.secondaryText {
                    HStack(spacing: 4) {
                        if let detailIconName = item.detailIconName {
                            Image(systemName: detailIconName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(secondaryText)
                            .font(layout.itemDetailFont)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            if let assigneeInitials = item.assigneeInitials, !assigneeInitials.isEmpty {
                AvatarStackView(initials: assigneeInitials, accentColor: theme.accentColor)
            }

            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.accentColor)
                }
                .buttonStyle(PressableIconButtonStyle())
            }

            if let onDelete {
                Button {
                    Haptics.medium()
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(DeleteButtonStyle())
            }
        }
        .padding(layout.rowPadding)
        .background(
            RoundedRectangle(cornerRadius: layout.rowCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Color.white.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: layout.rowCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .swipeActions(edge: .trailing) {
            if let onDelete {
                Button(role: .destructive) {
                    Haptics.medium()
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var leadingView: some View {
        if let onToggle {
            Button {
                triggerToggleAnimation()
                onToggle()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(theme.accentColor.opacity(item.isCompleted ? 0.3 : 0.6), lineWidth: 2)
                        .background(
                            Circle()
                                .fill(item.isCompleted ? theme.accentColor : Color.clear)
                        )
                        .frame(width: layout.checkboxSize, height: layout.checkboxSize)

                    if item.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: layout.checkboxSize * 0.45, weight: .bold))
                            .foregroundStyle(.white)
                            .rotationEffect(checkmarkRotation)
                    }
                }
            }
            .scaleEffect(pulse)
        }
    }

    private func triggerToggleAnimation() {
        Haptics.light()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            pulse = 1.2
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.05)) {
            pulse = 1
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            checkmarkRotation += .degrees(360)
        }
    }
}

struct AvatarStackView: View {
    let initials: [String]
    let accentColor: Color

    private var visibleInitials: [String] {
        Array(initials.prefix(3))
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(visibleInitials, id: \.self) { value in
                AvatarBadgeView(initials: value, accentColor: accentColor)
            }
            if initials.count > visibleInitials.count {
                AvatarBadgeView(initials: "+\(initials.count - visibleInitials.count)", accentColor: accentColor)
            }
        }
    }
}

struct AvatarBadgeView: View {
    let initials: String
    let accentColor: Color

    var body: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accentColor.opacity(0.2))
            )
    }
}

struct GlassHeaderView: View {
    let onSettingsTap: () -> Void

    var body: some View {
        HStack {
            Text("Tasks")
                .font(.headline.weight(.semibold))
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
    let cardKinds: [CardKind]
    let currentIndex: Int
    let themeProvider: (CardKind) -> CardTheme
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(cardKinds.indices, id: \.self) { index in
                let isActive = index == currentIndex
                Capsule(style: .continuous)
                    .fill(isActive ? themeProvider(cardKinds[index]).accentColor : Color.secondary.opacity(0.4))
                    .frame(width: isActive ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: currentIndex)
                    .onTapGesture {
                        Haptics.light()
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
    let size: CGFloat
    let iconSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
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

struct PressableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? 0.03 : 0)
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

    static func heavy() {
        #if !CI
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
    }
}

struct CardListItem: Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var secondaryText: String?
    var detailIconName: String?
    var quantityValue: String?
    var quantityUnit: String?
    var assigneeInitials: [String]?
    var allowsToggle: Bool
    var allowsEdit: Bool
    var allowsDelete: Bool

    init(
        id: UUID,
        title: String,
        isCompleted: Bool = false,
        secondaryText: String? = nil,
        detailIconName: String? = nil,
        quantityValue: String? = nil,
        quantityUnit: String? = nil,
        assigneeInitials: [String]? = nil,
        allowsToggle: Bool = true,
        allowsEdit: Bool = true,
        allowsDelete: Bool = true
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.secondaryText = secondaryText
        self.detailIconName = detailIconName
        self.quantityValue = quantityValue
        self.quantityUnit = quantityUnit
        self.assigneeInitials = assigneeInitials
        self.allowsToggle = allowsToggle
        self.allowsEdit = allowsEdit
        self.allowsDelete = allowsDelete
    }
}

enum CardKind: String, CaseIterable {
    case shoppingList
    case todo
    case backlog
    case recurring
    case household
    case areas
    case settings

    static let displayOrder: [CardKind] = [
        .shoppingList,
        .todo,
        .backlog,
        .recurring,
        .household,
        .areas,
        .settings,
    ]

    static var defaultIndex: Int {
        displayOrder.firstIndex(of: .todo) ?? 0
    }

    var title: String {
        switch self {
        case .shoppingList:
            "Shopping List"
        case .todo:
            "Todo"
        case .backlog:
            "Backlog"
        case .recurring:
            "Recurring Tasks"
        case .household:
            "Household"
        case .areas:
            "Areas"
        case .settings:
            "Settings"
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
            "Add recurring task..."
        case .household:
            "Add member..."
        case .areas:
            "Add area..."
        case .settings:
            ""
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
            count == 1 ? "1 recurring task" : "\(count) recurring tasks"
        case .household:
            count == 1 ? "1 member" : "\(count) members"
        case .areas:
            count == 1 ? "1 area" : "\(count) areas"
        case .settings:
            "Theme & preferences"
        }
    }
}

enum LayoutConstants {
    static let headerHeight: CGFloat = 60
    static let footerHeight: CGFloat = 60
    static let cardCornerRadius: CGFloat = 24
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                width = max(width, rowWidth)
                height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += size.width + (rowWidth == 0 ? 0 : spacing)
                rowHeight = max(rowHeight, size.height)
            }
        }

        width = max(width, rowWidth)
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let redComponent: UInt64
        let greenComponent: UInt64
        let blueComponent: UInt64
        switch cleaned.count {
        case 6:
            (redComponent, greenComponent, blueComponent) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (redComponent, greenComponent, blueComponent) = (1, 1, 1)
        }
        self.init(
            .sRGB,
            red: Double(redComponent) / 255,
            green: Double(greenComponent) / 255,
            blue: Double(blueComponent) / 255,
            opacity: 1
        )
    }
}
