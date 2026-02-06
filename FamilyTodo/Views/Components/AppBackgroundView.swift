import SwiftUI

/// Subtle app-wide background that gives glass blur materials content to sample.
///
/// Uses layered gradients to avoid a flat backdrop, so frosted blur remains
/// visible on low-content screens in both light and dark appearances.
struct AppBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: baseGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: topGlowColors,
                center: .topLeading,
                startRadius: 40,
                endRadius: 520
            )
            .blendMode(.plusLighter)

            RadialGradient(
                colors: bottomGlowColors,
                center: .bottomTrailing,
                startRadius: 80,
                endRadius: 620
            )
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }

    private var baseGradientColors: [Color] {
        if colorScheme == .dark {
            [
                Color(red: 0.03, green: 0.04, blue: 0.07),
                Color(red: 0.04, green: 0.05, blue: 0.09),
            ]
        } else {
            [
                Color(red: 0.95, green: 0.96, blue: 0.98),
                Color(red: 0.92, green: 0.94, blue: 0.97),
            ]
        }
    }

    private var topGlowColors: [Color] {
        if colorScheme == .dark {
            [
                Color(red: 0.16, green: 0.24, blue: 0.45).opacity(0.22),
                .clear,
            ]
        } else {
            [
                Color(red: 1.0, green: 1.0, blue: 1.0).opacity(0.28),
                .clear,
            ]
        }
    }

    private var bottomGlowColors: [Color] {
        if colorScheme == .dark {
            [
                Color(red: 0.22, green: 0.20, blue: 0.50).opacity(0.24),
                .clear,
            ]
        } else {
            [
                Color(red: 0.78, green: 0.86, blue: 1.0).opacity(0.18),
                .clear,
            ]
        }
    }
}
