import SwiftUI

/// Shopping List screen - quick capture and management of groceries
struct ShoppingListView: View {
    @State private var items: [ShoppingItem] = []
    @State private var newItemText = ""
    @State private var showRestock = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

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
                    ForEach(activeItems) { item in
                        ShoppingItemRow(item: item, onToggle: { toggleItem(item) })
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            // Floating input row
            inputRow
                .padding(.horizontal, 20)
                .padding(.bottom, 100) // Space for tab bar
        }
        .background(backgroundColor.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Shopping")
                .font(.system(size: 28, weight: .bold))

            // Item count badge
            if !activeItems.isEmpty {
                Text("\(activeItems.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.blue))
            }

            Spacer()

            // Clear all button
            if !activeItems.isEmpty {
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
                RestockSheet(restockItems: restockItems, onRestock: restockItem)
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

    // MARK: - Data

    private var activeItems: [ShoppingItem] {
        items.filter { !$0.isBought }
    }

    private var restockItems: [ShoppingItem] {
        items.filter(\.isBought)
    }

    private func addItem() {
        guard !newItemText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let item = ShoppingItem(
            id: UUID(),
            householdId: UUID(), // TODO: Get from context
            title: newItemText.trimmingCharacters(in: .whitespaces)
        )
        items.append(item)
        newItemText = ""

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func toggleItem(_ item: ShoppingItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isBought.toggle()
            items[index].boughtAt = items[index].isBought ? Date() : nil

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }

    private func clearAll() {
        // Mark all as bought
        for index in items.indices where !items[index].isBought {
            items[index].isBought = true
            items[index].boughtAt = Date()
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func restockItem(_ item: ShoppingItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isBought = false
            items[index].boughtAt = nil
            items[index].restockCount += 1
        }
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
}
