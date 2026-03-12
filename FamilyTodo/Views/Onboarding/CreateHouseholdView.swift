import SwiftUI
import UIKit

struct CreateHouseholdView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    private let allowsJoin: Bool
    private let showsCloseButton: Bool

    @State private var householdName = ""
    @State private var isCreating = false
    @State private var isJoining = false
    @State private var showJoinSheet = false
    @State private var joinInput = ""
    @State private var joinInviteCode = ""
    @State private var joinErrorMessage: String?
    @State private var selectedIconSymbol = "house.fill"
    @State private var pendingCustomJoinInviteCode: String?
    @State private var showCustomJoinConfirmation = false
    @FocusState private var isTextFieldFocused: Bool

    init(allowsJoin: Bool = true, showsCloseButton: Bool = false) {
        self.allowsJoin = allowsJoin
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                themeStore.canvasColor
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()
                        .frame(height: 40)

                    // Header
                    VStack(spacing: 8) {
                        Text("Name your household.")
                            .font(themeStore.font(for: .screenHeader))
                            .foregroundStyle(themeStore.contentPrimaryColor)

                        Text("This name will be visible to members you invite.")
                            .font(themeStore.font(for: .listRowTitle))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    VStack(spacing: 12) {
                        Text("Choose icon")
                            .font(themeStore.font(for: .bodyStrong))
                            .foregroundStyle(themeStore.contentSecondaryColor)

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
                            .font(themeStore.font(for: .screenHeader))
                            .multilineTextAlignment(.center)
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                if !householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                        .font(themeStore.font(for: .buttonLabel))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(
                                    householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color.secondary : Color.blue
                                )
                        )
                    }
                    .disabled(
                        householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            isCreating || !userSession.hasActiveSession
                    )
                    .padding(.horizontal, 40)

                    if allowsJoin {
                        // Join Link
                        Button {
                            showJoinSheet = true
                        } label: {
                            Text("Have an invite code? ")
                                .foregroundStyle(themeStore.contentSecondaryColor)
                                + Text("Join Household")
                                .foregroundStyle(themeStore.contentPrimaryColor)
                                .bold()
                        }
                        .font(themeStore.font(for: .buttonLabel))
                        .disabled(!canJoinViaInvite || isCreating)
                    }

                    if !userSession.hasActiveSession {
                        Text("Sign in or continue as guest before creating or joining household.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else if userSession.syncMode != .cloud {
                        Text("Guest mode can create local household. Joining via invite requires Apple/iCloud sign in.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Spacer()
                        .frame(height: 60)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showJoinSheet) {
                HouseholdJoinSheet(
                    inviteCodeToken: $joinInviteCode,
                    inviteLink: $joinInput,
                    isJoining: isJoining,
                    onJoin: joinHousehold,
                    onPasteFromClipboard: {
                        joinInput = UIPasteboard.general.string ?? ""
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
                if householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    householdName = defaultHouseholdName()
                }
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
        householdName = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    displayName: fallbackDisplayNameForMembership(),
                    iconSymbol: selectedIconSymbol
                )
                userSession.setCurrentHousehold(newHousehold.id)
                onboardingState.completeHouseholdSetup(withHousehold: true)
                if showsCloseButton {
                    dismiss()
                }
            } catch {
                joinErrorMessage = error.localizedDescription
                print("Error creating household: \(error)")
                isCreating = false
            }
        }
    }

    private func joinHousehold() {
        guard allowsJoin else { return }
        guard canJoinViaInvite else {
            joinErrorMessage = "Joining via invite requires Apple/iCloud sign in."
            return
        }
        guard let userId = userSession.userId else {
            joinErrorMessage = "Could not determine your account identity."
            return
        }

        let rawInviteInput = preferredJoinInput()
        guard !rawInviteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isJoining else { return }

        isJoining = true
        joinErrorMessage = nil

        _Concurrency.Task {
            do {
                let normalizedInvite = try InviteInputNormalizer.normalizeInput(rawInviteInput)
                let displayName = fallbackDisplayNameForMembership()
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
        guard allowsJoin else { return }
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
                    displayName: fallbackDisplayNameForMembership()
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
            withInviteInput: inviteCode,
            userId: userId,
            displayName: displayName
        )
        if let household = householdStore.currentHousehold {
            userSession.setCurrentHousehold(household.id)
        }

        joinInput = ""
        joinInviteCode = ""
        showJoinSheet = false
        onboardingState.completeHouseholdSetup(withHousehold: true)
    }

    private func preferredJoinInput() -> String {
        if let normalizedCode = InviteInputNormalizer.normalizeInviteCodeToken(joinInviteCode) {
            return normalizedCode
        }
        return joinInput
    }

    private func fallbackDisplayNameForMembership() -> String {
        if let displayName = userSession.displayName,
           let validated = try? DisplayNameValidator.validate(displayName)
        {
            return validated
        }
        return userSession.isGuest ? "Guest" : "Member"
    }

    private func defaultHouseholdName() -> String {
        let rawName = userSession.preferredDisplayName ??
            userSession.displayName ??
            userSession.user?.givenName
        if let rawName,
           let validated = try? DisplayNameValidator.validate(rawName)
        {
            return "\(validated)'s Household"
        }
        return "My Household"
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

struct HouseholdJoinSheet: View {
    @Binding var inviteCodeToken: String
    @Binding var inviteLink: String
    let isJoining: Bool
    let onJoin: () -> Void
    let onPasteFromClipboard: () -> Void
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false
    @State private var scannerErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)

                Text("Enter Invite Code")
                    .font(themeStore.font(for: .screenHeader))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                TextField("A7B9XQ2M", text: $inviteCodeToken)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .disabled(isJoining)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .padding(.horizontal, 32)
                    .onChange(of: inviteCodeToken) { _, newValue in
                        inviteCodeToken = normalizedInviteCodeInput(newValue)
                    }

                Text("Use the 8-character invite code (A-Z, 0-9)")
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(themeStore.contentSecondaryColor)

                Button {
                    onJoin()
                } label: {
                    HStack(spacing: 10) {
                        if isJoining {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isJoining ? "Joining..." : "Join with code")
                            .font(themeStore.font(for: .buttonLabel))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(canJoinWithCode && !isJoining ? Color.blue : Color.secondary)
                    )
                }
                .disabled(!canJoinWithCode || isJoining)
                .padding(.horizontal, 40)

                Divider()
                    .padding(.horizontal, 40)

                Text("Or join with invite link")
                    .font(themeStore.font(for: .bodyStrong))
                    .foregroundStyle(themeStore.contentSecondaryColor)

                TextField("https://www.icloud.com/share/...", text: $inviteLink)
                    .font(themeStore.font(for: .listRowTitle))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .disabled(isJoining)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .padding(.horizontal, 32)

                Button {
                    onJoin()
                } label: {
                    HStack(spacing: 10) {
                        if isJoining {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isJoining ? "Joining..." : "Join with link")
                            .font(themeStore.font(for: .buttonLabel))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(canJoinWithLink && !isJoining ? Color.blue : Color.secondary)
                    )
                }
                .disabled(!canJoinWithLink || isJoining)
                .padding(.horizontal, 40)

                if isJoining {
                    ProgressView("Joining household...")
                        .font(themeStore.font(for: .bodySmall))
                        .tint(themeStore.accentTabColor)
                }

                HStack(spacing: 12) {
                    Button {
                        onPasteFromClipboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .font(themeStore.font(for: .buttonLabel))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isJoining)

                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan QR", systemImage: "qrcode.viewfinder")
                            .font(themeStore.font(for: .buttonLabel))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isJoining)
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
                    .disabled(isJoining)
                }
            }
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRCodeScannerView(
                        onCodeScanned: { scanned in
                            inviteLink = scanned
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

    private var canJoinWithCode: Bool {
        InviteInputNormalizer.normalizeInviteCodeToken(inviteCodeToken) != nil
    }

    private var canJoinWithLink: Bool {
        !inviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func normalizedInviteCodeInput(_ raw: String) -> String {
        let uppercased = raw.uppercased()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let filtered = String(uppercased.unicodeScalars.filter { allowed.contains($0) })
        return String(filtered.prefix(8))
    }
}

#Preview {
    CreateHouseholdView()
        .environmentObject(OnboardingState())
        .environmentObject(HouseholdStore())
        .environmentObject(UserSession.shared)
        .environmentObject(ThemeStore())
}
