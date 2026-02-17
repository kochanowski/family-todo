import SwiftUI
import UIKit

/// Overlay view that shows celebration toasts.
struct CelebrationOverlay: View {
    @ObservedObject var manager: CelebrationManager

    @State private var confettiParticles: [ConfettiParticle] = []
    @State private var confettiProgress: CGFloat = 0

    var body: some View {
        ZStack {
            confettiLayer

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
        .onChange(of: manager.activeCelebration) { _, newValue in
            guard let celebration = newValue, celebration.style == .milestone else { return }
            spawnConfetti()
        }
    }

    private var confettiLayer: some View {
        ForEach(confettiParticles) { particle in
            Text(particle.emoji)
                .font(.system(size: particle.size))
                .rotationEffect(.degrees(particle.rotation * Double(confettiProgress)))
                .opacity(Double(max(0, 1 - confettiProgress)))
                .position(
                    x: particle.startX + (particle.endX - particle.startX) * confettiProgress,
                    y: particle.startY + (particle.endY - particle.startY) * confettiProgress
                )
        }
    }

    private func spawnConfetti() {
        let emojis = ["🎉", "✨", "🌟", "💫", "🎊", "⭐️", "🔥"]
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        confettiParticles = (0 ..< 24).map { index in
            let startX = CGFloat.random(in: 16 ... (screenWidth - 16))
            return ConfettiParticle(
                emoji: emojis[index % emojis.count],
                size: CGFloat.random(in: 16 ... 28),
                startX: startX,
                endX: startX + CGFloat.random(in: -70 ... 70),
                startY: -24,
                endY: CGFloat.random(in: screenHeight * 0.28 ... screenHeight * 0.72),
                rotation: Double.random(in: -140 ... 140)
            )
        }

        confettiProgress = 0
        withAnimation(.easeOut(duration: 1.6)) {
            confettiProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            confettiParticles = []
            confettiProgress = 0
        }
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let emoji: String
    let size: CGFloat
    let startX: CGFloat
    let endX: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let rotation: Double
}
