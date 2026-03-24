import SwiftUI

/// In-app banner for new remote changes
struct NewItemsBanner: View {
    let count: Int
    let onTap: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(foregroundColor)

                Text(bannerText)
                    .font(themeStore.font(for: .bodyStrong))
                    .foregroundStyle(foregroundColor)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(foregroundColor.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.trailing, 28)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeStore.accentTabColor)
                    .shadow(
                        color: themeStore.inkColor.opacity(colorScheme == .dark ? 0.28 : 0.2),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(foregroundColor.opacity(0.7))
                    .padding(6)
            }
        }
        .padding(.horizontal, 20)
    }

    private var bannerText: String {
        if count == 1 {
            "1 new shopping item"
        } else {
            "\(count) new shopping items"
        }
    }

    private var foregroundColor: Color {
        themeStore.foregroundOnAccent(for: themeStore.accentTabColor, colorScheme: colorScheme)
    }
}

#Preview {
    VStack {
        NewItemsBanner(count: 3, onTap: {}, onDismiss: {})
        Spacer()
    }
    .padding(.top, 60)
    .background(Color(hex: "F9F9F9"))
    .environmentObject(ThemeStore())
}
