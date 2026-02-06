import SwiftUI
import UIKit

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

/// Custom floating tab bar with real frosted-glass blur anchored near the bottom safe area.
///
/// Uses UIKit `UIVisualEffectView(.systemChromeMaterial)` for reliable blur that
/// adapts to light/dark mode automatically. The parent view must use an overlay
/// (not safeAreaInset) so scrolling content renders behind the bar, giving the
/// material real pixels to blur.
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
            // Real UIKit blur – clips to capsule so frosted glass is visible
            VisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                }
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.45 : 0.12),
                    radius: 16, x: 0, y: 4
                )
        }
        .padding(.horizontal, 20)
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tabButton_\(tab.rawValue)")
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            Spacer()
            FloatingTabBar(activeTab: .constant(.shopping))
                .padding(.bottom, 8)
        }
    }
}
