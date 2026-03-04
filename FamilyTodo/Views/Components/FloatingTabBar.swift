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
    static let emptyStateTopPadding: CGFloat = 100
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
