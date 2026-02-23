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
        case .retro:
            [
                .init(color: Color(hex: "050510"), location: 0),
                .init(color: Color(hex: "0D0D22"), location: 0.74),
                .init(color: Color(hex: "1A0F2F"), location: 1.0),
            ]
        case .paper:
            [
                .init(color: Color(hex: "F7F0E3"), location: 0),
                .init(color: Color(hex: "F2E8D6"), location: 0.78),
                .init(color: Color(hex: "E9D9BF"), location: 1.0),
            ]
        case .system:
            if themeStore.unifiedTheme == .dark2 {
                [
                    .init(color: Color(hex: "000000"), location: 0),
                    .init(color: Color(hex: "000000"), location: 1.0),
                ]
            } else if themeStore.unifiedTheme == .light2 {
                [
                    .init(color: Color(hex: "FFFFFF"), location: 0),
                    .init(color: Color(hex: "FFFFFF"), location: 1.0),
                ]
            } else if colorScheme == .dark {
                [
                    .init(color: Color(hex: "0E0C0A"), location: 0),
                    .init(color: Color(hex: "15110F"), location: 0.74),
                    .init(color: Color(hex: "241B14"), location: 1.0),
                ]
            } else {
                [
                    .init(color: Color(hex: "FAFAF9"), location: 0),
                    .init(color: Color(hex: "F5F1EB"), location: 0.78),
                    .init(color: Color(hex: "EDE4D9"), location: 1.0),
                ]
            }
        }
    }
}
