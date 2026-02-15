import SwiftUI

/// Shared layout metrics for floating app chrome (tab bar + floating CTA buttons).
enum AppChromeMetrics {
    static let minimumTabBarHeight: CGFloat = 56
    static let tabBarBottomOffset: CGFloat = 8
    static let horizontalInset: CGFloat = 20

    private static let floatingButtonBottomMargin: CGFloat = 12
    private static let contentBottomMargin: CGFloat = 18

    static func floatingButtonBottomInset(tabBarHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        overlayCompensation(tabBarHeight: tabBarHeight, safeAreaBottom: safeAreaBottom) + floatingButtonBottomMargin
    }

    static func contentBottomInset(tabBarHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        overlayCompensation(tabBarHeight: tabBarHeight, safeAreaBottom: safeAreaBottom) + contentBottomMargin
    }

    private static func overlayCompensation(tabBarHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        max(0, normalized(tabBarHeight) + tabBarBottomOffset - safeAreaBottom)
    }

    private static func normalized(_ tabBarHeight: CGFloat) -> CGFloat {
        max(tabBarHeight, minimumTabBarHeight)
    }
}

private struct AppTabBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = AppChromeMetrics.minimumTabBarHeight
}

extension EnvironmentValues {
    var appTabBarHeight: CGFloat {
        get { self[AppTabBarHeightKey.self] }
        set { self[AppTabBarHeightKey.self] = newValue }
    }
}

private struct ViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func onMeasuredHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ViewHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(ViewHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            onChange(height)
        }
    }
}

/// Tab enumeration for the main navigation
enum Tab: String, CaseIterable {
    case shopping
    case tasks
    case backlog
    case more

    var title: String {
        switch self {
        case .shopping: "Shopping"
        case .tasks: "Tasks"
        case .backlog: "Backlog"
        case .more: "More"
        }
    }

    var icon: String {
        switch self {
        case .shopping: "cart.fill"
        case .tasks: "checkmark.circle.fill"
        case .backlog: "archivebox.fill"
        case .more: "ellipsis"
        }
    }
}

/// Floating tab bar rendered above scrolling content.
///
/// On iOS 26+, uses native Liquid Glass. On iOS 17-25, uses a tuned material
/// fallback with low-opacity tint so blur remains visible.
struct FloatingTabBar: View {
    @Binding var activeTab: Tab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background {
            tabBarSurface
        }
        .overlay {
            Capsule()
                .strokeBorder(borderColor, lineWidth: 0.5)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.5 : 0.12),
            radius: 12,
            x: 0,
            y: 5
        )
        .padding(.horizontal, AppChromeMetrics.horizontalInset)
    }

    @ViewBuilder
    private var tabBarSurface: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                Color.clear
                    .glassEffect(.regular.tint(liquidGlassTint))
            }
        } else {
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)

                Capsule()
                    .fill(fallbackTint)
            }
        }
    }

    private func tabButton(for tab: Tab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                HapticManager.selection()
                activeTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: activeTab == tab ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)

                Text(tab.title)
                    .font(.system(size: 10, weight: activeTab == tab ? .semibold : .regular))
            }
            .foregroundStyle(activeTab == tab ? .primary : .secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background {
                activePillBackground(isActive: activeTab == tab)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tabButton_\(tab.rawValue)")
    }

    @ViewBuilder
    private func activePillBackground(isActive: Bool) -> some View {
        if isActive {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 0) {
                    Color.clear
                        .glassEffect(.regular.tint(activePillTint).interactive())
                }
            } else {
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.36))
            }
        }
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    private var liquidGlassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.24)
    }

    private var activePillTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.32)
    }

    private var fallbackTint: Color {
        if colorScheme == .dark {
            return Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.30)
        }
        return Color.white.opacity(0.30)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            Spacer()
            FloatingTabBar(activeTab: .constant(.shopping))
                .padding(.bottom, AppChromeMetrics.tabBarBottomOffset)
        }
    }
}
