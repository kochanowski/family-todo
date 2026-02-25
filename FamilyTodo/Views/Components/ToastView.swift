import SwiftUI

/// Shared toast/snackbar used across Ideas/Tasks undo and celebrations.
struct ToastView: View {
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

    var body: some View {
        HStack(spacing: 12) {
            if let leadingText {
                Text(leadingText)
                    .font(.system(size: 18))
                    .foregroundStyle(messageColor)
                    .accessibilityHidden(true)
            }

            Text(message)
                .font(messageFont ?? themeStore.font(for: .bodySmall))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(messageColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .font(themeStore.font(for: .buttonLabel))
                .fontWeight(.bold)
                .foregroundStyle(themeStore.accentTabColor)
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
        colorScheme == .light ? Color(uiColor: .darkGray) : Color(uiColor: .systemGray5)
    }

    private var messageColor: Color {
        colorScheme == .light ? .white : .black
    }

    private var strokeColor: Color {
        colorScheme == .light ? .white.opacity(0.2) : .black.opacity(0.12)
    }

    private var shadowColor: Color {
        colorScheme == .light ? .black.opacity(0.32) : .black.opacity(0.12)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            Spacer()
            ToastView(message: "3 items cleared", actionTitle: "Undo", action: { print("Undo!") })
                .padding(.bottom, 100)
        }
    }
}
