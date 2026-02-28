import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Shopping List screen - quick capture and management of groceries
struct ShoppingListView: View {
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                ShoppingListContent(householdId: householdId, modelContext: modelContext)
            } else if let household = householdStore.currentHousehold {
                // Failsafe: Sync session if store has household
                ProgressView()
                    .onAppear {
                        userSession.setCurrentHousehold(household.id)
                    }
            } else {
                GuidedEmptyStateView()
                    .task {
                        // Recovery: Try to load from cache if session is lost
                        if userSession.currentHouseholdID == nil, let userId = userSession.userId {
                            print("DEBUG: Attempting household recovery for user: \(userId)")
                            await householdStore.loadCurrentHouseholdAndMembership(userId: userId)
                            if let household = householdStore.currentHousehold {
                                print("DEBUG: Recovered household: \(household.id)")
                                userSession.setCurrentHousehold(household.id)
                            }
                        }
                    }
            }
        }
    }
}

private struct ShoppingListContent: View {
    @StateObject private var store: ShoppingListStore
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
    @State private var isKeyboardVisible = false
    @State private var draggedItem: ShoppingItem?
    @State private var didPerformInitialLoad = false

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(
            wrappedValue: ShoppingListStore(householdId: householdId, modelContext: modelContext)
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

                    // Items list with rapid entry
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(store.toBuyItems) { item in
                                    Group {
                                        if itemBeingRemoved != item.id {
                                            if editingItemId == item.id {
                                                ShoppingItemInlineEditRow(
                                                    text: $editingItemText,
                                                    isBought: item.isBought,
                                                    onToggle: {
                                                        cancelEditingItem()
                                                        toggleItem(item)
                                                    },
                                                    onSubmit: { commitEditingItem(item) },
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
                                    .onDrag {
                                        draggedItem = item
                                        return NSItemProvider(
                                            object: item.id.uuidString as NSString
                                        )
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: ShoppingItemReorderDropDelegate(
                                            item: item,
                                            items: store.toBuyItems,
                                            draggedItem: $draggedItem,
                                            onMove: { from, to in
                                                store.moveToBuyItems(
                                                    from: from, to: to, persist: false
                                                )
                                            },
                                            onDrop: {
                                                _ = _Concurrency.Task {
                                                    await store.persistCurrentToBuyOrder()
                                                }
                                            }
                                        )
                                    )
                                }

                                // Rapid entry row (stable at bottom, no insert animation)
                                if isRapidEntryActive {
                                    rapidEntryRow
                                        .id("rapidEntry")
                                }
                            }
                            .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                            .padding(.bottom, listBottomInset)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .refreshable {
                            store.setSyncMode(userSession.syncMode)
                            await store.loadItems()
                        }
                        .onChange(of: rapidEntryFocused) { _, focused in
                            if focused {
                                withAnimation(WowAnimation.spring) {
                                    proxy.scrollTo("rapidEntry", anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: store.toBuyItems.count) { _, _ in
                            // Scroll to keep draft row visible after each insert
                            guard isRapidEntryActive else { return }
                            withAnimation(WowAnimation.spring) {
                                proxy.scrollTo("rapidEntry", anchor: .bottom)
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
            store.setSyncMode(userSession.syncMode)
            await store.loadItems()
        }
        .onChange(of: userSession.syncMode) { _, mode in
            store.setSyncMode(mode)
            _ = _Concurrency.Task {
                await store.loadItems()
            }
        }
        .newItemsBanner(manager: subscriptionManager)
        .onChange(of: isKeyboardVisible) { _, visible in
            guard !visible, let editingItem = currentEditingItem else { return }
            commitEditingItem(editingItem)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { _ in
            isKeyboardVisible = true
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text("Shopping")
                    .font(themeStore.font(for: .screenHeader))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                // Item count badge
                if !store.toBuyItems.isEmpty {
                    ShoppingCountBadge(count: store.toBuyItems.count)
                }
            }

            Spacer(minLength: 12)

            HStack(alignment: .center, spacing: 14) {
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

                // Recently purchased
                Button {
                    HapticManager.lightTap()
                    showRestock = true
                } label: {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shoppingRestockButton")
                .pulseAnimation(restockPulse.isPulsing)
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
        let foreground = themeStore.foregroundOnAccent(
            for: themeStore.accentTabColor, colorScheme: colorScheme
        )

        return Button {
            startRapidEntry()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Add item")
                    .font(
                        themeStore.preset == .retro
                            ? .system(size: 15, weight: .semibold)
                            : themeStore.font(for: .buttonLabel)
                    )
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
    }

    private var rapidEntryRow: some View {
        HStack(spacing: 10) {
            rapidEntryPlaceholderIcon

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
        }
        .padding(.vertical, 6)
        .background(cardBackground.opacity(0.01)) // Tap target
    }

    @ViewBuilder
    private var rapidEntryPlaceholderIcon: some View {
        if themeStore.preset == .retro {
            Rectangle()
                .stroke(Color(hex: "F7D51D"), lineWidth: 2.2)
                .frame(width: 20, height: 20)
                .overlay {
                    Rectangle()
                        .stroke(Color.black.opacity(0.75), lineWidth: 1)
                        .padding(0.8)
                }
                .frame(width: 44)
        } else {
            Circle()
                .stroke(themeStore.checkboxEmptyColor, lineWidth: 1.5)
                .frame(width: 20, height: 20)
                .frame(width: 44)
        }
    }

    // MARK: - Rapid Entry Logic

    private func startRapidEntry() {
        cancelEditingItem()
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
            await store.createItem(title: text)
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
        editingItemId = item.id
        editingItemText = item.title
    }

    private func cancelEditingItem() {
        editingItemId = nil
        editingItemText = ""
    }

    private func commitEditingItem(_ item: ShoppingItem) {
        guard editingItemId == item.id else { return }
        let trimmed = editingItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { cancelEditingItem() }

        guard !trimmed.isEmpty, trimmed != item.title else { return }

        var updatedItem = item
        updatedItem.title = trimmed
        _ = _Concurrency.Task {
            await store.updateItem(updatedItem)
        }
    }

    // MARK: - Data Actions

    private func toggleItem(_ item: ShoppingItem) {
        HapticManager.lightTap()
        let shouldCelebrateCompletion = store.toBuyItems.count == 1 && !item.isBought

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
                itemBeingRemoved = nil
                if shouldCelebrateCompletion, themeStore.celebrationsEnabled {
                    celebrationManager.celebrateShoppingComplete()
                    celebrationManager.triggerConfetti()
                }
            }
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

    private var cardBackground: Color {
        themeStore.surfaceColor
    }
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
        .contentShape(Rectangle())
        .padding(.vertical, ShoppingRowLayout.verticalPadding)
        .accessibilityIdentifier("shoppingItemRow_\(item.title)")
    }
}

private enum ShoppingRowLayout {
    static let spacing: CGFloat = 10
    static let verticalPadding: CGFloat = 6
    static let trailingSlotWidth: CGFloat = 24
}

private struct ShoppingItemInlineEditRow: View {
    @Binding var text: String
    let isBought: Bool
    let onToggle: () -> Void
    let onSubmit: () -> Void
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
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onChange(of: isFocused) { _, focused in
                    if !focused, !isCancelling {
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

    func updateUIView(_ uiView: UITextField, context _: Context) {
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

        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private var parent: RapidEntryTextField

        init(_ parent: RapidEntryTextField) {
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
            let button = UIButton(type: .system)
            button.setTitle("Done", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            button.setTitleColor(parent.actionForegroundColor, for: .normal)
            button.backgroundColor = parent.actionColor
            button.layer.cornerRadius = buttonHeight / 2
            button.contentEdgeInsets = UIEdgeInsets(
                top: 0,
                left: AppChromeMetrics.compactCTAHorizontalPadding,
                bottom: 0,
                right: AppChromeMetrics.compactCTAHorizontalPadding
            )
            button.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

            // Shadow matching the Add item pill
            button.layer.shadowColor = parent.actionColor.withAlphaComponent(0.3).cgColor
            button.layer.shadowRadius = 8
            button.layer.shadowOffset = CGSize(width: 0, height: 4)
            button.layer.shadowOpacity = 1.0

            button.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(button)

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
            .background(
                themeStore.canvasColor.ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Recently Purchased")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !store.recentItems.isEmpty {
                        Button(role: .destructive) {
                            showClearAllConfirmation = true
                        } label: {
                            Text("Clear All")
                                .font(themeStore.font(for: .buttonLabel))
                                .foregroundStyle(.red)
                        }
                        .tint(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .fontWeight(.bold)
                    .tint(themeStore.accentTabColor)
                }
            }
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

private struct ShoppingItemReorderDropDelegate: DropDelegate {
    let item: ShoppingItem
    let items: [ShoppingItem]
    @Binding var draggedItem: ShoppingItem?
    let onMove: (IndexSet, Int) -> Void
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        guard
            let draggedItem,
            draggedItem.id != item.id,
            let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
            let toIndex = items.firstIndex(where: { $0.id == item.id })
        else {
            return
        }

        onMove(
            IndexSet(integer: fromIndex),
            toIndex > fromIndex ? toIndex + 1 : toIndex
        )
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedItem = nil
        onDrop()
        HapticManager.lightTap()
        return true
    }
}

#Preview {
    ShoppingListView()
        .environmentObject(UserSession.shared)
        .environmentObject(ThemeStore())
}
