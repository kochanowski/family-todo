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
    @State private var newItemText = ""
    @State private var showRestock = false
    @FocusState private var isInputFocused: Bool
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

            // Items list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.toBuyItems) { item in
                        ShoppingItemRow(item: item, onToggle: { toggleItem(item) })
                    }
                }
                .padding(.horizontal, 20)
            }
            .refreshable {
                await store.loadItems()
            }

            Spacer()

            // Floating input row
            inputRow
                .padding(.horizontal, 20)
                .padding(.bottom, 100) // Space for tab bar
        }
        .background(backgroundColor.ignoresSafeArea())
        .task {
            // Set context for offline support if not already set by init
            // store.setModelContext(modelContext) // managed by init
            await store.loadItems()
        }
        .onChange(of: store.error as NSError?) { _, _ in
            // Handle error (e.g. toast)
        }
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

            // Restock button
            Button {
                showRestock = true
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .sheet(isPresented: $showRestock) {
                RestockSheet(restockItems: store.boughtItems, onRestock: toggleItem)
            }
        }
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(spacing: 12) {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                .frame(width: 24, height: 24)

            TextField("Add item", text: $newItemText)
                .font(.system(size: 15))
                .focused($isInputFocused)
                .onSubmit {
                    addItem()
                    isInputFocused = true // Keep focus for rapid entry
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        }
    }

    // MARK: - Data Actions

    private func addItem() {
        guard !newItemText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        _Concurrency.Task {
            await store.createItem(title: newItemText.trimmingCharacters(in: .whitespaces))
        }

        newItemText = ""
        HapticManager.lightTap()
    }

    private func toggleItem(_ item: ShoppingItem) {
        _Concurrency.Task {
            await store.toggleBought(item)
        }
        HapticManager.mediumTap()
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

                Spacer()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Restock Sheet

struct RestockSheet: View {
    let restockItems: [ShoppingItem]
    let onRestock: (ShoppingItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if restockItems.isEmpty {
                    ContentUnavailableView(
                        "No Recent Purchases",
                        systemImage: "cart",
                        description: Text("Items you check off will appear here for easy restocking.")
                    )
                } else {
                    ForEach(restockItems) { item in
                        HStack {
                            Text(item.title)
                                .font(.system(size: 15))

                            Spacer()

                            Button {
                                onRestock(item)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
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
    }
}

#Preview {
    ShoppingListView()
        .environmentObject(UserSession.shared)
}
