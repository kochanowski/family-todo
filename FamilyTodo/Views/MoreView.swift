import SwiftUI

/// More screen - hub for settings, profile, and configuration
struct MoreView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // Menu items
                ScrollView {
                    VStack(spacing: 16) {
                        // Profile card
                        NavigationLink {
                            ProfileView()
                        } label: {
                            ProfileCard()
                        }
                        .buttonStyle(.plain)

                        // Settings group
                        VStack(spacing: 0) {
                            NavigationLink {
                                CategoriesManagementView()
                            } label: {
                                MenuRow(icon: "folder", title: "Backlog Categories")
                            }

                            Divider()
                                .padding(.leading, 52)

                            NavigationLink {
                                RepetitiveTasksView()
                            } label: {
                                MenuRow(icon: "arrow.trianglehead.2.clockwise.rotate.90", title: "Repetitive Tasks")
                            }

                            Divider()
                                .padding(.leading, 52)

                            NavigationLink {
                                SettingsView()
                            } label: {
                                MenuRow(icon: "gear", title: "Settings")
                            }
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(cardBackground)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }

                Spacer()
            }
            .background(backgroundColor.ignoresSafeArea())
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("More")
                .font(.system(size: 28, weight: .bold))

            Spacer()
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : Color(hex: "F9F9F9")
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "1C1C1E") : .white
    }
}

// MARK: - Profile Card

struct ProfileCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession

    var body: some View {
        HStack(spacing: 16) {
            // Avatar stack
            ZStack {
                Circle()
                    .fill(.blue)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(String(userSession.displayName?.prefix(1) ?? "U"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                // .offset(x: -10) // TODO: Multi-avatar logic
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(userSession.displayName ?? "User")
                    .font(.system(size: 17, weight: .semibold))

                Text(householdStore.currentHousehold?.name ?? "No Household")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        }
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "1C1C1E") : .white
    }
}

// MARK: - Menu Row

struct MenuRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.blue)
                .frame(width: 28)

            Text(title)
                .font(.system(size: 16))

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Sub-screens

struct ProfileView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var householdStore: HouseholdStore

    var body: some View {
        List {
            Section("Household") {
                if let household = householdStore.currentHousehold {
                    LabeledContent("Name", value: household.name)
                } else {
                    Text("No Household Selected")
                }
            }

            Section("Members") {
                if let household = householdStore.currentHousehold {
                    NavigationLink {
                        MemberManagementView(householdId: household.id)
                    } label: {
                        Text("Manage Members")
                    }
                } else {
                    Text("Select a household first")
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MemberRow: View {
    let name: String
    let initials: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

            Text(name)
                .font(.system(size: 16))

            Spacer()
        }
    }
}

struct CategoriesManagementView: View {
    @State private var categories: [String] = []
    @State private var newCategoryName = ""

    var body: some View {
        List {
            ForEach(categories, id: \.self) { category in
                Text(category)
            }
            .onDelete { indexSet in
                categories.remove(atOffsets: indexSet)
            }

            Section {
                HStack {
                    TextField("New category", text: $newCategoryName)
                        .onSubmit {
                            addCategory()
                        }

                    Button {
                        addCategory()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("Backlog Categories")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addCategory() {
        guard !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        categories.append(newCategoryName.trimmingCharacters(in: .whitespaces))
        newCategoryName = ""
    }
}

struct RepetitiveTasksView: View {
    var body: some View {
        ContentUnavailableView(
            "Coming Soon",
            systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
            description: Text("Repetitive tasks will be available in a future update.")
        )
        .navigationTitle("Repetitive Tasks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var celebrationsEnabled = true
    @State private var suggestionsEnabled = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            Section("Appearance") {
                Picker(
                    "Theme",
                    selection: Binding(
                        get: { themeStore.preset },
                        set: { themeStore.preset = $0 }
                    )
                ) {
                    ForEach(ThemePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Features") {
                Toggle("Celebrations", isOn: $celebrationsEnabled)
                Toggle("Suggestions", isOn: $suggestionsEnabled)
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    // Sign out action
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    MoreView()
        .environmentObject(ThemeStore())
}
