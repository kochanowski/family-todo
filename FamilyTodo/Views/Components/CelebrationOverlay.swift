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
            confettiShapeView(for: particle)
                .rotationEffect(.degrees(particle.rotation * Double(confettiProgress)))
                .opacity(Double(max(0, 1 - confettiProgress)))
                .position(
                    x: particle.startX + (particle.endX - particle.startX) * confettiProgress,
                    y: particle.startY + (particle.endY - particle.startY) * confettiProgress
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
        Color(hex: "FF6B6B"), // coral red
        Color(hex: "4ECDC4"), // teal
        Color(hex: "FFE66D"), // sunny yellow
        Color(hex: "A78BFA"), // lavender
        Color(hex: "F093FB"), // pink
        Color(hex: "4DD599"), // mint green
        Color(hex: "74B9FF"), // sky blue
        Color(hex: "FD79A8"), // rose
    ]

    private var resolvedConfettiColors: [Color] {
        if let accentPalette, !accentPalette.isEmpty {
            return accentPalette
        }
        return Self.defaultConfettiColors
    }

    private func spawnConfetti() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let colors = resolvedConfettiColors

        confettiParticles = (0 ..< 30).map { _ in
            let startX = CGFloat.random(in: 16 ... (screenWidth - 16))
            return ConfettiParticle(
                shape: ConfettiParticle.ConfettiShape.allCases.randomElement() ?? .rectangle,
                color: colors.randomElement() ?? .blue,
                size: CGFloat.random(in: 6 ... 12),
                startX: startX,
                endX: startX + CGFloat.random(in: -80 ... 80),
                startY: -20,
                endY: CGFloat.random(in: screenHeight * 0.25 ... screenHeight * 0.75),
                rotation: Double.random(in: -360 ... 360)
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

// MARK: - Confetti Shapes

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let shape: ConfettiShape
    let color: Color
    let size: CGFloat
    let startX: CGFloat
    let endX: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let rotation: Double

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
