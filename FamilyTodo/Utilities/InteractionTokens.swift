import SwiftUI

// MARK: - Animation Tokens

/// Centralized animation constants for consistent UX polish
enum WowAnimation {
    /// Standard duration for micro-interactions (200ms)
    static let duration: Double = 0.2

    /// Quick duration for immediate feedback (150ms)
    static let quick: Double = 0.15

    /// Standard easeOut animation
    static let easeOut = Animation.easeOut(duration: duration)

    /// Subtle spring animation for natural feel
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Quick spring for immediate feedback
    static let quickSpring = Animation.spring(response: 0.25, dampingFraction: 0.8)

    /// Staggered animation delay for list items
    static func staggerDelay(index: Int) -> Double {
        Double(index) * 0.05
    }
}

// MARK: - View Modifiers for Common Animations

extension View {
    /// Apply standard row insertion animation
    func rowInsertAnimation() -> some View {
        transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)).animation(WowAnimation.spring),
            removal: .opacity.combined(with: .scale(scale: 0.98)).animation(WowAnimation.easeOut)
        ))
    }

    /// Apply move-to-restock animation (shrink + fade + slide)
    func restockRemovalAnimation() -> some View {
        transition(.asymmetric(
            insertion: .opacity,
            removal: .opacity
                .combined(with: .scale(scale: 0.98))
                .combined(with: .move(edge: .bottom))
                .animation(WowAnimation.easeOut)
        ))
    }

    /// Pulse animation for icons (scale 1.0 -> 1.08 -> 1.0) that retriggers on every token change.
    func pulseAnimation(trigger: Int) -> some View {
        modifier(PulseAnimationModifier(trigger: trigger))
    }

    /// Crossfade transition for appearance changes
    func crossfadeTransition() -> some View {
        transition(.opacity.animation(.easeInOut(duration: WowAnimation.duration)))
    }
}

// MARK: - Reusable Animation States

/// Observable state for restock icon pulse
@MainActor
final class RestockPulseState: ObservableObject {
    @Published private(set) var pulseToken = 0

    func pulse() {
        pulseToken += 1
    }
}

private struct PulseAnimationModifier: ViewModifier {
    let trigger: Int

    @State private var isPulsing = false
    @State private var pulseGeneration = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.08 : 1.0)
            .onChange(of: trigger) { _, _ in
                pulseGeneration += 1
                let currentGeneration = pulseGeneration
                isPulsing = true

                DispatchQueue.main.asyncAfter(deadline: .now() + WowAnimation.quick) {
                    guard pulseGeneration == currentGeneration else { return }
                    isPulsing = false
                }
            }
            .animation(WowAnimation.quickSpring, value: isPulsing)
    }
}
