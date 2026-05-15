import SwiftUI

struct PremiumUpsellSheet: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var premiumSubscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    let context: UpsellContext

    var body: some View {
        ZStack {
            background

            VStack(spacing: 20) {
                heroIcon

                VStack(spacing: 8) {
                    Text(context.eyebrow)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(primaryTitleGradient)

                    Text(context.title)
                        .font(themeStore.font(for: .profileName))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                        .multilineTextAlignment(.center)

                    Text(context.message)
                        .font(themeStore.font(for: .bodyStrong))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                }

                VStack(spacing: 10) {
                    Button {
                        premiumSubscriptionManager.presentPaywallFromUpsell()
                    } label: {
                        Text(context.primaryCTATitle)
                            .font(themeStore.font(for: .buttonLabel))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .background {
                        Capsule()
                            .fill(primaryButtonGradient)
                            .shadow(color: Color.indigo.opacity(0.30), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismiss()
                    } label: {
                        Text("Not Now")
                            .font(themeStore.font(for: .buttonLabel))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.top, 54)
            .padding(.bottom, 24)
        }
        .presentationBackground(.clear)
    }

    private var background: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)

            RadialGradient(
                colors: [
                    Color.indigo.opacity(0.30),
                    Color.blue.opacity(0.12),
                    Color.clear,
                ],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 260
            )
            .blur(radius: 18)

            RadialGradient(
                colors: [
                    Color(hex: "F6B84B").opacity(0.22),
                    Color.clear,
                ],
                center: .bottomLeading,
                startRadius: 8,
                endRadius: 240
            )
            .blur(radius: 20)
        }
        .ignoresSafeArea()
    }

    private var heroIcon: some View {
        Image(systemName: context.iconName)
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(primaryTitleGradient)
            .frame(width: 78, height: 78)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.28),
                                        Color.indigo.opacity(0.16),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            }
            .shadow(color: Color.indigo.opacity(0.25), radius: 18, y: 8)
            .accessibilityHidden(true)
    }

    private var primaryTitleGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "FDE68A"),
                Color(hex: "A78BFA"),
                Color(hex: "60A5FA"),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.blue,
                Color.indigo,
                Color.purple,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
