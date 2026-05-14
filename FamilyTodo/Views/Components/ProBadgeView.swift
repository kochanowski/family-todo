import SwiftUI

struct ProBadgeView: View {
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
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "FFF2A8"),
                        Color(hex: "F6B84B"),
                        Color(hex: "D98B19"),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.dimension, height: size.dimension)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "FFD66B").opacity(0.26),
                                        Color(hex: "8B5CF6").opacity(0.12),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.45), lineWidth: 0.8)
            }
            .shadow(color: Color(hex: "F6B84B").opacity(0.35), radius: 7, y: 3)
            .accessibilityLabel("Dwello Pro")
    }
}
