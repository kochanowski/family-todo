import SwiftUI
import UIKit

struct CreateHouseholdView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore

    private let allowsJoin: Bool
    private let initialStep: SetupStep?

    enum SetupStep: Int, Identifiable {
        case name = 0
        case household = 1
        case join = 2

        var id: Int {
            rawValue
        }
    }

    @State private var currentStep: SetupStep = .household
    @State private var initialized = false

    // Name Step State
    @State private var displayName = ""
    @State private var displayNameErrorMessage: String?
    @FocusState private var isNameFocused: Bool

    // Household Step State
    @State private var householdName = ""
    @State private var selectedIconSymbol = "house.fill"
    @State private var isCreating = false
    @State private var createErrorMessage: String?
    @FocusState private var isHouseholdNameFocused: Bool

    // Join Step State
    @State private var joinInviteCode = ""
    @State private var isJoining = false
    @State private var joinErrorMessage: String?
    @State private var showScanner = false

    init(allowsJoin: Bool = true, showsCloseButton _: Bool = false, initialStep: SetupStep? = nil) {
        self.allowsJoin = allowsJoin
        self.initialStep = initialStep
        // showsCloseButton was ignored for full screen wizard, but kept for signature
    }

    var body: some View {
        ZStack {
            // Background
            AnimatedAuroraBackground(currentSlide: currentStep.rawValue)
                .ignoresSafeArea()
                .opacity(0.8) // Dimmed slightly for readability

            if initialized {
                GeometryReader { geometry in
                    ScrollView {
                        ZStack(alignment: .top) {
                            if currentStep == .name {
                                nameStepContent
                                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                            }
                            if currentStep == .household {
                                householdStepContent
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .trailing),
                                            removal: .move(edge: .leading)
                                        )
                                    )
                            }
                            if currentStep == .join {
                                joinStepContent
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .trailing),
                                            removal: .move(edge: .trailing)
                                        )
                                    )
                            }
                        }
                        .frame(minHeight: geometry.size.height)
                        .padding(.top, 40)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            if isJoining || isCreating {
                Color.black.opacity(0.4).ignoresSafeArea()
                JoiningHouseholdLoadingView(isActive: true)
                    .environmentObject(themeStore)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if !initialized {
                if let initialStep {
                    currentStep = initialStep
                    initialized = true
                    if initialStep == .name {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isNameFocused = true }
                    } else if initialStep == .household {
                        householdName = defaultHouseholdName()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isHouseholdNameFocused = true }
                    }
                } else if userSession.needsDisplayNamePrompt {
                    currentStep = .name
                    displayName = userSession.suggestedDisplayNameForPrompt
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isNameFocused = true
                    }
                } else {
                    currentStep = .household
                    householdName = defaultHouseholdName()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isHouseholdNameFocused = true
                    }
                }
                initialized = true
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                QRCodeScannerView(
                    onCodeScanned: { scanned in
                        joinInviteCode = normalizedInviteCodeInput(scanned)
                        showScanner = false
                        if canJoinWithCode, !isJoining {
                            joinHousehold()
                        }
                    },
                    onFailure: { message in
                        joinErrorMessage = message
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
        .alert("Action failed", isPresented: Binding(
            get: { (createErrorMessage ?? joinErrorMessage ?? displayNameErrorMessage) != nil },
            set: { _ in
                createErrorMessage = nil
                joinErrorMessage = nil
                displayNameErrorMessage = nil
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(createErrorMessage ?? joinErrorMessage ?? displayNameErrorMessage ?? "Unknown error")
        }
    }

    // MARK: - Name Step

    private var nameStepContent: some View {
        VStack(spacing: 32) {
            HStack {
                Button("Sign out") {
                    HapticManager.lightTap()
                    userSession.signOut()
                }
                .font(themeStore.font(for: .buttonLabel))
                .foregroundStyle(themeStore.contentSecondaryColor)
                Spacer()
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 10)

            VStack(spacing: 8) {
                Text("What should we call you?")
                    .font(themeStore.font(for: .screenHeader))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                Text("This name is visible to your household members.")
                    .font(themeStore.font(for: .listRowTitle))
                    .foregroundStyle(themeStore.contentSecondaryColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 8) {
                TextField("Nickname", text: $displayName)
                    .font(themeStore.font(for: .screenHeader))
                    .multilineTextAlignment(.center)
                    .focused($isNameFocused)
                    .submitLabel(.continue)
                    .onSubmit {
                        submitName()
                    }

                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal, 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Button {
                submitName()
            } label: {
                Text("Continue")
                    .font(themeStore.font(for: .buttonLabel))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : themeStore.accentTabColor)
                    )
            }
            .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 40)
            .padding(.top, 20)

            Spacer()
        }
        .appAdaptiveWidth(maxWidth: AppChromeMetrics.regularFormMaxWidth, alignment: .top)
    }

    private func submitName() {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        HapticManager.mediumTap()
        do {
            let validated = try DisplayNameValidator.validate(trimmed)
            userSession.applyProfileUpdate(displayName: validated)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                currentStep = .household
                householdName = defaultHouseholdName()
                isHouseholdNameFocused = true
            }
        } catch {
            displayNameErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Household Step

    private var householdStepContent: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Set up your home")
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
                            HapticManager.selection()
                            selectedIconSymbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(selectedIconSymbol == symbol ? .white : themeStore.contentPrimaryColor)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(selectedIconSymbol == symbol ? themeStore.accentTabColor : Color.secondary.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)

            // Input Field
            VStack(spacing: 8) {
                TextField("e.g. Smith Family", text: $householdName)
                    .font(themeStore.font(for: .screenHeader))
                    .multilineTextAlignment(.center)
                    .focused($isHouseholdNameFocused)
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
            .padding(.top, 10)

            // Create Button
            VStack(spacing: 16) {
                Button {
                    createHousehold()
                } label: {
                    Text("Create Household")
                        .font(themeStore.font(for: .buttonLabel))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(
                                    householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color.secondary : themeStore.accentTabColor
                                )
                        )
                }
                .disabled(
                    householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        isCreating ||
                        !userSession.hasActiveSession ||
                        confirmedMembershipDisplayName == nil
                )

                if allowsJoin {
                    // Prominent Join Link
                    Button {
                        HapticManager.mediumTap()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                            currentStep = .join
                        }
                    } label: {
                        Text("Have an invite code? Join Household")
                            .font(themeStore.font(for: .buttonLabel))
                            .foregroundStyle(themeStore.contentPrimaryColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Capsule()
                                    .strokeBorder(themeStore.contentPrimaryColor.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .disabled(!canJoinViaInvite || isCreating || confirmedMembershipDisplayName == nil)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)

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
        .appAdaptiveWidth(maxWidth: AppChromeMetrics.regularFormMaxWidth, alignment: .top)
    }

    private func createHousehold() {
        householdName = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !householdName.isEmpty else { return }
        guard let displayName = confirmedMembershipDisplayName else {
            createErrorMessage = HouseholdError.displayNameRequired.localizedDescription
            return
        }
        guard userSession.hasActiveSession, let userId = userSession.userId else {
            createErrorMessage = "Sign in or continue as guest before creating household."
            return
        }

        HapticManager.success()
        isCreating = true
        isHouseholdNameFocused = false

        _Concurrency.Task {
            do {
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
                onboardingState.completeHouseholdSetup(withHousehold: true)
            } catch {
                createErrorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }

    // MARK: - Join Step

    private var joinStepContent: some View {
        VStack(spacing: 24) {
            HStack {
                Button {
                    HapticManager.lightTap()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        currentStep = .household
                        isHouseholdNameFocused = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .font(themeStore.font(for: .buttonLabel))
                .foregroundStyle(themeStore.contentSecondaryColor)
                Spacer()
            }
            .padding(.horizontal, 32)

            Text("Enter Invite Code")
                .font(themeStore.font(for: .screenHeader))
                .foregroundStyle(themeStore.contentPrimaryColor)
                .multilineTextAlignment(.center)

            TextField("A7B9XQ", text: $joinInviteCode, axis: .vertical)
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
                .onChange(of: joinInviteCode) { _, newValue in
                    joinInviteCode = normalizedInviteCodeInput(newValue)
                }

            Text("Use the 6-character invite code (A-Z, 0-9). Older 8-character codes still work. QR codes fill this field automatically.")
                .font(themeStore.font(for: .bodySmall))
                .foregroundStyle(themeStore.contentSecondaryColor)
                .multilineTextAlignment(.center)

            Text("Shared lists and tasks usually appear in seconds after you join, but sync can take up to 1-2 minutes.")
                .font(themeStore.font(for: .bodySmall))
                .foregroundStyle(themeStore.contentSecondaryColor)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                Button {
                    joinHousehold()
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
                        HapticManager.lightTap()
                        joinInviteCode = UIPasteboard.general.string ?? ""
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .font(themeStore.font(for: .buttonLabel))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isJoining)

                    Button {
                        HapticManager.lightTap()
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
            .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .appAdaptiveWidth(maxWidth: AppChromeMetrics.regularFormMaxWidth, alignment: .top)
    }

    private var canJoinWithCode: Bool {
        InviteInputNormalizer.normalizeInviteCodeToken(joinInviteCode) != nil
    }

    private func normalizedInviteCodeInput(_ raw: String) -> String {
        let uppercased = raw.uppercased()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let filtered = String(uppercased.unicodeScalars.filter { allowed.contains($0) })
        return String(filtered.prefix(InviteInputNormalizer.maximumInviteCodeLength))
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

        HapticManager.success()
        isJoining = true
        joinErrorMessage = nil

        _Concurrency.Task {
            do {
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
                onboardingState.completeHouseholdSetup(withHousehold: true)
            } catch {
                joinErrorMessage = error.localizedDescription
            }
            isJoining = false
        }
    }

    private func preferredJoinCode() -> String? {
        guard let normalizedCode = InviteInputNormalizer.normalizeInviteCodeToken(joinInviteCode) else {
            return nil
        }
        return normalizedCode
    }

    private var canJoinViaInvite: Bool {
        userSession.hasActiveSession && userSession.syncMode == .cloud
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

#Preview {
    CreateHouseholdView()
        .environmentObject(OnboardingState())
        .environmentObject(HouseholdStore())
        .environmentObject(UserSession.shared)
        .environmentObject(ThemeStore())
}
