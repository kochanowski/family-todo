import SwiftUI

/// Shared layout metrics for compact CTA buttons.
enum AppChromeMetrics {
    static let horizontalInset: CGFloat = 20
    static let screenHorizontalInset: CGFloat = horizontalInset
    static let screenHeaderTopPadding: CGFloat = 16
    static let screenHeaderBottomPadding: CGFloat = 12
    static let compactCTAHeight: CGFloat = 44
    static let compactCTAHorizontalPadding: CGFloat = 20
    static let keyboardAccessoryBottomInset: CGFloat = 8
    static let floatingTabBarHeight: CGFloat = 60
    static let floatingTabBarCornerRadius: CGFloat = 26
    static let floatingTabBarHorizontalInset: CGFloat = 12
    static let floatingTabBarTopPadding: CGFloat = 8
    static let floatingTabBarBottomPadding: CGFloat = 8
    static let floatingTabBarCompactMaxWidth: CGFloat = 560
    static let regularContentMaxWidth: CGFloat = 960
    static let regularFormMaxWidth: CGFloat = 720
    static let regularHorizontalPadding: CGFloat = 24
}

private struct AppAdaptiveWidthModifier: ViewModifier {
    let maxWidth: CGFloat
    let alignment: Alignment

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var appliesRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    func body(content: Content) -> some View {
        content
            .frame(
                maxWidth: appliesRegularLayout ? maxWidth : .infinity,
                maxHeight: .infinity,
                alignment: alignment
            )
            .padding(.horizontal, appliesRegularLayout ? AppChromeMetrics.regularHorizontalPadding : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

extension View {
    func appAdaptiveWidth(
        maxWidth: CGFloat,
        alignment: Alignment = .topLeading
    ) -> some View {
        modifier(
            AppAdaptiveWidthModifier(
                maxWidth: maxWidth,
                alignment: alignment
            )
        )
    }
}

struct AppScreenHeader<Accessory: View, Trailing: View>: View {
    let title: String
    let accessory: Accessory
    let trailing: Trailing

    @EnvironmentObject private var themeStore: ThemeStore

    init(
        title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.accessory = accessory()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(themeStore.font(for: .screenHeader))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                accessory
            }

            Spacer(minLength: 12)

            trailing
        }
        .frame(minHeight: 44, alignment: .center)
    }
}

extension AppScreenHeader where Accessory == EmptyView {
    init(
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(title: title, accessory: { EmptyView() }, trailing: trailing)
    }
}

extension AppScreenHeader where Trailing == EmptyView {
    init(
        title: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(title: title, accessory: accessory, trailing: { EmptyView() })
    }
}

/// App tab identity used by native TabView.
enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case shopping
    case tasks
    case backlog
    case more

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .shopping: "Shopping"
        case .tasks: "Tasks"
        case .backlog: "Ideas"
        case .more: "More"
        }
    }

    var inactiveIcon: String {
        switch self {
        case .shopping: "cart"
        case .tasks: "checkmark.circle"
        case .backlog: "archivebox"
        case .more: "ellipsis"
        }
    }

    var icon: String {
        inactiveIcon
    }

    var activeIcon: String {
        switch self {
        case .shopping: "cart.fill"
        case .tasks: "checkmark.circle.fill"
        case .backlog: "archivebox.fill"
        case .more: "ellipsis"
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption2) private var iconSize = 18.0
    @ScaledMetric(relativeTo: .caption2) private var itemVerticalPadding = 6.0

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                glassBar
            } else {
                materialBar
            }
        }
        .padding(.top, AppChromeMetrics.floatingTabBarTopPadding)
        .padding(.horizontal, AppChromeMetrics.floatingTabBarHorizontalInset)
        .padding(.bottom, AppChromeMetrics.floatingTabBarBottomPadding)
        .frame(maxWidth: .infinity)
    }

    private var glassBar: some View {
        GlassEffectContainer(spacing: 0) {
            barContent
                .overlay {
                    RoundedRectangle(cornerRadius: AppChromeMetrics.floatingTabBarCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.28), lineWidth: 0.8)
                }
                .glassEffect(
                    .regular.tint(.clear),
                    in: .rect(cornerRadius: AppChromeMetrics.floatingTabBarCornerRadius)
                )
        }
    }

    private var materialBar: some View {
        barContent
            .background(
                .bar,
                in: RoundedRectangle(
                    cornerRadius: AppChromeMetrics.floatingTabBarCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppChromeMetrics.floatingTabBarCornerRadius, style: .continuous)
                    .strokeBorder(themeStore.borderLightColor.opacity(0.42), lineWidth: 0.8)
            }
            .shadow(color: themeStore.inkColor.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 14, x: 0, y: 8)
    }

    private var barContent: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: tabBarMaxWidth)
        .frame(height: AppChromeMetrics.floatingTabBarHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tab bar")
        .animation(.easeInOut(duration: 0.18), value: selection)
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = selection == tab
        let style = TabBarTypographyManager.resolvedStyle(
            themeStore: themeStore,
            colorScheme: colorScheme
        )
        let foreground = Color(uiColor: isSelected ? style.selectedColor : style.normalColor)

        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.activeIcon : tab.icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(height: 18)
                    .accessibilityHidden(true)

                Text(tab.title)
                    .font(themeStore.font(for: .tabLabel))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .padding(.vertical, itemVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tabBarMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? AppChromeMetrics.floatingTabBarCompactMaxWidth : .infinity
    }
}

#Preview {
    ZStack {
        AppBackgroundView()
        VStack {
            Spacer()
            FloatingTabBar(selection: .constant(.shopping))
        }
    }
    .environmentObject(ThemeStore())
}
