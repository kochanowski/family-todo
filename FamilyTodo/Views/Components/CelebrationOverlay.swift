import SwiftUI

/// Overlay view that shows celebration toasts.
struct CelebrationOverlay: View {
    @ObservedObject var manager: CelebrationManager

    var body: some View {
        ZStack {
            if let celebration = manager.activeCelebration {
                VStack {
                    Spacer()

                    HStack(spacing: 10) {
                        Text(celebration.emoji)
                            .font(.system(size: 24))

                        Text(celebration.message)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))

                    Spacer().frame(height: 100) // Keep above tab bar area
                }
                .animation(WowAnimation.spring, value: manager.activeCelebration)
            }
        }
        .allowsHitTesting(false)
    }
}
