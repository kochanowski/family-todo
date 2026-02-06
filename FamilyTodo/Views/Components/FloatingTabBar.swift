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

/// Custom floating tab bar with a UIKit frosted glass background.
///
/// Uses `UIVisualEffectView` to match native iOS chrome more closely than a
/// pure SwiftUI material stack.
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
        .padding(.vertical, 9)
        .frame(height: 58)
        .allowsHitTesting(true)
        .background {
            Capsule()
                .fill(.clear)
                .overlay {
                    VisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
                        .clipShape(Capsule())
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            borderColor,
                            lineWidth: 0.6
                        )
                }
                .shadow(
                    color: shadowColor,
                    radius: 12,
                    x: 0,
                    y: 6
                )
        }
        .padding(.horizontal, 16)
        .compositingGroup()
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
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tabButton_\(tab.rawValue)")
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.12)
    }
}

private struct VisualEffectView: UIViewRepresentable {
    let effect: UIVisualEffect

    func makeUIView(context _: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: effect)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context _: Context) {
        uiView.effect = effect
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            Spacer()
            FloatingTabBar(activeTab: .constant(.shopping))
                .padding(.bottom, 6)
        }
    }
}
