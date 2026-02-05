import SwiftData
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var userSession: UserSession

    var body: some View {
        Group {
            if userSession.hasActiveSession {
                MainAppView()
            } else {
                SignInView()
            }
        }
    }
}

/// Main app view with custom floating tab bar overlaid at the bottom.
///
/// Uses overlay (not safeAreaInset) so scrolling content extends behind the
/// tab bar, giving the glass material real content to blur.
struct MainAppView: View {
    @State private var activeTab: Tab = .shopping
    @Environment(\.colorScheme) private var colorScheme

    /// Animation state for tab transitions
    @Namespace private var animation

    var body: some View {
        ZStack {
            // Background
            backgroundColor
                .ignoresSafeArea()

            // Tab content with animation
            tabContent
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.99)).combined(with: .blur),
                        removal: .opacity.combined(with: .scale(scale: 0.99)).combined(with: .blur)
                    )
                )
                .animation(.easeInOut(duration: 0.3), value: activeTab)
                .id(activeTab)
        }
        .overlay(alignment: .bottom) {
            // Glass tab bar on top of content so material blur samples
            // the scrolling items underneath.
            FloatingTabBar(activeTab: $activeTab)
                .ignoresSafeArea(.keyboard)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .shopping:
            ShoppingListView()
        case .tasks:
            TasksView()
        case .backlog:
            BacklogView()
        case .more:
            MoreView()
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : Color(hex: "F9F9F9")
    }
}

// MARK: - Blur Transition Extension

extension AnyTransition {
    static var blur: AnyTransition {
        .modifier(
            active: BlurModifier(radius: 2),
            identity: BlurModifier(radius: 0)
        )
    }
}

struct BlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let alpha: UInt64
        let red: UInt64
        let green: UInt64
        let blue: UInt64
        switch hex.count {
        case 3:
            (alpha, red, green, blue) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (alpha, red, green, blue) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (alpha, red, green, blue) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (alpha, red, green, blue) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

#Preview {
    MainAppView()
}
