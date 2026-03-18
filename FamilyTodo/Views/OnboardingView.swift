import SwiftUI

/// Onboarding flow for new users to create or join a household
struct OnboardingView: View {
    @ObservedObject var householdStore: HouseholdStore
    let userId: String
    let displayName: String
    let isCloudSyncEnabled: Bool
    @EnvironmentObject private var themeStore: ThemeStore

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

                    Text("Welcome to HousePulse")
                        .font(themeStore.font(for: .screenHeader))
                        .foregroundStyle(themeStore.contentPrimaryColor)

                    Text("Create a household to start managing tasks together")
                        .font(themeStore.font(for: .listRowTitle))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if !isCloudSyncEnabled {
                        Text("Guest mode keeps everything on this device.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()

                // Actions
                VStack(spacing: 16) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Create Household", systemImage: "plus.circle.fill")
                            .font(themeStore.font(for: .buttonLabel))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        showJoinSheet = true
                    } label: {
                        Label("Join Household", systemImage: "person.badge.plus")
                            .font(themeStore.font(for: .buttonLabel))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!isCloudSyncEnabled)

                    if !isCloudSyncEnabled {
                        Text("Sign in to join an existing household or invite others.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .ignoresSafeArea(edges: .bottom)
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
            .onAppear {
                if householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    householdName = defaultHouseholdName()
                }
            }
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
        guard let resolvedDisplayName = resolvedDisplayNameForMembership() else {
            errorMessage = HouseholdError.displayNameRequired.localizedDescription
            return
        }

        isCreating = true
        errorMessage = nil

        _Concurrency.Task {
            do {
                _ = try await householdStore.createHousehold(
                    name: name,
                    userId: userId,
                    displayName: resolvedDisplayName
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }

    private func resolvedDisplayNameForMembership() -> String? {
        try? DisplayNameValidator.validate(displayName)
    }

    private func defaultHouseholdName() -> String {
        if let validated = try? DisplayNameValidator.validate(displayName) {
            return "\(validated)'s Household"
        }
        return "My Household"
    }
}

// MARK: - Join Household Sheet

struct JoinHouseholdSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var householdStore: HouseholdStore
    let userId: String
    let displayName: String

    @State private var inviteInput = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("8-character invite code", text: $inviteInput)
                        .textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .onChange(of: inviteInput) { _, newValue in
                            inviteInput = normalizedInviteCodeInput(newValue)
                        }
                } footer: {
                    Text("Ask the household owner for the 8-character invite code.")
                }

                if isJoining {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Joining household...")
                        }
                    }
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
                    .disabled(preferredInviteCode() == nil || isJoining)
                }
            }
            .interactiveDismissDisabled(isJoining)
        }
    }

    private func joinHousehold() {
        guard let inviteCode = preferredInviteCode() else { return }
        guard let resolvedDisplayName = resolvedDisplayNameForMembership() else {
            errorMessage = HouseholdError.displayNameRequired.localizedDescription
            return
        }

        isJoining = true
        errorMessage = nil

        _Concurrency.Task {
            do {
                try await householdStore.joinHousehold(
                    inviteCode: inviteCode,
                    userId: userId,
                    displayName: resolvedDisplayName
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isJoining = false
            }
        }
    }

    private func resolvedDisplayNameForMembership() -> String? {
        try? DisplayNameValidator.validate(displayName)
    }

    private func normalizedInviteCodeInput(_ raw: String) -> String {
        let uppercased = raw.uppercased()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let filtered = String(uppercased.unicodeScalars.filter { allowed.contains($0) })
        return String(filtered.prefix(8))
    }

    private func preferredInviteCode() -> String? {
        guard let normalizedCode = InviteInputNormalizer.normalizeInviteCodeToken(inviteInput),
              normalizedCode.count == 8
        else {
            return nil
        }
        return normalizedCode
    }
}

#Preview {
    OnboardingView(
        householdStore: HouseholdStore(),
        userId: "test-user",
        displayName: "Test User",
        isCloudSyncEnabled: true
    )
    .environmentObject(ThemeStore())
}
