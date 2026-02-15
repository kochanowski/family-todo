import SwiftUI

/// Shared layout metrics for floating app chrome (tab bar + floating CTA buttons).
enum AppChromeMetrics {
    static let minimumTabBarHeight: CGFloat = 56
    static let tabBarBottomOffset: CGFloat = -4
    static let horizontalInset: CGFloat = 20
    static let compactCTAHeight: CGFloat = 44
    static let compactCTAHorizontalPadding: CGFloat = 20
    static let compactCTAVerticalPadding: CGFloat = 12
    static let keyboardAccessoryBottomInset: CGFloat = 8

    private static let floatingButtonClearance: CGFloat = 8
    private static let contentClearance: CGFloat = 12

    static func floatingButtonBottomInset(tabBarHeight: CGFloat) -> CGFloat {
        normalized(tabBarHeight) + tabBarBottomOffset + floatingButtonClearance
    }

    static func contentBottomInset(tabBarHeight: CGFloat) -> CGFloat {
        normalized(tabBarHeight) + tabBarBottomOffset + contentClearance
    }

    private static func normalized(_ tabBarHeight: CGFloat) -> CGFloat {
        max(tabBarHeight, minimumTabBarHeight)
    }
}

private struct AppTabBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = AppChromeMetrics.minimumTabBarHeight
}

private struct AppKeyboardVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appTabBarHeight: CGFloat {
        get { self[AppTabBarHeightKey.self] }
        set { self[AppTabBarHeightKey.self] = newValue }
    }

    var appKeyboardVisible: Bool {
        get { self[AppKeyboardVisibleKey.self] }
        set { self[AppKeyboardVisibleKey.self] = newValue }
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

    var activeIconColor: Color {
        switch self {
        case .shopping: .blue
        case .tasks: .green
        case .backlog: .orange
        case .more: .purple
        }
    }
}

/// Floating tab bar rendered above scrolling content.
///
/// iOS 26+ path uses Liquid Glass indicator transition (`glassEffectID` +
/// `glassEffectTransition(.matchedGeometry)`), while iOS 17-25 keeps a material fallback.
struct FloatingTabBar: View {
    @Binding var activeTab: Tab
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var glassNamespace
    @Namespace private var fallbackNamespace

    private let tabBarContentHeight: CGFloat = 52
    private let activeIndicatorSize = CGSize(width: 86, height: 52)

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                tabBarBody(useGlassIndicator: true)
                    .background {
                        Capsule()
                            .fill(liquidBaseTint)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(borderColor, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
            } else {
                tabBarBody(useGlassIndicator: false)
                    .background {
                        ZStack {
                            Capsule()
                                .fill(.ultraThinMaterial)

                            Capsule()
                                .fill(fallbackTint)
                        }
                    }
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(borderColor, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.5 : 0.12),
                        radius: 12,
                        x: 0,
                        y: 5
                    )
            }
        }
        .padding(.horizontal, AppChromeMetrics.horizontalInset)
    }

    @ViewBuilder
    private func tabBarBody(useGlassIndicator: Bool) -> some View {
        if #available(iOS 26.0, *), useGlassIndicator {
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        tabButton(for: tab, useGlassIndicator: true)
                    }
                }
            }
            .frame(height: tabBarContentHeight)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        } else {
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    tabButton(for: tab, useGlassIndicator: false)
                }
            }
            .frame(height: tabBarContentHeight)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func indicator(for tab: Tab, useGlassIndicator: Bool) -> some View {
        if activeTab == tab {
            if useGlassIndicator {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .frame(width: activeIndicatorSize.width, height: activeIndicatorSize.height)
                        .glassEffect(.regular.tint(dropletTint).interactive(), in: .capsule)
                        .glassEffectID("activeTabIndicator", in: glassNamespace)
                        .glassEffectTransition(.matchedGeometry)
                        .allowsHitTesting(false)
                }
            } else {
                fallbackIndicator
                    .frame(width: activeIndicatorSize.width, height: activeIndicatorSize.height)
                    .matchedGeometryEffect(id: "activeTabIndicatorFallback", in: fallbackNamespace)
                    .allowsHitTesting(false)
            }
        }
    }

    private func tabButton(for tab: Tab, useGlassIndicator: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                HapticManager.selection()
                activeTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: activeTab == tab ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(activeTab == tab ? tab.activeIconColor : .secondary)

                Text(tab.title)
                    .font(.system(size: 10, weight: activeTab == tab ? .semibold : .regular))
                    .foregroundStyle(activeTab == tab ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(alignment: .center) {
            indicator(for: tab, useGlassIndicator: useGlassIndicator)
        }
        .accessibilityIdentifier("tabButton_\(tab.rawValue)")
    }

    private var fallbackIndicator: some View {
        Capsule()
            .fill(colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.9))
            .overlay {
                Capsule()
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.14),
                        lineWidth: 0.6
                    )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.1), radius: 6, x: 0, y: 3)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    private var liquidBaseTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.7)
    }

    private var dropletTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.white.opacity(0.52)
    }

    private var fallbackTint: Color {
        if colorScheme == .dark {
            return Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.3)
        }
        return Color.white.opacity(0.3)
    }
}

#Preview {
    ZStack {
        AppBackgroundView()
        VStack {
            Spacer()
            FloatingTabBar(activeTab: .constant(.shopping))
        }
    }
    .ignoresSafeArea()
}
