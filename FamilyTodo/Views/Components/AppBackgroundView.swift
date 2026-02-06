import SwiftUI

/// Subtle app-wide background that gives glass blur materials content to sample.
///
/// Uses the app's standard base colour with a very subtle gradient shift near the
/// bottom of the screen. This ensures the floating tab bar's frosted-glass effect
/// remains perceptible even on screens with little scrollable content.
struct AppBackgroundView: View {
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
        if colorScheme == .dark {
            [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.6),
                .init(color: Color(red: 0.12, green: 0.08, blue: 0.20), location: 1.0),
            ]
        } else {
            [
                .init(color: Color(hex: "F9F9F9"), location: 0),
                .init(color: Color(hex: "F9F9F9"), location: 1.0),
            ]
        }
    }
}
