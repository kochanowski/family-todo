import SwiftUI

struct BundlesManagementView: View {
    @ObservedObject var store: ShoppingBundleStore

    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var presentedEditor: PresentedBundleEditor?

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
            if store.bundles.isEmpty {
                ContentUnavailableView(
                    "No Bundles Yet",
                    systemImage: ShoppingBundle.defaultIcon,
                    description: Text(
                        "Create reusable shopping bundles for quick add from the main Shopping button."
                    )
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
            store.setSyncMode(userSession.syncMode)
            await store.loadBundles()
        }
        .refreshable {
            store.setSyncMode(userSession.syncMode)
            await store.loadBundles()
        }
        .onChange(of: userSession.syncMode) { _, mode in
            store.setSyncMode(mode)
            _ = _Concurrency.Task {
                await store.loadBundles()
            }
        }
        .sheet(item: $presentedEditor) { destination in
            ShoppingBundleEditorSheet(
                store: store,
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
    @FocusState private var focusedField: BundleEditorFocus?

    init(store: ShoppingBundleStore, bundle: ShoppingBundle?) {
        self.store = store
        self.bundle = bundle
        _name = State(initialValue: bundle?.name ?? "")
        _selectedIcon = State(initialValue: bundle?.resolvedIcon ?? ShoppingBundle.defaultIcon)

        let initialItems = bundle?.normalizedItems ?? []
        _itemDrafts = State(initialValue: initialItems.map { BundleItemDraft(title: $0) })
        _newItemText = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Bundle Name") {
                    TextField("Weekly breakfast", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section("Icon") {
                    ShoppingBundleIconSelector(selectedIcon: $selectedIcon) {
                        showIconPicker = true
                    }
                }

                Section("Items") {
                    ForEach($itemDrafts) { $draft in
                        HStack(spacing: 12) {
                            TextField("Item", text: $draft.title)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .focused($focusedField, equals: .existing(draft.id))
                                .onSubmit {
                                    handleExistingItemSubmit(forDraftID: draft.id)
                                }

                            Button(role: .destructive) {
                                removeItemDraft(withID: draft.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove item")
                        }
                    }

                    HStack(spacing: 12) {
                        TextField(composerPlaceholder, text: $newItemText)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.return)
                            .focused($focusedField, equals: .composer)
                            .onSubmit {
                                commitComposerItem()
                            }

                        Color.clear
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                    }
                }

                if bundle != nil {
                    Section {
                        Button("Delete Bundle", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .environment(\.defaultMinListRowHeight, 44)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(themeStore.canvasColor.ignoresSafeArea())
            .navigationTitle(bundle == nil ? "New Bundle" : "Edit Bundle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        _ = _Concurrency.Task {
                            await saveBundle()
                        }
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
        itemDrafts.removeAll { $0.id == id }

        if focusedField == .existing(id) {
            DispatchQueue.main.async {
                focusedField = .composer
            }
        }
    }

    private func saveBundle() async {
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
        }

        dismiss()
    }

    private func deleteBundle() async {
        guard let bundle else { return }
        await store.deleteBundle(bundle)
        dismiss()
    }

    private var composerPlaceholder: String {
        itemDrafts.isEmpty ? "Milk" : "Add another item"
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

        DispatchQueue.main.async {
            focusedField = .composer
        }
    }
}

private struct ShoppingBundleIconSelector: View {
    @Binding var selectedIcon: String
    let onChooseIcon: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: selectedIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        themeStore.foregroundOnAccent(
                            for: themeStore.accentTabColor,
                            colorScheme: colorScheme
                        )
                    )
                    .frame(width: 68, height: 68)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(themeStore.accentTabColor)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ShoppingBundle.iconLabel(for: selectedIcon))
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)

                    Text("Shown on the bundle and quick-add menu.")
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }

                Spacer()
            }

            Button("Choose Icon", action: onChooseIcon)
                .font(themeStore.font(for: .buttonLabel))
                .buttonStyle(.bordered)
                .tint(themeStore.accentTabColor)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
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
                    Button("Close") {
                        dismiss()
                    }
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
