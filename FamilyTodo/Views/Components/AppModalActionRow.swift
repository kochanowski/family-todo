import SwiftUI

enum AppModalPrimaryStyle {
    case accent
    case destructive
}

struct AppModalActionRow: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    let secondaryTitle: String
    let primaryTitle: String
    let primaryStyle: AppModalPrimaryStyle
    let isPrimaryDisabled: Bool
    let onSecondary: () -> Void
    let onPrimary: () -> Void

    init(
        secondaryTitle: String = "Cancel",
        primaryTitle: String,
        primaryStyle: AppModalPrimaryStyle = .accent,
        isPrimaryDisabled: Bool = false,
        onSecondary: @escaping () -> Void,
        onPrimary: @escaping () -> Void
    ) {
        self.secondaryTitle = secondaryTitle
        self.primaryTitle = primaryTitle
        self.primaryStyle = primaryStyle
        self.isPrimaryDisabled = isPrimaryDisabled
        self.onSecondary = onSecondary
        self.onPrimary = onPrimary
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                HapticManager.lightTap()
                onSecondary()
            }) {
                Text(secondaryTitle)
                    .font(themeStore.font(for: .buttonLabel))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        Capsule()
                            .fill(secondaryBackground)
                    }
            }
            .buttonStyle(.plain)

            Button(action: {
                if primaryStyle == .destructive {
                    HapticManager.warning()
                } else {
                    HapticManager.success()
                }
                onPrimary()
            }) {
                Text(primaryTitle)
                    .font(themeStore.font(for: .buttonLabel))
                    .fontWeight(.bold)
                    .foregroundStyle(primaryForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        Capsule()
                            .fill(primaryBackground)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isPrimaryDisabled)
            .opacity(isPrimaryDisabled ? 0.45 : 1)
        }
    }

    private var secondaryBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }

    private var primaryBackground: Color {
        switch primaryStyle {
        case .accent:
            themeStore.accentTabColor
        case .destructive:
            .red
        }
    }

    private var primaryForeground: Color {
        switch primaryStyle {
        case .accent:
            themeStore.foregroundOnAccent(for: themeStore.accentTabColor, colorScheme: colorScheme)
        case .destructive:
            .white
        }
    }
}
