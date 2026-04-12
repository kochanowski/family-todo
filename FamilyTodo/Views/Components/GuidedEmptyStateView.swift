import SwiftUI
import UIKit

struct GuidedEmptyStateView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var showCreateFlow = false
    @State private var activeSetupStep: CreateHouseholdView.SetupStep = .household

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
                    activeSetupStep = .household
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
                .disabled(confirmedMembershipDisplayName == nil)

                // Secondary - Join
                Button {
                    activeSetupStep = .join
                    showCreateFlow = true
                } label: {
                    Text("Join Existing")
                        .font(themeStore.font(for: .buttonLabel))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
                .disabled(!canJoinViaInvite || confirmedMembershipDisplayName == nil)
            }
            .padding(.horizontal, 40)

            if canJoinViaInvite {
                Text("Ask your household owner for an invite code or QR.")
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(themeStore.contentSecondaryColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
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
            CreateHouseholdView(allowsJoin: true, showsCloseButton: true, initialStep: activeSetupStep)
        }
        .onChange(of: userSession.currentHouseholdID) { _, newValue in
            guard newValue != nil else { return }
            showCreateFlow = false
        }
    }

    private var canJoinViaInvite: Bool {
        userSession.hasActiveSession && userSession.syncMode == .cloud
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
