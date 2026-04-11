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
