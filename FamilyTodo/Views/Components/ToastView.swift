import SwiftUI

/// Shared toast/snackbar used across Ideas/Tasks undo and celebrations.
struct ToastView: View {
    struct Appearance {
        let backgroundColor: Color
        let messageColor: Color
        let strokeColor: Color
        let shadowColor: Color
        var actionColor: Color
        var messageFont: Font?
        var actionFont: Font

        init(
            backgroundColor: Color,
            messageColor: Color,
            strokeColor: Color,
            shadowColor: Color,
            actionColor: Color,
            messageFont: Font? = nil,
            actionFont: Font = .headline
        ) {
            self.backgroundColor = backgroundColor
            self.messageColor = messageColor
            self.strokeColor = strokeColor
            self.shadowColor = shadowColor
            self.actionColor = actionColor
            self.messageFont = messageFont
            self.actionFont = actionFont
        }
    }

    enum Metrics {
        static let height: CGFloat = 52
        static let horizontalInset: CGFloat = 20
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 12
    }

    enum AnimationTokens {
        static let transition: AnyTransition = .move(edge: .bottom).combined(with: .opacity)
        static let curve: Animation = .spring(response: 0.34, dampingFraction: 0.86)
    }

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    let message: String
    var messageFont: Font?
    var leadingText: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var appearance: Appearance?

    var body: some View {
        if let appearance {
            toastBody(
                messageColor: appearance.messageColor,
                actionColor: appearance.actionColor,
                messageFont: messageFont ?? appearance.messageFont ?? .system(size: 13),
                actionFont: appearance.actionFont,
                backgroundColor: appearance.backgroundColor,
                strokeColor: appearance.strokeColor,
                shadowColor: appearance.shadowColor
            )
        } else {
            toastBody(
                messageColor: messageColor,
                actionColor: themeStore.accentTabColor,
                messageFont: messageFont ?? themeStore.font(for: .bodySmall),
                actionFont: themeStore.font(for: .buttonLabel),
                backgroundColor: backgroundColor,
                strokeColor: strokeColor,
                shadowColor: shadowColor
            )
        }
    }

    private func toastBody(
        messageColor: Color,
        actionColor: Color,
        messageFont: Font,
        actionFont: Font,
        backgroundColor: Color,
        strokeColor: Color,
        shadowColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            if let leadingText {
                Text(leadingText)
                    .font(.system(size: 18))
                    .foregroundStyle(messageColor)
                    .accessibilityHidden(true)
            }

            Text(message)
                .font(messageFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(messageColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .font(actionFont)
                .fontWeight(.bold)
                .foregroundStyle(actionColor)
            }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.height)
        .background {
            Capsule()
                .fill(backgroundColor)
                .overlay {
                    Capsule()
                        .stroke(strokeColor, lineWidth: 0.8)
                }
                .shadow(color: shadowColor, radius: 10, x: 0, y: 5)
        }
    }

    private var backgroundColor: Color {
        themeStore.surfaceElevatedColor
    }

    private var messageColor: Color {
        themeStore.foregroundOnAccent(for: backgroundColor, colorScheme: colorScheme)
    }

    private var strokeColor: Color {
        themeStore.borderLightColor.opacity(0.55)
    }

    private var shadowColor: Color {
        themeStore.inkColor.opacity(0.18)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            Spacer()
            ToastView(message: "3 items cleared", actionTitle: "Undo", action: { print("Undo!") })
                .environmentObject(ThemeStore())
                .padding(.bottom, 100)
        }
    }
}
