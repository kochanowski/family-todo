import SwiftUI

/// Backlog screen - long-term storage for ideas and projects, organized by categories
struct BacklogView: View {
    @State private var categories: [BacklogCategoryItem] = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Content
            if categories.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(categories) { category in
                            CategoryCard(
                                category: category,
                                onAddItem: { addItem(to: category) },
                                onDeleteItem: { item in deleteItem(item, from: category) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
            }

            Spacer()
        }
        .background(backgroundColor.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Backlog")
                .font(.system(size: 28, weight: .bold))

            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Categories", systemImage: "archivebox")
        } description: {
            Text("Go to More > Backlog Categories to create categories and organize your backlog items.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Actions

    private func addItem(to _: BacklogCategoryItem) {
        // Will be implemented with store
    }

    private func deleteItem(_: BacklogItemData, from _: BacklogCategoryItem) {
        // Will be implemented with store
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : Color(hex: "F9F9F9")
    }
}

// MARK: - Local Models

struct BacklogCategoryItem: Identifiable {
    let id: UUID
    var title: String
    var items: [BacklogItemData]
}

struct BacklogItemData: Identifiable {
    let id: UUID
    var title: String
}

// MARK: - Category Card

struct CategoryCard: View {
    let category: BacklogCategoryItem
    let onAddItem: () -> Void
    let onDeleteItem: (BacklogItemData) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var newItemText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header
            Text(category.title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Items
            ForEach(category.items) { item in
                BacklogItemRow(item: item)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDeleteItem(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }

            // Add item row
            Button(action: onAddItem) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)

                    Text("Add item")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        }
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "1C1C1E") : .white
    }
}

// MARK: - Backlog Item Row

struct BacklogItemRow: View {
    let item: BacklogItemData

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)

            Text(item.title)
                .font(.system(size: 15))

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    BacklogView()
}
