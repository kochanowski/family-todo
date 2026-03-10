import SwiftUI

struct AppConfirmationSheet: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    let title: String
    let message: String?
    let secondaryTitle: String
    let primaryTitle: String
    let titleFontToken: ThemeFontToken
    let messageFontToken: ThemeFontToken
    let primaryStyle: AppModalPrimaryStyle
    let onSecondary: (() -> Void)?
    let onPrimary: () -> Void

    init(
        title: String,
        message: String? = nil,
        secondaryTitle: String = "Cancel",
        primaryTitle: String,
        titleFontToken: ThemeFontToken = .inlineTitle,
        messageFontToken: ThemeFontToken = .bodySmall,
        primaryStyle: AppModalPrimaryStyle = .accent,
        onSecondary: (() -> Void)? = nil,
        onPrimary: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.secondaryTitle = secondaryTitle
        self.primaryTitle = primaryTitle
        self.titleFontToken = titleFontToken
        self.messageFontToken = messageFontToken
        self.primaryStyle = primaryStyle
        self.onSecondary = onSecondary
        self.onPrimary = onPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(themeStore.font(for: titleFontToken))
                .foregroundStyle(.primary)

            if let message {
                Text(message)
                    .font(themeStore.font(for: messageFontToken))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            AppModalActionRow(
                secondaryTitle: secondaryTitle,
                primaryTitle: primaryTitle,
                primaryStyle: primaryStyle,
                onSecondary: {
                    onSecondary?()
                    dismiss()
                },
                onPrimary: {
                    onPrimary()
                    dismiss()
                }
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .presentationDetents([.height(message == nil ? 190 : 220)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }
}
