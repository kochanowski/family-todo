import SwiftUI

struct SyncSelectionView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Background
            Color(colorScheme == .dark ? .black : .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Header
                VStack(spacing: 8) {
                    Text("Choose how to save.")
                        .font(.system(size: 28, weight: .bold))

                    Text("Select where your data lives.")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }

                Spacer()
                    .frame(height: 20)

                // Options
                VStack(spacing: 16) {
                    // Primary Option - iCloud
                    Button {
                        onboardingState.selectSyncMethod(.iCloud)
                    } label: {
                        HStack(spacing: 16) {
                            // Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                                    .frame(width: 48, height: 48)

                                Image(systemName: "icloud.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                            }

                            // Text
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Sync with iCloud")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.primary)

                                    // Recommended Badge
                                    Text("Recommended")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.blue))
                                }

                                Text("Seamlessly share data across devices.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // Secondary Option - Guest
                    Button {
                        onboardingState.selectSyncMethod(.local)
                    } label: {
                        HStack(spacing: 16) {
                            // Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 48, height: 48)

                                Image(systemName: "person.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.secondary)
                            }

                            // Text
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Continue as Guest")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text("Data is saved only on this device.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(cardBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.97)
    }
}

#Preview {
    SyncSelectionView()
        .environmentObject(OnboardingState())
}
