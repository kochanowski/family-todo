import Foundation

/// Store for shared shopping list management
@MainActor
final class ShoppingListStore: ObservableObject {
    @Published private(set) var items: [ShoppingItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private lazy var cloudKit = CloudKitManager.shared
    private let householdId: UUID?

    init(householdId: UUID?) {
        self.householdId = householdId
    }

    var toBuyItems: [ShoppingItem] {
        items
            .filter { !$0.isBought }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var boughtItems: [ShoppingItem] {
        items
            .filter { $0.isBought }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Load Items

    func loadItems() async {
        guard let householdId else { return }

        isLoading = true
        error = nil

        do {
            items = try await cloudKit.fetchShoppingItems(householdId: householdId)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Create Item

    func createItem(title: String, quantityValue: String? = nil, quantityUnit: String? = nil) async {
        guard let householdId else { return }

        let item = ShoppingItem(
            householdId: householdId,
            title: title,
            quantityValue: quantityValue,
            quantityUnit: quantityUnit,
            isBought: false
        )

        items.append(item)

        do {
            _ = try await cloudKit.saveShoppingItem(item)
        } catch {
            items.removeAll { $0.id == item.id }
            self.error = error
        }
    }

    // MARK: - Update Item

    func updateItem(_ item: ShoppingItem) async {
        var updatedItem = item
        updatedItem.updatedAt = Date()

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updatedItem
        }

        do {
            _ = try await cloudKit.saveShoppingItem(updatedItem)
        } catch {
            self.error = error
            await loadItems()
        }
    }

    // MARK: - Toggle Bought

    func toggleBought(_ item: ShoppingItem) async {
        var updatedItem = item
        updatedItem.isBought.toggle()
        updatedItem.boughtAt = updatedItem.isBought ? Date() : nil
        await updateItem(updatedItem)
    }

    // MARK: - Delete Item

    func deleteItem(_ item: ShoppingItem) async {
        items.removeAll { $0.id == item.id }

        do {
            try await cloudKit.deleteShoppingItem(id: item.id)
        } catch {
            self.error = error
            await loadItems()
        }
    }
}
