import SwiftData
import SwiftUI

/// View for managing household areas/boards
struct AreasView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var userSession: UserSession
    @ObservedObject var householdStore: HouseholdStore
    @StateObject private var areaStore: AreaStore
    @State private var showingAddArea = false
    @State private var selectedArea: Area?

    init(householdStore: HouseholdStore) {
        self.householdStore = householdStore
        _areaStore = StateObject(wrappedValue: AreaStore(householdId: householdStore.currentHousehold?.id))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(areaStore.areas) { area in
                    AreaRowView(area: area)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedArea = area
                        }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let area = areaStore.areas[index]
                        _Concurrency.Task {
                            await areaStore.deleteArea(area)
                        }
                    }
                }
            }
            .navigationTitle("Areas")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddArea = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await areaStore.loadAreas()
            }
            .sheet(isPresented: $showingAddArea) {
                AreaDetailView(areaStore: areaStore)
            }
            .sheet(item: $selectedArea) { area in
                AreaDetailView(areaStore: areaStore, area: area)
            }
            .overlay {
                if areaStore.isLoading, areaStore.areas.isEmpty {
                    ProgressView("Loading areas...")
                }
            }
            .task {
                areaStore.setModelContext(modelContext)
                areaStore.setSyncMode(userSession.syncMode)
                await areaStore.loadAreas()
            }
            .onChange(of: userSession.syncMode) { _, newMode in
                areaStore.setSyncMode(newMode)
            }
        }
    }
}

// MARK: - Area Row

struct AreaRowView: View {
    let area: Area

    var body: some View {
        HStack(spacing: 12) {
            if let icon = area.icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)
            }

            Text(area.name)
                .font(.body)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Area Detail View

struct AreaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var areaStore: AreaStore

    let area: Area?

    @State private var name: String
    @State private var selectedIcon: String

    private var isNewArea: Bool {
        area == nil
    }

    private let availableIcons = [
        "fork.knife", "shower", "sofa", "bed.double", "leaf",
        "wrench", "car", "tshirt", "books.vertical", "gamecontroller",
        "desktopcomputer", "heart", "star", "flag", "folder",
    ]

    init(areaStore: AreaStore, area: Area? = nil) {
        self.areaStore = areaStore
        self.area = area
        _name = State(initialValue: area?.name ?? "")
        _selectedIcon = State(initialValue: area?.icon ?? "folder")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Area name", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(selectedIcon == icon ? Color.blue.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(isNewArea ? "New Area" : "Edit Area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveArea()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func saveArea() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        _Concurrency.Task {
            if let existingArea = area {
                var updatedArea = existingArea
                updatedArea.name = trimmedName
                updatedArea.icon = selectedIcon
                await areaStore.updateArea(updatedArea)
            } else {
                await areaStore.createArea(name: trimmedName, icon: selectedIcon)
            }
            dismiss()
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: CachedArea.self, configurations: config)
    } catch {
        fatalError("Failed to create preview container: \(error)")
    }

    return AreasView(householdStore: HouseholdStore())
        .environmentObject(UserSession.shared)
        .modelContainer(container)
}
