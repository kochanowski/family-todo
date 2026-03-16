import SwiftUI

struct BundlesManagementView: View {
    @ObservedObject var store: ShoppingBundleStore
    let shoppingStore: ShoppingListStore?

    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var presentedEditor: PresentedBundleEditor?
    @State private var hasStartedInitialLoad = false

    var body: some View {
        List {
            ForEach(store.bundles) { bundle in
                Button {
                    presentedEditor = .edit(bundle)
                } label: {
                    ShoppingBundleRow(bundle: bundle)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
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
        .overlay {
            if !store.hasHydratedLocalSnapshot, store.bundles.isEmpty {
                ProgressView("Loading bundles...")
            } else if store.bundles.isEmpty {
                ThemedEmptyStateView(
                    title: "No Bundles Yet",
                    systemImage: ShoppingBundle.defaultIcon,
                    description: "Create reusable shopping bundles for quick add from the main Shopping button."
                )
                .offset(y: -24)
            }
        }
        .environment(\.defaultMinListRowHeight, 10)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
        .refreshable {
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
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
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
    @FocusState private var focusedField: BundleEditorFocus?

    init(store: ShoppingBundleStore, shoppingStore: ShoppingListStore?, bundle: ShoppingBundle?) {
        self.store = store
        self.shoppingStore = shoppingStore
        self.bundle = bundle
        _name = State(initialValue: bundle?.name ?? "")
        _selectedIcon = State(initialValue: bundle?.resolvedIcon ?? ShoppingBundle.defaultIcon)

        let initialItems = bundle?.normalizedItems ?? []
        _itemDrafts = State(initialValue: initialItems.map { BundleItemDraft(title: $0) })
        _newItemText = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
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
                                focusedField: $focusedField,
                                onSubmit: commitComposerItem
                            )
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

        setFocus(.composer)
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
    let focusedField: FocusState<BundleEditorFocus?>.Binding
    let onSubmit: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        HStack(spacing: 12) {
            TextField(
                "",
                text: $text,
                prompt: Text("Add item")
                    .font(themeStore.font(for: .listRowTitle))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            )
            .font(themeStore.font(for: .listRowTitle))
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused(focusedField, equals: .composer)
            .onSubmit(onSubmit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
