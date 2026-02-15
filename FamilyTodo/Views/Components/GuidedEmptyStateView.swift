import SwiftUI

struct GuidedEmptyStateView: View {
    @EnvironmentObject private var onboardingState: OnboardingState

    @Environment(\.colorScheme) private var colorScheme

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
                    // Open household creation modal
                    onboardingState.openHouseholdSetup()
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

                // Secondary - Join
                Button {
                    // For now, same action
                    onboardingState.openHouseholdSetup()
                } label: {
                    Text("Join Existing")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(colorScheme == .dark ? .black : .systemBackground))
    }
}

#Preview {
    GuidedEmptyStateView()
        .environmentObject(OnboardingState())
}
