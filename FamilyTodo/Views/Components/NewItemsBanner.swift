import SwiftUI

/// In-app banner for new remote changes
struct NewItemsBanner: View {
    let count: Int
    let onTap: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white)

            Text(bannerText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 20)
        .onTapGesture {
            onTap()
        }
    }

    private var bannerText: String {
        if count == 1 {
            return "1 new item added"
        } else {
            return "\(count) new items added"
        }
    }
}

/// View modifier to add new items banner overlay
struct NewItemsBannerModifier: ViewModifier {
    @ObservedObject var subscriptionManager: CloudKitSubscriptionManager

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if subscriptionManager.showNewItemsBanner {
                    NewItemsBanner(
                        count: subscriptionManager.newItemsCount,
                        onTap: {
                            subscriptionManager.dismissBanner()
                            // Scroll to new items handled by parent view
                        },
                        onDismiss: {
                            subscriptionManager.dismissBanner()
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                }
            }
            .animation(WowAnimation.spring, value: subscriptionManager.showNewItemsBanner)
    }
}

extension View {
    func newItemsBanner(manager: CloudKitSubscriptionManager) -> some View {
        modifier(NewItemsBannerModifier(subscriptionManager: manager))
    }
}

#Preview {
    VStack {
        NewItemsBanner(count: 3, onTap: {}, onDismiss: {})
        Spacer()
    }
    .padding(.top, 60)
    .background(Color(hex: "F9F9F9"))
}
