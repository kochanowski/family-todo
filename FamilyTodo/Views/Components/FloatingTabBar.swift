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

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// Floating tab bar rendered above scrolling content.
struct FloatingTabBar: View {
    @Binding var activeTab: Tab
    @Environment(\.colorScheme) private var colorScheme

    private let tabBarContentHeight: CGFloat = 52
    private let activeIndicatorSize = CGSize(width: 88, height: 48)
    private let horizontalContentPadding: CGFloat = 8
    private let verticalContentPadding: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let barWidth = proxy.size.width
            let indicatorX = indicatorCenterX(totalWidth: barWidth)

            ZStack(alignment: .leading) {
                activeIndicator
                    .frame(width: activeIndicatorSize.width, height: activeIndicatorSize.height)
                    .position(x: indicatorX, y: proxy.size.height / 2)
                    .allowsHitTesting(false)
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activeTab)

                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        tabButton(for: tab)
                    }
                }
                .frame(height: tabBarContentHeight)
                .padding(.horizontal, horizontalContentPadding)
                .padding(.vertical, verticalContentPadding)
            }
            .background {
                tabBarBackground
            }
            .overlay {
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: shadowColor,
                radius: 12,
                x: 0,
                y: 5
            )
        }
        .frame(height: tabBarContentHeight + (verticalContentPadding * 2))
        .padding(.horizontal, AppChromeMetrics.horizontalInset)
    }

    private func tabButton(for tab: Tab) -> some View {
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
        .accessibilityIdentifier("tabButton_\(tab.rawValue)")
    }

    @ViewBuilder
    private var activeIndicator: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(dropletTint).interactive(), in: .capsule)
        } else {
            fallbackIndicator
        }
    }

    @ViewBuilder
    private var tabBarBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(liquidBaseTint)
        } else {
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .fill(fallbackTint)
            }
            .clipShape(Capsule())
        }
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

    private func indicatorCenterX(totalWidth: CGFloat) -> CGFloat {
        let contentWidth = max(0, totalWidth - (horizontalContentPadding * 2))
        let tabCount = CGFloat(max(1, Tab.allCases.count))
        let slotWidth = contentWidth / tabCount
        return horizontalContentPadding + slotWidth * (CGFloat(activeTab.index) + 0.5)
    }

    private var isIOS26: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    private var shadowColor: Color {
        if isIOS26, colorScheme != .dark {
            return .clear
        }
        return .black.opacity(colorScheme == .dark ? 0.46 : 0.1)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    private var liquidBaseTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.2)
    }

    private var dropletTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.34)
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
