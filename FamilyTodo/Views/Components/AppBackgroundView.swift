import SwiftUI

/// Subtle app-wide background that gives glass blur materials content to sample.
struct AppBackgroundView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            stops: gradientStops,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var gradientStops: [Gradient.Stop] {
        switch themeStore.preset {
        case .retroDark:
            [
                .init(color: Color(hex: "050510"), location: 0),
                .init(color: Color(hex: "0D0D22"), location: 0.74),
                .init(color: Color(hex: "1A0F2F"), location: 1.0),
            ]
        case .retroLight:
            [
                .init(color: Color(hex: "FFF6E5"), location: 0),
                .init(color: Color(hex: "ECE1C6"), location: 0.76),
                .init(color: Color(hex: "D8CFB9"), location: 1.0),
            ]
        case .paper:
            [
                .init(color: Color(hex: "F7F0E3"), location: 0),
                .init(color: Color(hex: "F2E8D6"), location: 0.78),
                .init(color: Color(hex: "E9D9BF"), location: 1.0),
            ]
        case .system:
            if colorScheme == .dark {
                [
                    .init(color: Color(hex: "000000"), location: 0),
                    .init(color: Color(hex: "000000"), location: 1.0),
                ]
            } else {
                [
                    .init(color: Color(hex: "FFFFFF"), location: 0),
                    .init(color: Color(hex: "FFFFFF"), location: 1.0),
                ]
            }
        }
    }
}
