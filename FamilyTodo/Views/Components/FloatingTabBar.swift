import SwiftUI

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

/// Custom floating tab bar with frosted-glass blur anchored near the bottom safe area.
///
/// Uses SwiftUI `.thinMaterial` so the blur correctly samples SwiftUI-rendered
/// content layers. The parent view must use an overlay (not safeAreaInset) so
/// scrolling content renders behind the bar, giving the material real pixels to blur.
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
            ZStack {
                // Base glass: semi-transparent color for reliable glass look
                Capsule()
                    .fill(colorScheme == .dark
                        ? Color(white: 0.15).opacity(0.8)
                        : Color.white.opacity(0.78))

                // Material: adds real blur when content scrolls behind
                Capsule()
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.18)
                            : Color.black.opacity(0.08),
                        lineWidth: 0.5
                    )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.5 : 0.12),
                radius: 12, x: 0, y: 5
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
