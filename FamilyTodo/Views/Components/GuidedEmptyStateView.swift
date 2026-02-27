import SwiftUI
import UIKit

struct GuidedEmptyStateView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession

    @Environment(\.colorScheme) private var colorScheme
    @State private var showCreateFlow = false
    @State private var showJoinSheet = false
    @State private var joinInput = ""
    @State private var joinInviteCode = ""
    @State private var isJoining = false
    @State private var joinErrorMessage: String?
    @State private var pendingCustomJoinInviteCode: String?
    @State private var showCustomJoinConfirmation = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Illustration
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)

                Image(systemName: "house.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
            }

            // Text
            VStack(spacing: 8) {
                Text("No Household Active")
                    .font(.system(size: 22, weight: .bold))

                Text("To share shopping lists and tasks, you need to create or join a household.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 20)

            // Buttons
            VStack(spacing: 12) {
                // Primary - Create
                Button {
                    showJoinSheet = false
                    showCreateFlow = true
                } label: {
                    Text("Create Household")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                        )
                }
                .disabled(showJoinSheet)

                // Secondary - Join
                Button {
                    showCreateFlow = false
                    showJoinSheet = true
                } label: {
                    Text("Join Existing")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .disabled(showCreateFlow || !canJoinViaInvite)
            }
            .padding(.horizontal, 40)

            if !canJoinViaInvite {
                Text("Joining requires Apple/iCloud sign in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(colorScheme == .dark ? .black : .systemBackground))
        .fullScreenCover(isPresented: $showCreateFlow) {
            CreateHouseholdView(allowsJoin: false, showsCloseButton: true)
        }
        .sheet(isPresented: $showJoinSheet) {
            HouseholdJoinSheet(
                inviteCodeToken: $joinInviteCode,
                inviteLink: $joinInput,
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
        .onChange(of: userSession.currentHouseholdID) { _, newValue in
            guard newValue != nil else { return }
            showCreateFlow = false
            showJoinSheet = false
            pendingCustomJoinInviteCode = nil
        }
    }

    private var canJoinViaInvite: Bool {
        userSession.hasActiveSession && userSession.syncMode == .cloud
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
        let rawInviteInput = preferredJoinInput()
        guard !rawInviteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isJoining else { return }

        isJoining = true
        joinErrorMessage = nil

        _Concurrency.Task {
            do {
                let normalizedInvite = try InviteInputNormalizer.normalizeInput(rawInviteInput)
                if normalizedInvite.requiresConfirmation {
                    pendingCustomJoinInviteCode = normalizedInvite.inviteCode
                    showCustomJoinConfirmation = true
                    isJoining = false
                    return
                }

                try await performJoinHousehold(inviteCode: normalizedInvite.inviteCode, userId: userId)
            } catch {
                joinErrorMessage = error.localizedDescription
            }

            isJoining = false
        }
    }

    private func confirmCustomJoin() {
        guard canJoinViaInvite else {
            joinErrorMessage = "Joining via invite requires Apple/iCloud sign in."
            return
        }
        guard let userId = userSession.userId else {
            joinErrorMessage = "Could not determine your account identity."
            return
        }
        guard let inviteCode = pendingCustomJoinInviteCode else { return }

        pendingCustomJoinInviteCode = nil
        isJoining = true

        _Concurrency.Task {
            do {
                try await performJoinHousehold(inviteCode: inviteCode, userId: userId)
            } catch {
                joinErrorMessage = error.localizedDescription
            }
            isJoining = false
        }
    }

    private func performJoinHousehold(inviteCode: String, userId: String) async throws {
        householdStore.setSyncMode(userSession.syncMode)
        try await householdStore.joinHousehold(
            withInviteInput: inviteCode,
            userId: userId,
            displayName: fallbackDisplayNameForMembership()
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
}

#Preview {
    GuidedEmptyStateView()
        .environmentObject(OnboardingState())
        .environmentObject(HouseholdStore())
        .environmentObject(UserSession.shared)
}
