import SwiftUI

struct ProBadgeView: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Size {
        case compact
        case inline

        var dimension: CGFloat {
            switch self {
            case .compact:
                22
            case .inline:
                26
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .compact:
                10
            case .inline:
                12
            }
        }
    }

    let size: Size

    init(size: Size = .compact) {
        self.size = size
    }

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size.iconSize, weight: .bold))
            .foregroundStyle(iconForegroundStyle)
            .frame(width: size.dimension + 8, height: size.dimension)
            .background {
                badgeBackground
            }
            .overlay {
                Capsule()
                    .stroke(badgeStrokeColor, lineWidth: 0.9)
            }
            .shadow(color: badgeShadowColor, radius: colorScheme == .dark ? 8 : 6, x: 0, y: 2)
            .accessibilityLabel("Dwello Pro")
    }

    @ViewBuilder
    private var badgeBackground: some View {
        if colorScheme == .dark {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "FFF2A8").opacity(0.34),
                                    Color(hex: "F6B84B").opacity(0.18),
                                    Color(hex: "8B5CF6").opacity(0.10),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        } else {
            Capsule()
                .fill(Color.black.opacity(0.84))
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    Color.black.opacity(0.14),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
    }

    private var iconForegroundStyle: some ShapeStyle {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color(hex: "FFF7C7"),
                    Color(hex: "F6B84B"),
                    Color(hex: "D97706"),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color.white,
                    Color(hex: "FDE68A"),
                    Color(hex: "F59E0B"),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var badgeStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.08)
    }

    private var badgeShadowColor: Color {
        colorScheme == .dark ? Color(hex: "F6B84B").opacity(0.34) : Color.black.opacity(0.28)
    }
}
