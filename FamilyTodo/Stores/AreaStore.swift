import Foundation

/// Store for area/board management
@MainActor
final class AreaStore: ObservableObject {
    @Published private(set) var areas: [Area] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private let cloudKit = CloudKitManager.shared
    private let householdId: UUID?

    init(householdId: UUID?) {
        self.householdId = householdId
    }

    // MARK: - Load Areas

    func loadAreas() async {
        guard let householdId else { return }

        isLoading = true
        error = nil

        do {
            areas = try await cloudKit.fetchAreas(householdId: householdId)
            areas.sort { $0.sortOrder < $1.sortOrder }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Create Area

    func createArea(name: String, icon: String?) async {
        guard let householdId else { return }

        let sortOrder = (areas.map(\.sortOrder).max() ?? -1) + 1

        let area = Area(
            householdId: householdId,
            name: name,
            icon: icon,
            sortOrder: sortOrder
        )

        // Optimistic update
        areas.append(area)

        do {
            _ = try await cloudKit.saveArea(area)
        } catch {
            // Rollback
            areas.removeAll { $0.id == area.id }
            self.error = error
        }
    }

    // MARK: - Update Area

    func updateArea(_ area: Area) async {
        // Optimistic update
        if let index = areas.firstIndex(where: { $0.id == area.id }) {
            areas[index] = area
        }

        do {
            _ = try await cloudKit.saveArea(area)
        } catch {
            self.error = error
            await loadAreas() // Reload to get correct state
        }
    }

    // MARK: - Delete Area

    func deleteArea(_ area: Area) async {
        // Optimistic update
        areas.removeAll { $0.id == area.id }

        do {
            try await cloudKit.deleteArea(id: area.id)
        } catch {
            self.error = error
            await loadAreas() // Reload to get correct state
        }
    }
}
