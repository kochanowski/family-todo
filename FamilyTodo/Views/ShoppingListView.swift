import SwiftData
import SwiftUI

/// Shopping List screen - quick capture and management of groceries
struct ShoppingListView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                ShoppingListContent(householdId: householdId, modelContext: modelContext)
            } else {
                ContentUnavailableView(
                    "No Household Selected",
                    systemImage: "house.slash",
                    description: Text("Please select or create a household in the More tab.")
                )
            }
        }
    }
}

private struct ShoppingListContent: View {
    @StateObject private var store: ShoppingListStore
    @StateObject private var restockPulse = RestockPulseState()
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager

    // Rapid entry state
    @State private var isRapidEntryActive = false
    @State private var rapidEntryText = ""
    @FocusState private var rapidEntryFocused: Bool

    @State private var showRestock = false
    @State private var itemBeingRemoved: UUID?

    @Environment(\.colorScheme) private var colorScheme

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(wrappedValue: ShoppingListStore(householdId: householdId, modelContext: modelContext))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Items list with rapid entry
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.toBuyItems) { item in
                            if itemBeingRemoved != item.id {
                                ShoppingItemRow(
                                    item: item,
                                    onToggle: { toggleItem(item) }
                                )
                                .rowInsertAnimation()
                            }
                        }

                        // Rapid entry row (always at bottom)
                        if isRapidEntryActive {
                            rapidEntryRow
                                .id("rapidEntry")
                                .rowInsertAnimation()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120) // Space for tab bar + add button
                }
                .refreshable {
                    await store.loadItems()
                }
                .onChange(of: rapidEntryFocused) { _, focused in
                    if focused {
                        withAnimation(WowAnimation.spring) {
                            proxy.scrollTo("rapidEntry", anchor: .bottom)
                        }
                    }
                }
            }

            Spacer()

            // Add item button (compact, bottom)
            if !isRapidEntryActive {
                addItemButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap outside: commit or dismiss rapid entry
            if isRapidEntryActive {
                commitOrDismissRapidEntry()
            }
        }
        .task {
            await store.loadItems()
        }
        .newItemsBanner(manager: subscriptionManager)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Shopping")
                .font(.system(size: 28, weight: .bold))

            // Item count badge
            if !store.toBuyItems.isEmpty {
                Text("\(store.toBuyItems.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.blue))
            }

            Spacer()

            // Clear all button
            if !store.toBuyItems.isEmpty {
                Button {
                    clearAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }

            // Restock button with pulse animation
            Button {
                HapticManager.lightTap()
                showRestock = true
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .pulseAnimation(restockPulse.isPulsing)
            .sheet(isPresented: $showRestock) {
                RestockSheet(restockItems: store.boughtItems, onRestock: restockItem)
            }
        }
    }

    // MARK: - Add Item Button

    private var addItemButton: some View {
        Button {
            startRapidEntry()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)

                Text("Add item")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackground)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rapid Entry Row

    private var rapidEntryRow: some View {
        HStack(spacing: 12) {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                .frame(width: 24, height: 24)

            TextField("Add item", text: $rapidEntryText)
                .font(.system(size: 15))
                .focused($rapidEntryFocused)
                .submitLabel(.done)
                .onSubmit {
                    handleRapidEntrySubmit()
                }
        }
        .padding(.vertical, 12)
        .background(cardBackground.opacity(0.01)) // Tap target
    }

    // MARK: - Rapid Entry Logic

    private func startRapidEntry() {
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

    // MARK: - Data Actions

    private func toggleItem(_ item: ShoppingItem) {
        HapticManager.lightTap()

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
            }
        }
    }

    private func restockItem(_ item: ShoppingItem) {
        _Concurrency.Task {
            await store.toggleBought(item)
        }
        HapticManager.lightTap()
    }

    private func clearAll() {
        _Concurrency.Task {
            await store.markAllAsBought()
        }
        HapticManager.success()
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : Color(hex: "F9F9F9")
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "1C1C1E") : .white
    }
}

// MARK: - Shopping Item Row

struct ShoppingItemRow: View {
    let item: ShoppingItem
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Circular checkbox
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .overlay {
                        if item.isBought {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 16, height: 16)
                        }
                    }

                Text(item.title)
                    .font(.system(size: 15))
                    .foregroundStyle(item.isBought ? .secondary : .primary)
                    .strikethrough(item.isBought)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 10) // Compact height
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Restock Sheet

struct RestockSheet: View {
    let restockItems: [ShoppingItem]
    let onRestock: (ShoppingItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                if restockItems.isEmpty {
                    ContentUnavailableView(
                        "No Recent Purchases",
                        systemImage: "cart",
                        description: Text("Items you check off will appear here for easy restocking.")
                    )
                    .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(restockItems.enumerated()), id: \.element.id) { index, item in
                            RestockItemRow(item: item, onRestock: { onRestock(item) })
                                .opacity(0)
                                .onAppear {} // Staggered fade handled via animation
                                .animation(
                                    .easeOut(duration: 0.2).delay(WowAnimation.staggerDelay(index: index)),
                                    value: restockItems.count
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .background((colorScheme == .dark ? Color.black : Color(hex: "F9F9F9")).ignoresSafeArea())
            .navigationTitle("Recently Purchased")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }
}

private struct RestockItemRow: View {
    let item: ShoppingItem
    let onRestock: () -> Void

    var body: some View {
        HStack {
            Text(item.title)
                .font(.system(size: 15))
                .lineLimit(1)

            Spacer()

            Button {
                onRestock()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    ShoppingListView()
        .environmentObject(UserSession.shared)
}
