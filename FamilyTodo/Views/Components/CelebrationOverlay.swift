import SwiftUI
import UIKit

/// Overlay view that shows celebration toasts and geometric confetti.
struct CelebrationOverlay: View {
    @ObservedObject var manager: CelebrationManager
    let messageFont: Font
    let accentPalette: [Color]?

    @State private var confettiParticles: [ConfettiParticle] = []
    @State private var confettiProgress: CGFloat = 0

    init(
        manager: CelebrationManager,
        messageFont: Font = .system(size: 15, weight: .semibold),
        accentPalette: [Color]? = nil
    ) {
        self.manager = manager
        self.messageFont = messageFont
        self.accentPalette = accentPalette
    }

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
                            .font(messageFont)
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

    // MARK: - Confetti Layer

    private var confettiLayer: some View {
        ForEach(confettiParticles) { particle in
            let time = confettiProgress * particle.flightDuration
            confettiShapeView(for: particle)
                .rotationEffect(
                    .degrees(particle.rotationStart + particle.rotationVelocity * Double(time))
                )
                .opacity(Double(max(0, 1 - confettiProgress * 1.1)))
                .position(
                    x: particle.originX + particle.velocityX * time,
                    y: particle.originY - particle.velocityY * time + 0.5 * particle.gravity * time * time
                )
        }
    }

    @ViewBuilder
    private func confettiShapeView(for particle: ConfettiParticle) -> some View {
        switch particle.shape {
        case .rectangle:
            Rectangle()
                .fill(particle.color)
                .frame(width: particle.size, height: particle.size * 0.6)
        case .circle:
            Circle()
                .fill(particle.color)
                .frame(width: particle.size, height: particle.size)
        case .triangle:
            TriangleShape()
                .fill(particle.color)
                .frame(width: particle.size, height: particle.size)
        }
    }

    private static let defaultConfettiColors: [Color] = [
        Color(hex: "FF6B6B"),
        Color(hex: "4ECDC4"),
        Color(hex: "FFE66D"),
        Color(hex: "A78BFA"),
        Color(hex: "F093FB"),
        Color(hex: "4DD599"),
        Color(hex: "74B9FF"),
        Color(hex: "FD79A8"),
        Color(hex: "00C2FF"),
        Color(hex: "C4F000"),
        Color(hex: "FF9F1C"),
        Color(hex: "9B5DE5"),
        Color(hex: "00F5D4"),
        Color(hex: "F15BB5"),
        Color(hex: "FFC300"),
        Color(hex: "3A86FF"),
        Color(hex: "FB5607"),
        Color(hex: "8338EC"),
    ]

    private var resolvedConfettiColors: [Color] {
        if let accentPalette, !accentPalette.isEmpty {
            return accentPalette + Self.defaultConfettiColors
        }
        return Self.defaultConfettiColors
    }

    private func spawnConfetti() {
        let screenMidX = UIScreen.main.bounds.width / 2
        let screenHeight = UIScreen.main.bounds.height
        let colors = resolvedConfettiColors

        confettiParticles = (0 ..< 90).map { _ in
            let emitterJitter = CGFloat.random(in: -10 ... 10)
            let launchAngleDegrees = CGFloat.random(in: 70 ... 110)
            let launchAngle = launchAngleDegrees * .pi / 180
            let launchSpeed = CGFloat.random(in: 420 ... 760)
            let velocityX = cos(launchAngle) * launchSpeed
            let velocityY = sin(launchAngle) * launchSpeed

            return ConfettiParticle(
                shape: ConfettiParticle.ConfettiShape.allCases.randomElement() ?? .rectangle,
                color: colors.randomElement() ?? .blue,
                size: CGFloat.random(in: 6 ... 13),
                originX: screenMidX + emitterJitter,
                originY: screenHeight + CGFloat.random(in: 6 ... 30),
                velocityX: velocityX,
                velocityY: velocityY,
                gravity: CGFloat.random(in: 620 ... 860),
                rotationStart: Double.random(in: 0 ... 360),
                rotationVelocity: Double.random(in: -900 ... 900),
                flightDuration: CGFloat.random(in: 1.4 ... 2.0)
            )
        }

        confettiProgress = 0
        withAnimation(.easeOut(duration: 1.9)) {
            confettiProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            confettiParticles = []
            confettiProgress = 0
        }
    }
}

// MARK: - Confetti Shapes

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let shape: ConfettiShape
    let color: Color
    let size: CGFloat
    let originX: CGFloat
    let originY: CGFloat
    let velocityX: CGFloat
    let velocityY: CGFloat
    let gravity: CGFloat
    let rotationStart: Double
    let rotationVelocity: Double
    let flightDuration: CGFloat

    enum ConfettiShape: CaseIterable {
        case rectangle, circle, triangle
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
