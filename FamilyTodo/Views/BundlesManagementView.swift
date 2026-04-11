import SwiftUI

struct BundlesManagementView: View {
    @ObservedObject var store: ShoppingBundleStore
    let shoppingStore: ShoppingListStore?

    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var presentedEditor: PresentedBundleEditor?
    @State private var hasStartedInitialLoad = false
    @State private var lastAddedBundleId: UUID?

    var body: some View {
        Group {
            if !store.hasHydratedLocalSnapshot, store.bundles.isEmpty {
                ProgressView("Loading bundles...")
            } else if store.bundles.isEmpty {
                bundlesEmptyState
            } else {
                bundlesList
            }
        }
        .background(themeStore.canvasColor.ignoresSafeArea())
        .navigationTitle("Shopping Bundles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Shopping Bundles")
                    .font(themeStore.font(for: .inlineTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentedEditor = .create
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("shoppingBundlesAddButton")
            }
        }
        .task {
            guard !hasStartedInitialLoad else { return }
            hasStartedInitialLoad = true
            store.setSyncMode(userSession.syncMode)
            await store.loadBundlesForDisplay()
        }
        .onChange(of: userSession.syncMode) { _, mode in
            store.setSyncMode(mode)
            _ = _Concurrency.Task {
                await store.loadBundlesForDisplay()
            }
        }
        .sheet(item: $presentedEditor) { destination in
            ShoppingBundleEditorSheet(
                store: store,
                shoppingStore: shoppingStore,
                bundle: destination.bundle
            )
        }
    }

