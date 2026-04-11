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
    @State private var joinInviteCode = ""
    @State private var joinErrorMessage: String?
    @State private var selectedIconSymbol = "house.fill"
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
                            isCreating ||
                            !userSession.hasActiveSession ||
                            confirmedMembershipDisplayName == nil
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
                        .disabled(!canJoinViaInvite || isCreating || confirmedMembershipDisplayName == nil)
                    }

                    if userSession.syncMode == .cloud, userSession.hasActiveSession {
                        Text("After creating, invite members from your household settings.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
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
                .appAdaptiveWidth(
                    maxWidth: AppChromeMetrics.regularFormMaxWidth,
                    alignment: .top
                )
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
                    isJoining: isJoining,
                    onJoin: joinHousehold,
                    onPasteFromClipboard: {
                        joinInviteCode = UIPasteboard.general.string ?? ""
                    }
                )
                .presentationDetents([.large])
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
        guard let displayName = confirmedMembershipDisplayName else {
            joinErrorMessage = HouseholdError.displayNameRequired.localizedDescription
            return
        }
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
                    displayName: displayName,
                    iconSymbol: selectedIconSymbol
                )
                await MainActor.run {
                    userSession.applyProfileUpdate(displayName: displayName)
                }
                userSession.setCurrentHousehold(newHousehold.id)
                if userSession.syncMode == .cloud {}
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
        guard let displayName = confirmedMembershipDisplayName else {
            joinErrorMessage = HouseholdError.displayNameRequired.localizedDescription
            return
        }

        let inviteCode = preferredJoinCode()
        guard let inviteCode else { return }
        guard !isJoining else { return }

        isJoining = true
        joinErrorMessage = nil

        _Concurrency.Task {
            do {
                try await performJoinHousehold(
                    inviteCode: inviteCode,
                    userId: userId,
                    displayName: displayName
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
        let resolvedDisplayName = householdStore.resolveMembershipDisplayNameLocally(
            userId: userId,
            preferredHouseholdId: householdStore.currentHousehold?.id
        ) ?? displayName
        await MainActor.run {
            userSession.applyProfileUpdate(displayName: resolvedDisplayName)
        }
        if let household = householdStore.currentHousehold {
            userSession.setCurrentHousehold(household.id)
        }

        joinInviteCode = ""
        showJoinSheet = false
        if userSession.syncMode == .cloud {}
        onboardingState.completeHouseholdSetup(withHousehold: true)
    }

    private func preferredJoinCode() -> String? {
        guard let normalizedCode = InviteInputNormalizer.normalizeInviteCodeToken(joinInviteCode) else {
            return nil
        }
        return normalizedCode
    }

    private var confirmedMembershipDisplayName: String? {
        userSession.confirmedMembershipDisplayName
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
    let isJoining: Bool
    let onJoin: () -> Void
    let onPasteFromClipboard: () -> Void
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false
    @State private var scannerErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        Text("Enter Invite Code")
                            .font(themeStore.font(for: .screenHeader))
                            .foregroundStyle(themeStore.contentPrimaryColor)
                            .multilineTextAlignment(.center)

                        TextField("A7B9XQ", text: $inviteCodeToken, axis: .vertical)
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
                            .onChange(of: inviteCodeToken) { _, newValue in
                                inviteCodeToken = normalizedInviteCodeInput(newValue)
                            }

                        Text("Use the 6-character invite code (A-Z, 0-9). Older 8-character codes still work. QR codes fill this field automatically.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .multilineTextAlignment(.center)

                        Text("Shared lists and tasks usually appear in seconds after you join, but sync can take up to 1-2 minutes.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .multilineTextAlignment(.center)

                        Button {
                            onJoin()
                        } label: {
                            Text("Join with code")
                                .font(themeStore.font(for: .buttonLabel))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    Capsule()
                                        .fill(canJoinWithCode && !isJoining ? themeStore.accentTabColor : Color.secondary)
                                )
                        }
                        .disabled(!canJoinWithCode || isJoining)

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
                    }
                    .padding(24)
                    .appAdaptiveWidth(
                        maxWidth: AppChromeMetrics.regularFormMaxWidth,
                        alignment: .top
                    )
                }

                if isJoining {
                    JoiningHouseholdLoadingView(isActive: isJoining)
                        .environmentObject(themeStore)
                        .transition(.opacity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isJoining)
                }
                ToolbarItem(placement: .principal) {
                    Text("Join Household")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
            }
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRCodeScannerView(
                        onCodeScanned: { scanned in
                            inviteCodeToken = normalizedInviteCodeInput(scanned)
                            showScanner = false
                            if canJoinWithCode, !isJoining {
                                onJoin()
                            }
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
            .interactiveDismissDisabled(isJoining)
        }
    }

    private var canJoinWithCode: Bool {
        InviteInputNormalizer.normalizeInviteCodeToken(inviteCodeToken) != nil
    }

    private func normalizedInviteCodeInput(_ raw: String) -> String {
        let uppercased = raw.uppercased()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let filtered = String(uppercased.unicodeScalars.filter { allowed.contains($0) })
        return String(filtered.prefix(InviteInputNormalizer.maximumInviteCodeLength))
    }
}

#Preview {
    CreateHouseholdView()
        .environmentObject(OnboardingState())
        .environmentObject(HouseholdStore())
        .environmentObject(UserSession.shared)
        .environmentObject(ThemeStore())
}
