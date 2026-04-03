import SwiftUI

struct SyncStatusPill: View {
    let text: String

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(themeStore.accentTabColor)

            Text(text)
                .font(themeStore.font(for: .bodySmall))
                .foregroundStyle(themeStore.contentSecondaryColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(themeStore.surfaceElevatedColor)
                .overlay {
                    Capsule()
                        .stroke(themeStore.borderLightColor.opacity(0.5), lineWidth: 0.8)
                }
                .shadow(color: themeStore.inkColor.opacity(shadowOpacity), radius: 8, x: 0, y: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.22 : 0.12
    }
}

struct SyncStatusIcon: View {
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(themeStore.accentTabColor)
            .frame(width: 18, height: 18)
            .accessibilityLabel("Syncing")
    }
}

#Preview {
    VStack(spacing: 16) {
        SyncStatusPill(text: "Shopping updated")
        SyncStatusIcon()
    }
    .environmentObject(ThemeStore())
    .padding()
}
