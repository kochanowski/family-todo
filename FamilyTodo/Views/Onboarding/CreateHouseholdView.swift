import SwiftUI
import UIKit

struct CreateHouseholdView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession

    @State private var householdName = ""
    @State private var isCreating = false
    @State private var isJoining = false
    @State private var showJoinSheet = false
    @State private var joinCode = ""
    @State private var joinErrorMessage: String?
    @State private var selectedIconSymbol = "house.fill"
    @State private var pendingCustomJoinInviteCode: String?
    @State private var showCustomJoinConfirmation = false
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

                    VStack(spacing: 12) {
                        Text("Choose icon")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(Self.availableHouseholdSymbols, id: \.self) { symbol in
                                Button {
                                    selectedIconSymbol = symbol
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(selectedIconSymbol == symbol ? .white : .primary)
                                        .frame(width: 40, height: 40)
                                        .background(
                                            Circle()
                                                .fill(selectedIconSymbol == symbol ? Color.blue : Color.secondary.opacity(0.15))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 24)

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
                                .fill(householdName.isEmpty ? Color.secondary : Color.blue)
                        )
                    }
                    .disabled(householdName.isEmpty || isCreating || !userSession.hasActiveSession)
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
                    .disabled(!canJoinViaInvite)

                    if !userSession.hasActiveSession {
                        Text("Sign in or continue as guest before creating or joining household.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else if userSession.syncMode != .cloud {
                        Text("Guest mode can create local household. Joining via invite requires Apple/iCloud sign in.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Spacer()
                        .frame(height: 60)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showJoinSheet) {
                CreateJoinSheet(
                    joinCode: $joinCode,
                    onJoin: joinHousehold,
                    onPasteFromClipboard: {
                        joinCode = UIPasteboard.general.string ?? ""
                    }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showCustomJoinConfirmation) {
                AppConfirmationSheet(
                    title: "Join this household?",
                    message: "This invite uses a custom deep link. Confirm before joining.",
                    primaryTitle: "Join",
                    onPrimary: confirmCustomJoin
                )
            }
            .alert("Action failed", isPresented: Binding(
                get: { joinErrorMessage != nil },
                set: { if !$0 { joinErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(joinErrorMessage ?? "Unknown error")
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
        }
    }

    private var canJoinViaInvite: Bool {
        userSession.hasActiveSession && userSession.syncMode == .cloud
    }

    private func createHousehold() {
        guard !householdName.isEmpty else { return }
        guard userSession.hasActiveSession, let userId = userSession.userId else {
            joinErrorMessage = "Sign in or continue as guest before creating household."
            return
        }

        isCreating = true

        _Concurrency.Task {
            do {
                // Ensure sync mode is set based on user session
                householdStore.setSyncMode(userSession.syncMode)

                let newHousehold = try await householdStore.createHousehold(
                    name: householdName,
                    userId: userId,
                    displayName: resolvedDisplayName(),
                    iconSymbol: selectedIconSymbol
                )
                userSession.setCurrentHousehold(newHousehold.id)
                onboardingState.completeHouseholdSetup(withHousehold: true)
            } catch {
                joinErrorMessage = error.localizedDescription
                print("Error creating household: \(error)")
                isCreating = false
            }
        }
    }

    private func joinHousehold() {
        guard canJoinViaInvite else {
            joinErrorMessage = "Joining via invite requires Apple/iCloud sign in."
            return
        }
        guard let userId = userSession.userId else {
            joinErrorMessage = "Could not determine your account identity."
            return
        }

        guard !joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isJoining else { return }

        isJoining = true
        joinErrorMessage = nil

        _Concurrency.Task {
            do {
                let normalizedInvite = try InviteInputNormalizer.normalizeInput(joinCode)
                let displayName = try resolvedDisplayName()
                if normalizedInvite.requiresConfirmation {
                    pendingCustomJoinInviteCode = normalizedInvite.inviteCode
                    showCustomJoinConfirmation = true
                    isJoining = false
                    return
                }

                try await performJoinHousehold(
                    inviteCode: normalizedInvite.inviteCode,
                    userId: userId,
                    displayName: displayName
                )
            } catch {
                joinErrorMessage = error.localizedDescription
            }

            isJoining = false
        }
    }

    private func confirmCustomJoin() {
        guard let inviteCode = pendingCustomJoinInviteCode else { return }
        guard canJoinViaInvite else {
            joinErrorMessage = "Joining via invite requires Apple/iCloud sign in."
            return
        }
        guard let userId = userSession.userId else {
            joinErrorMessage = "Could not determine your account identity."
            return
        }

        pendingCustomJoinInviteCode = nil
        isJoining = true
        _Concurrency.Task {
            do {
                try await performJoinHousehold(
                    inviteCode: inviteCode,
                    userId: userId,
                    displayName: resolvedDisplayName()
                )
            } catch {
                joinErrorMessage = error.localizedDescription
            }

            isJoining = false
        }
    }

    private func performJoinHousehold(inviteCode: String, userId: String, displayName: String) async throws {
        householdStore.setSyncMode(userSession.syncMode)
        try await householdStore.joinHousehold(
            inviteCode: inviteCode,
            userId: userId,
            displayName: displayName
        )
        if let household = householdStore.currentHousehold {
            userSession.setCurrentHousehold(household.id)
        }

        joinCode = ""
        showJoinSheet = false
        onboardingState.completeHouseholdSetup(withHousehold: true)
    }

    private func resolvedDisplayName() throws -> String {
        guard let displayName = userSession.displayName else {
            throw DisplayNameValidationError.empty
        }
        return try DisplayNameValidator.validate(displayName)
    }

    private static let availableHouseholdSymbols = [
        "house.fill",
        "star.fill",
        "heart.fill",
        "leaf.fill",
        "pawprint.fill",
    ]
}

// MARK: - Join Sheet (local to this view)

private struct CreateJoinSheet: View {
    @Binding var joinCode: String
    let onJoin: () -> Void
    let onPasteFromClipboard: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false
    @State private var scannerErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)

                Text("Enter your invite link")
                    .font(.system(size: 22, weight: .bold))

                TextField("https://www.icloud.com/share/...", text: $joinCode)
                    .font(.system(size: 20))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .padding(.horizontal, 32)

                Button {
                    onJoin()
                } label: {
                    Text("Join Household")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(joinCode.isEmpty ? Color.secondary : Color.blue)
                        )
                }
                .disabled(joinCode.isEmpty)
                .padding(.horizontal, 40)

                HStack(spacing: 12) {
                    Button {
                        onPasteFromClipboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan QR", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
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
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRCodeScannerView(
                        onCodeScanned: { scanned in
                            joinCode = scanned
                            showScanner = false
                        },
                        onFailure: { message in
                            scannerErrorMessage = message
                            showScanner = false
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showScanner = false
                            }
                        }
                    }
                }
            }
            .alert("Scanner error", isPresented: Binding(
                get: { scannerErrorMessage != nil },
                set: { if !$0 { scannerErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scannerErrorMessage ?? "Unknown camera error")
            }
        }
    }
}

#Preview {
    CreateHouseholdView()
        .environmentObject(OnboardingState())
        .environmentObject(HouseholdStore())
        .environmentObject(UserSession.shared)
        .environmentObject(ThemeStore())
}