    private var bundlesList: some View {
        List {
            ForEach(store.bundles) { bundle in
                HStack(spacing: 0) {
                    Button {
                        presentedEditor = .edit(bundle)
                    } label: {
                        ShoppingBundleRow(bundle: bundle)
                    }
                    .buttonStyle(.plain)

                    if shoppingStore != nil {
                        let added = lastAddedBundleId == bundle.id
                        Button {
                            addBundleToShopping(bundle)
                        } label: {
                            Image(systemName: added ? "checkmark.circle.fill" : "cart.badge.plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(added ? .green : themeStore.accentTabColor)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                                .animation(.easeInOut(duration: 0.2), value: added)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(bundle.name) to shopping list")
                    }
                }
                .contentShape(Rectangle())
                .listRowInsets(
                    EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 8)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .contextMenu {
                    if shoppingStore != nil {
                        Button {
                            addBundleToShopping(bundle)
                        } label: {
                            Label("Add to Shopping List", systemImage: "cart.badge.plus")
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        _ = _Concurrency.Task {
                            await store.deleteBundle(bundle)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .environment(\.defaultMinListRowHeight, 10)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var bundlesEmptyState: some View {
        ThemedEmptyStateView(
            title: "No Bundles Yet",
            systemImage: ShoppingBundle.featureIcon,
            description: "Create reusable shopping sets for faster planning here"
        ) {
            Button {
                presentedEditor = .create
            } label: {
                Text("Create your first bundle")
                    .font(themeStore.font(for: .buttonLabel))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.bottom, 24)
    }

    private func addBundleToShopping(_ bundle: ShoppingBundle) {
        guard let shoppingStore else { return }
        lastAddedBundleId = bundle.id
        _ = _Concurrency.Task {
            _ = await shoppingStore.createItems(fromTitles: bundle.normalizedItems)
        }
        _ = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(nanoseconds: 1_500_000_000)
            if lastAddedBundleId == bundle.id {
                lastAddedBundleId = nil
            }
        }
    }
}

private enum PresentedBundleEditor: Identifiable {
    case create
    case edit(ShoppingBundle)

    var id: String {
        switch self {
        case .create:
            "create"
        case let .edit(bundle):
            "edit-\(bundle.id.uuidString)"
        }
    }

    var bundle: ShoppingBundle? {
        switch self {
        case .create:
            nil
        case let .edit(bundle):
            bundle
        }
    }
}

private struct ShoppingBundleRow: View {
    let bundle: ShoppingBundle

    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bundle.resolvedIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(themeStore.accentTabColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(bundle.name)
                    .font(themeStore.font(for: .inlineTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                    .lineLimit(1)

                Text(itemCountLabel(for: bundle.itemCount))
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bundle.name), \(itemCountLabel(for: bundle.itemCount))")
    }

    private func itemCountLabel(for count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}

private struct ShoppingBundleEditorSheet: View {
    @ObservedObject var store: ShoppingBundleStore
    let shoppingStore: ShoppingListStore?
    let bundle: ShoppingBundle?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var name: String
    @State private var selectedIcon: String
    @State private var itemDrafts: [BundleItemDraft]
    @State private var newItemText: String
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    @State private var showIconPicker = false
    @State private var hasAppliedInitialFocus = false
    @State private var composerFocused = false
    @FocusState private var focusedField: BundleEditorFocus?

    init(store: ShoppingBundleStore, shoppingStore: ShoppingListStore?, bundle: ShoppingBundle?) {
        self.store = store
        self.shoppingStore = shoppingStore
        self.bundle = bundle
        _name = State(initialValue: bundle?.name ?? "")
        _selectedIcon = State(initialValue: bundle?.resolvedIcon ?? ShoppingBundle.creationDefaultIcon)

        let initialItems = bundle?.normalizedItems ?? []
        _itemDrafts = State(initialValue: initialItems.map { BundleItemDraft(title: $0) })
        _newItemText = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BundleSectionCard {
                            ShoppingBundleHeaderRow(
                                name: $name,
                                selectedIcon: $selectedIcon,
                                focusedField: $focusedField,
                                onSubmitName: focusNextFieldAfterName,
                                onChooseIcon: { showIconPicker = true }
                            )
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Items")
                                .font(themeStore.font(for: .sectionHeader))
                                .foregroundStyle(themeStore.contentSecondaryColor)

                            BundleSectionCard {
                                ForEach($itemDrafts) { $draft in
                                    ShoppingBundleItemRow(
                                        title: $draft.title,
                                        focusedField: $focusedField,
                                        focusID: .existing(draft.id),
                                        onSubmit: {
                                            handleExistingItemSubmit(forDraftID: draft.id)
                                        },
                                        onRemove: {
                                            removeItemDraft(withID: draft.id)
                                        }
                                    )

                                    if draft.id != itemDrafts.last?.id {
                                        Divider()
                                            .padding(.leading, 16)
                                    }
                                }

                                if !itemDrafts.isEmpty {
                                    Divider()
                                        .padding(.leading, 16)
                                }

                                ShoppingBundleComposerRow(
                                    text: $newItemText,
                                    isFocused: $composerFocused,
                                    onSubmit: commitComposerItem
                                )
                                .id("bundleComposer")
                            }

                            if bundle == nil {
                                Button {
                                    _ = _Concurrency.Task {
                                        await saveBundle(andAddToShoppingList: true)
                                    }
                                } label: {
                                    Text(isSaving ? "Saving..." : "Save & Add to List")
                                        .font(themeStore.font(for: .buttonLabel))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!canSave || isSaving)
                                .padding(.top, 4)
                            }
                        }

                        if bundle != nil {
                            Button("Delete Bundle", role: .destructive) {
                                showDeleteConfirmation = true
                            }
                            .font(themeStore.font(for: .buttonLabel))
                        }
                    }
                    .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(themeStore.canvasColor.ignoresSafeArea())
                .onChange(of: itemDrafts.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo("bundleComposer", anchor: .bottom)
                    }
                }
            } // ScrollViewReader
            .navigationTitle(bundle == nil ? "New Bundle" : "Edit Bundle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(themeStore.font(for: .buttonLabel))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsTightening(true)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(bundle == nil ? "New Bundle" : "Edit Bundle")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        _ = _Concurrency.Task {
                            await saveBundle(andAddToShoppingList: false)
                        }
                    } label: {
                        Text(isSaving ? "Saving..." : "Save")
                            .font(themeStore.font(for: .buttonLabel))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsTightening(true)
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .confirmationDialog(
                "Delete this bundle?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Bundle", role: .destructive) {
                    _ = _Concurrency.Task {
                        await deleteBundle()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the bundle, but not any items already added to your shopping list.")
            }
        }
        .onAppear {
            applyInitialFocusIfNeeded()
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue == .composer {
                composerFocused = true
                focusedField = nil
            }
        }
        .sheet(isPresented: $showIconPicker) {
            ShoppingBundleIconPickerSheet(selectedIcon: $selectedIcon)
        }
        .presentationBackground(themeStore.canvasColor)
    }

    private var canSave: Bool {
        !ShoppingBundle.sanitizedName(name).isEmpty && !cleanedItems.isEmpty
    }

    private var cleanedItems: [String] {
        ShoppingBundle.sanitizedItems(itemDrafts.map(\.title) + [newItemText])
    }

    private func removeItemDraft(withID id: UUID) {
        guard let index = itemDrafts.firstIndex(where: { $0.id == id }) else { return }
        itemDrafts.remove(at: index)

        guard focusedField == .existing(id) else { return }

        let nextFocus: BundleEditorFocus =
            if index < itemDrafts.count {
                .existing(itemDrafts[index].id)
            } else {
                .composer
            }

        setFocus(nextFocus)
    }

    private func saveBundle(andAddToShoppingList: Bool) async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        if var bundle {
            bundle.name = name
            bundle.icon = selectedIcon
            bundle.items = cleanedItems
            await store.updateBundle(bundle)
        } else {
            await store.createBundle(
                name: name,
                icon: selectedIcon,
                items: cleanedItems
            )

            if andAddToShoppingList {
                _ = await shoppingStore?.createItems(fromTitles: cleanedItems)
            }
        }

        dismiss()
    }

    private func deleteBundle() async {
        guard let bundle else { return }
        await store.deleteBundle(bundle)
        dismiss()
    }

    private func handleExistingItemSubmit(forDraftID id: UUID) {
        guard let index = itemDrafts.firstIndex(where: { $0.id == id }) else { return }
        let nextIndex = itemDrafts.index(after: index)

        if nextIndex < itemDrafts.endIndex {
            focusedField = .existing(itemDrafts[nextIndex].id)
            return
        }

        focusedField = .composer
    }

    private func commitComposerItem() {
        let trimmedTitle = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            focusedField = .composer
            return
        }

        itemDrafts.append(BundleItemDraft(title: trimmedTitle))
        newItemText = ""
        focusedField = .composer
    }

    private func applyInitialFocusIfNeeded() {
        guard !hasAppliedInitialFocus else { return }
        hasAppliedInitialFocus = true
        setFocus(.name)
    }

    private func focusNextFieldAfterName() {
        focusedField = itemDrafts.first.map {
            BundleEditorFocus.existing($0.id)
        } ?? .composer
    }

    private func setFocus(_ nextFocus: BundleEditorFocus) {
        _ = _Concurrency.Task { @MainActor in
            focusedField = nextFocus
        }
    }
}

private struct ShoppingBundleHeaderRow: View {
    @Binding var name: String
    @Binding var selectedIcon: String
    let focusedField: FocusState<BundleEditorFocus?>.Binding
    let onSubmitName: () -> Void
    let onChooseIcon: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            TextField(
                "",
                text: $name,
                prompt: Text("Bundle Name")
                    .foregroundStyle(themeStore.contentSecondaryColor),
                axis: .vertical
            )
            .font(themeStore.font(for: .listRowTitle))
            .textFieldStyle(.plain)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused(focusedField, equals: .name)
            .onSubmit(onSubmitName)

            Button(action: onChooseIcon) {
                HStack(spacing: 8) {
                    Image(systemName: selectedIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(
                            themeStore.foregroundOnAccent(
                                for: themeStore.accentTabColor,
                                colorScheme: colorScheme
                            )
                        )
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(themeStore.accentTabColor)
                        }
                        .accessibilityHidden(true)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change Icon")
            .accessibilityValue(ShoppingBundle.iconLabel(for: selectedIcon))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ShoppingBundleIconPickerSheet: View {
    @Binding var selectedIcon: String

    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(displayedGroups) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title)
                                .font(themeStore.font(for: .sectionHeader))
                                .foregroundStyle(themeStore.contentSecondaryColor)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(group.icons, id: \.self) { icon in
                                    Button {
                                        selectedIcon = icon
                                        dismiss()
                                    } label: {
                                        Image(systemName: icon)
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(
                                                selectedIcon == icon
                                                    ? themeStore.foregroundOnAccent(
                                                        for: themeStore.accentTabColor,
                                                        colorScheme: colorScheme
                                                    )
                                                    : themeStore.contentPrimaryColor
                                            )
                                            .frame(maxWidth: .infinity, minHeight: 54)
                                            .background {
                                                RoundedRectangle(
                                                    cornerRadius: 14,
                                                    style: .continuous
                                                )
                                                .fill(
                                                    selectedIcon == icon
                                                        ? themeStore.accentTabColor
                                                        : themeStore.surfaceElevatedColor
                                                )
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(ShoppingBundle.iconLabel(for: icon))
                                    .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                .padding(.vertical, 20)
            }
            .scrollContentBackground(.hidden)
            .background(themeStore.canvasColor.ignoresSafeArea())
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(themeStore.font(for: .buttonLabel))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Choose Icon")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
            }
        }
        .presentationBackground(themeStore.canvasColor)
    }

    private var displayedGroups: [CuratedIconGroup] {
        let resolvedSelectedIcon = ShoppingBundle.resolvedIconName(selectedIcon)
        guard !ShoppingBundle.curatedIcons.contains(resolvedSelectedIcon) else {
            return ShoppingBundle.curatedIconGroups
        }

        return [
            CuratedIconGroup(title: "Current", icons: [resolvedSelectedIcon]),
        ] + ShoppingBundle.curatedIconGroups
    }
}

private enum BundleEditorFocus: Hashable {
    case name
    case existing(UUID)
    case composer
}

private struct BundleItemDraft: Identifiable {
    let id: UUID
    var title: String

    init(id: UUID = UUID(), title: String = "") {
        self.id = id
        self.title = title
    }
}

private struct StableComposerTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let themeStore: ThemeStore
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.delegate = context.coordinator
        field.returnKeyType = .done
        field.autocapitalizationType = .sentences
        field.autocorrectionType = .no
        field.enablesReturnKeyAutomatically = false
        applyStyle(to: field)
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        applyStyle(to: field)
        if isFocused, !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    private func applyStyle(to field: UITextField) {
        let font = themeStore.uiFont(for: .listRowTitle)
        field.font = font
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: StableComposerTextField

        init(_ parent: StableComposerTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ sender: UITextField) {
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
    }
}

private struct BundleSectionCard<Content: View>: View {
    @EnvironmentObject private var themeStore: ThemeStore
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(themeStore.surfaceColor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeStore.borderLightColor.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct ShoppingBundleItemRow: View {
    @Binding var title: String
    let focusedField: FocusState<BundleEditorFocus?>.Binding
    let focusID: BundleEditorFocus
    let onSubmit: () -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        HStack(spacing: 12) {
            TextField("Item", text: $title)
                .font(themeStore.font(for: .listRowTitle))
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused(focusedField, equals: focusID)
                .onSubmit(onSubmit)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove item")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ShoppingBundleComposerRow: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        HStack(spacing: 12) {
            StableComposerTextField(
                text: $text,
                isFocused: $isFocused,
                placeholder: "Add item",
                themeStore: themeStore,
                onSubmit: onSubmit
            )
            .frame(height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
