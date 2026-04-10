import SwiftUI

// MARK: - Aurora Color Palettes

enum AuroraPalette {
    case calmSync // Slide 1 - Blues
    case freshAction // Slide 2 - Greens
    case warmDreams // Slide 3 - Oranges/Roses
    case dreamerPurple // Slide 4 - Violets/Purples
    case togetherCyan // Slide 5 - Cyan/Teal

    func colors(for colorScheme: ColorScheme) -> [Color] {
        switch self {
        case .calmSync:
            if colorScheme == .dark {
                [
                    Color(hex: "312E81"), // Indigo-900
                    Color(hex: "1E3A8A"), // Blue-900
                    Color(hex: "0C4A6E"), // Sky-800
                ]
            } else {
                [
                    Color(hex: "A5B4FC"), // Indigo-300
                    Color(hex: "93C5FD"), // Blue-300
                    Color(hex: "BAE6FD"), // Sky-200
                ]
            }

        case .freshAction:
            if colorScheme == .dark {
                [
                    Color(hex: "064E3B"), // Emerald-900
                    Color(hex: "134E4A"), // Teal-900
                    Color(hex: "14532D"), // Green-900
                ]
            } else {
                [
                    Color(hex: "6EE7B7"), // Emerald-300
                    Color(hex: "5EEAD4"), // Teal-300
                    Color(hex: "DCFCE7"), // Green-100
                ]
            }

        case .warmDreams:
            if colorScheme == .dark {
                [
                    Color(hex: "7C2D12"), // Orange-900
                    Color(hex: "881337"), // Rose-900
                    Color(hex: "78350F"), // Amber-900
                ]
            } else {
                [
                    Color(hex: "FDBA74"), // Orange-300
                    Color(hex: "FDA4AF"), // Rose-300
                    Color(hex: "FDE68A"), // Amber-200
                ]
            }

        case .dreamerPurple:
            if colorScheme == .dark {
                [
                    Color(hex: "4C1D95"), // Violet-900
                    Color(hex: "581C87"), // Purple-900
                    Color(hex: "3B0764"), // Fuchsia-950
                ]
            } else {
                [
                    Color(hex: "C4B5FD"), // Violet-300
                    Color(hex: "DDD6FE"), // Violet-200
                    Color(hex: "E9D5FF"), // Purple-200
                ]
            }

        case .togetherCyan:
            if colorScheme == .dark {
                [
                    Color(hex: "164E63"), // Cyan-900
                    Color(hex: "134E4A"), // Teal-900
                    Color(hex: "0E7490"), // Cyan-700
                ]
            } else {
                [
                    Color(hex: "67E8F9"), // Cyan-300
                    Color(hex: "A5F3FC"), // Cyan-200
                    Color(hex: "99F6E4"), // Teal-200
                ]
            }
        }
    }
}

// MARK: - Aurora Background View

struct AuroraBackground: View {
    let palette: AuroraPalette
    @Environment(\.colorScheme) private var colorScheme

    @State private var animate = false

    private var colors: [Color] {
        palette.colors(for: colorScheme)
    }

    var body: some View {
        ZStack {
            // Background base
            Color(colorScheme == .dark ? .black : .white)
                .ignoresSafeArea()

            // Animated orbs
            GeometryReader { geometry in
                ZStack {
                    // Orb 1 - Top Left
                    Circle()
                        .fill(colors[0])
                        .frame(width: geometry.size.width * 0.8)
                        .blur(radius: 80)
                        .offset(
                            x: animate ? -geometry.size.width * 0.2 : -geometry.size.width * 0.3,
                            y: animate ? -geometry.size.height * 0.15 : -geometry.size.height * 0.25
                        )
                        .scaleEffect(animate ? 1.1 : 0.9)

                    // Orb 2 - Bottom Right
                    Circle()
                        .fill(colors[1])
                        .frame(width: geometry.size.width * 0.7)
                        .blur(radius: 80)
                        .offset(
                            x: animate ? geometry.size.width * 0.25 : geometry.size.width * 0.15,
                            y: animate ? geometry.size.height * 0.2 : geometry.size.height * 0.3
                        )
                        .scaleEffect(animate ? 0.95 : 1.05)

                    // Orb 3 - Center (lower opacity)
                    Circle()
                        .fill(colors[2].opacity(0.6))
                        .frame(width: geometry.size.width * 0.5)
                        .blur(radius: 100)
                        .offset(
                            x: animate ? 20 : -20,
                            y: animate ? 40 : -40
                        )
                        .scaleEffect(animate ? 1.0 : 1.15)
                }
            }

            // Overlay to unify colors
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.3)
                .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 8)
                    .repeatForever(autoreverses: true)
            ) {
                animate = true
            }
        }
    }
}

// MARK: - Animated Aurora Background (Cross-dissolve between palettes)

struct AnimatedAuroraBackground: View {
    let currentSlide: Int
    @Environment(\.colorScheme) private var colorScheme

    private var palette: AuroraPalette {
        switch currentSlide {
        case 0: .calmSync
        case 1: .freshAction
        case 2: .warmDreams
        case 3: .dreamerPurple
        default: .togetherCyan
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground(palette: .calmSync)
                .opacity(currentSlide == 0 ? 1 : 0)

            AuroraBackground(palette: .freshAction)
                .opacity(currentSlide == 1 ? 1 : 0)

            AuroraBackground(palette: .warmDreams)
                .opacity(currentSlide == 2 ? 1 : 0)

            AuroraBackground(palette: .dreamerPurple)
                .opacity(currentSlide == 3 ? 1 : 0)

            AuroraBackground(palette: .togetherCyan)
                .opacity(currentSlide == 4 ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.5), value: currentSlide)
    }
}

#Preview("Calm Sync") {
    AuroraBackground(palette: .calmSync)
}

#Preview("Fresh Action") {
    AuroraBackground(palette: .freshAction)
}

#Preview("Warm Dreams") {
    AuroraBackground(palette: .warmDreams)
}

#Preview("Dreamer Purple") {
    AuroraBackground(palette: .dreamerPurple)
}

#Preview("Together Cyan") {
    AuroraBackground(palette: .togetherCyan)
}
