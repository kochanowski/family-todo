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
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    @FocusState private var focusedDraftID: UUID?

    init(store: ShoppingBundleStore, bundle: ShoppingBundle?) {
        self.store = store
        self.bundle = bundle
        _name = State(initialValue: bundle?.name ?? "")
        _selectedIcon = State(initialValue: bundle?.resolvedIcon ?? ShoppingBundle.defaultIcon)

        let initialItems = bundle?.normalizedItems ?? []
        let drafts = initialItems.isEmpty
            ? [BundleItemDraft()]
            : initialItems.map { BundleItemDraft(title: $0) }
        _itemDrafts = State(initialValue: drafts)
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
                    ShoppingBundleIconPicker(selectedIcon: $selectedIcon)
                }

                Section("Items") {
                    ForEach($itemDrafts) { $draft in
                        HStack(spacing: 12) {
                            TextField(itemPlaceholder(forDraftID: draft.id), text: $draft.title)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .focused($focusedDraftID, equals: draft.id)
                                .onSubmit {
                                    handleItemSubmit(forDraftID: draft.id)
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

                    Button {
                        appendItemDraft(shouldFocus: true)
                    } label: {
                        Label("Add item", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(themeStore.accentTabColor)
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
        .presentationBackground(themeStore.canvasColor)
    }

    private var canSave: Bool {
        !ShoppingBundle.sanitizedName(name).isEmpty && !cleanedItems.isEmpty
    }

    private var cleanedItems: [String] {
        ShoppingBundle.sanitizedItems(itemDrafts.map(\.title))
    }

    private func removeItemDraft(withID id: UUID) {
        itemDrafts.removeAll { $0.id == id }

        if itemDrafts.isEmpty {
            appendItemDraft(shouldFocus: false)
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

    private func appendItemDraft(shouldFocus: Bool) {
        let draft = BundleItemDraft()
        itemDrafts.append(draft)

        guard shouldFocus else { return }
        focusedDraftID = draft.id
    }

    private func itemPlaceholder(forDraftID id: UUID) -> String {
        itemDrafts.first?.id == id ? "Milk" : "Item"
    }

    private func handleItemSubmit(forDraftID id: UUID) {
        guard let index = itemDrafts.firstIndex(where: { $0.id == id }) else { return }

        let trimmedTitle = itemDrafts[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextIndex = itemDrafts.index(after: index)

        if nextIndex < itemDrafts.endIndex {
            focusedDraftID = itemDrafts[nextIndex].id
            return
        }

        guard !trimmedTitle.isEmpty else {
            focusedDraftID = id
            return
        }

        appendItemDraft(shouldFocus: true)
    }
}

private struct ShoppingBundleIconPicker: View {
    @Binding var selectedIcon: String
    @State private var currentPage: Int

    @ScaledMetric(relativeTo: .body) private var iconTileMinHeight = 52

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private let gridSpacing: CGFloat = 12
    private let iconsPerPage = 12

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    init(selectedIcon: Binding<String>) {
        _selectedIcon = selectedIcon
        _currentPage = State(initialValue: Self.pageIndex(for: selectedIcon.wrappedValue))
    }

    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(Array(iconPages.enumerated()), id: \.offset) { pageIndex, icons in
                ShoppingBundleIconPage(
                    icons: icons,
                    columns: columns,
                    iconTileMinHeight: iconTileMinHeight,
                    selectedIcon: $selectedIcon
                )
                .tag(pageIndex)
            }
        }
        .frame(height: pickerHeight)
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        .onChange(of: selectedIcon) { _, icon in
            syncCurrentPage(with: icon)
        }
    }

    private var iconPages: [[String]] {
        ShoppingBundle.curatedIcons.chunked(into: iconsPerPage)
    }

    private var pickerHeight: CGFloat {
        (iconTileMinHeight * 4) + (gridSpacing * 3) + 34
    }

    private func syncCurrentPage(with icon: String) {
        let pageIndex = Self.pageIndex(for: icon)
        guard currentPage != pageIndex else { return }
        currentPage = pageIndex
    }

    private static func pageIndex(for icon: String) -> Int {
        let resolvedIcon = ShoppingBundle.resolvedIconName(icon)
        guard let iconIndex = ShoppingBundle.curatedIcons.firstIndex(of: resolvedIcon) else {
            return 0
        }
        return iconIndex / 12
    }
}

private struct ShoppingBundleIconPage: View {
    let icons: [String]
    let columns: [GridItem]
    let iconTileMinHeight: CGFloat
    @Binding var selectedIcon: String

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(
                                selectedIcon == icon
                                    ? themeStore.foregroundOnAccent(
                                        for: themeStore.accentTabColor,
                                        colorScheme: colorScheme
                                    )
                                    : themeStore.contentPrimaryColor
                            )
                            .frame(maxWidth: .infinity, minHeight: iconTileMinHeight)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }
}

private extension Array {
    func chunked(into chunkSize: Int) -> [[Element]] {
        guard chunkSize > 0, !isEmpty else {
            return isEmpty ? [] : [self]
        }

        return stride(from: 0, to: count, by: chunkSize).map { startIndex in
            Array(self[startIndex ..< Swift.min(startIndex + chunkSize, count)])
        }
    }
}

private struct BundleItemDraft: Identifiable {
    let id: UUID
    var title: String

    init(id: UUID = UUID(), title: String = "") {
        self.id = id
        self.title = title
    }
}
