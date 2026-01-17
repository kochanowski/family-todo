import SwiftUI

/// Onboarding flow for new users to create or join a household
struct OnboardingView: View {
    @ObservedObject var householdStore: HouseholdStore
    let userId: String
    let displayName: String

    @State private var showCreateSheet = false
    @State private var showJoinSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Welcome
                VStack(spacing: 12) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)

                    Text("Welcome to Family To-Do")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Create a household to start managing tasks together")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Actions
                VStack(spacing: 16) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Create Household", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        showJoinSheet = true
                    } label: {
                        Label("Join Household", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateHouseholdSheet(
                    householdStore: householdStore,
                    userId: userId,
                    displayName: displayName
                )
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinHouseholdSheet(
                    householdStore: householdStore,
                    userId: userId,
                    displayName: displayName
                )
            }
        }
    }
}

// MARK: - Create Household Sheet

struct CreateHouseholdSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var householdStore: HouseholdStore
    let userId: String
    let displayName: String

    @State private var householdName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Household name", text: $householdName)
                        .textContentType(.organizationName)
                } footer: {
                    Text("e.g., \"Smith Family\" or \"Our Home\"")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Create Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createHousehold()
                    }
                    .disabled(householdName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .interactiveDismissDisabled(isCreating)
        }
    }

    private func createHousehold() {
        let name = householdName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        _Concurrency.Task {
            do {
                try await householdStore.createHousehold(
                    name: name,
                    userId: userId,
                    displayName: displayName
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

// MARK: - Join Household Sheet

struct JoinHouseholdSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var householdStore: HouseholdStore
    let userId: String
    let displayName: String

    @State private var inviteCode = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $inviteCode)
                        .textContentType(.oneTimeCode)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } footer: {
                    Text("Ask the household owner for the invite code")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Join Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        joinHousehold()
                    }
                    .disabled(inviteCode.trimmingCharacters(in: .whitespaces).isEmpty || isJoining)
                }
            }
            .interactiveDismissDisabled(isJoining)
        }
    }

    private func joinHousehold() {
        let code = inviteCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }

        isJoining = true
        errorMessage = nil

        _Concurrency.Task {
            do {
                try await householdStore.joinHousehold(
                    inviteCode: code,
                    userId: userId,
                    displayName: displayName
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isJoining = false
            }
        }
    }
}

#Preview {
    OnboardingView(
        householdStore: HouseholdStore(),
        userId: "test-user",
        displayName: "Test User"
    )
}
