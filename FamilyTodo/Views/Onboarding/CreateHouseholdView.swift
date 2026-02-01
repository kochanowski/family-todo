import SwiftUI

struct CreateHouseholdView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession

    @State private var householdName = ""
    @State private var isCreating = false
    @State private var showJoinSheet = false
    @State private var joinCode = ""
    @FocusState private var isTextFieldFocused: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(colorScheme == .dark ? .black : .systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()
                        .frame(height: 40)

                    // Header
                    VStack(spacing: 8) {
                        Text("Name your household.")
                            .font(.system(size: 28, weight: .bold))

                        Text("This name will be visible to members you invite.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Spacer()
                        .frame(height: 20)

                    // Input Field
                    VStack(spacing: 8) {
                        TextField("e.g. Smith Family", text: $householdName)
                            .font(.system(size: 28, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                if !householdName.isEmpty {
                                    createHousehold()
                                }
                            }

                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 1)
                            .padding(.horizontal, 40)
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Create Button
                    Button {
                        createHousehold()
                    } label: {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Create Household")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(householdName.isEmpty ? Color.secondary : Color.primary)
                        )
                    }
                    .disabled(householdName.isEmpty || isCreating)
                    .padding(.horizontal, 40)

                    // Join Link
                    Button {
                        showJoinSheet = true
                    } label: {
                        Text("Have an invite code? ")
                            .foregroundStyle(.secondary)
                            + Text("Join Household")
                            .foregroundStyle(.primary)
                            .bold()
                    }
                    .font(.system(size: 15))

                    Spacer()
                        .frame(height: 60)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        onboardingState.skipHouseholdSetup()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinHouseholdSheet(
                    joinCode: $joinCode,
                    onJoin: joinHousehold
                )
                .presentationDetents([.medium])
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
        }
    }

    private func createHousehold() {
        guard !householdName.isEmpty else { return }
        isCreating = true

        _Concurrency.Task {
            do {
                _ = try await householdStore.createHousehold(
                    name: householdName,
                    userId: userSession.currentUserId ?? "local-user",
                    displayName: userSession.displayName ?? "Me"
                )
                onboardingState.completeHouseholdSetup(withHousehold: true)
            } catch {
                print("Error creating household: \(error)")
                isCreating = false
            }
        }
    }

    private func joinHousehold() {
        // TODO: Implement join via invite code
        // For now, just complete with household active
        onboardingState.completeHouseholdSetup(withHousehold: true)
    }
}

// MARK: - Join Household Sheet

private struct JoinHouseholdSheet: View {
    @Binding var joinCode: String
    let onJoin: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)

                Text("Enter your invite code")
                    .font(.system(size: 22, weight: .bold))

                TextField("Invite Code", text: $joinCode)
                    .font(.system(size: 20))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .padding(.horizontal, 32)

                Button {
                    onJoin()
                    dismiss()
                } label: {
                    Text("Join Household")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(joinCode.isEmpty ? Color.secondary : Color.primary)
                        )
                }
                .disabled(joinCode.isEmpty)
                .padding(.horizontal, 40)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CreateHouseholdView()
        .environmentObject(OnboardingState())
        .environmentObject(HouseholdStore())
        .environmentObject(UserSession.shared)
}
