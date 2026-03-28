import SwiftUI
import UIKit

struct GuidedEmptyStateView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var showCreateFlow = false
    @State private var showJoinSheet = false
    @State private var joinInviteCode = ""
    @State private var isJoining = false
    @State private var joinErrorMessage: String?

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
                    .font(themeStore.font(for: .screenHeader))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                Text("To share shopping lists and tasks, you need to create or join a household.")
                    .font(themeStore.font(for: .listRowTitle))
                    .foregroundStyle(themeStore.contentSecondaryColor)
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
                        .font(themeStore.font(for: .buttonLabel))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                        )
                }
                .disabled(showJoinSheet || confirmedMembershipDisplayName == nil)

                // Secondary - Join
                Button {
                    showCreateFlow = false
                    showJoinSheet = true
                } label: {
                    Text("Join Existing")
                        .font(themeStore.font(for: .buttonLabel))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
                .disabled(showCreateFlow || !canJoinViaInvite || confirmedMembershipDisplayName == nil)
            }
            .padding(.horizontal, 40)

            if !canJoinViaInvite {
                Text("Joining requires Apple/iCloud sign in.")
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(themeStore.contentSecondaryColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeStore.canvasColor)
        .fullScreenCover(isPresented: $showCreateFlow) {
            CreateHouseholdView(allowsJoin: false, showsCloseButton: true)
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
            .presentationDetents([.medium])
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
        guard let displayName = confirmedMembershipDisplayName else {
            joinErrorMessage = HouseholdError.displayNameRequired.localizedDescription
            return
        }
        guard let inviteCode = preferredJoinCode() else { return }
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

    private func performJoinHousehold(
        inviteCode: String,
        userId: String,
        displayName: String
    ) async throws {
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
        if userSession.syncMode == .cloud {
            await NotificationService.shared.requestCollaborationAuthorizationIfNeeded()
        }
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
}

#Preview {
    GuidedEmptyStateView()
        .environmentObject(OnboardingState())
        .environmentObject(HouseholdStore())
        .environmentObject(UserSession.shared)
        .environmentObject(ThemeStore())
}
