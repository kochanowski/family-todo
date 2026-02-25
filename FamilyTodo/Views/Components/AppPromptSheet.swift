import SwiftUI

struct AppPromptSheet: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    let title: String
    let message: String?
    let placeholder: String
    @Binding var text: String
    let secondaryTitle: String
    let primaryTitle: String
    let primaryStyle: AppModalPrimaryStyle
    let onCancel: (() -> Void)?
    let onSubmit: (String) -> Void

    init(
        title: String,
        message: String? = nil,
        placeholder: String,
        text: Binding<String>,
        secondaryTitle: String = "Cancel",
        primaryTitle: String,
        primaryStyle: AppModalPrimaryStyle = .accent,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (String) -> Void
    ) {
        self.title = title
        self.message = message
        self.placeholder = placeholder
        _text = text
        self.secondaryTitle = secondaryTitle
        self.primaryTitle = primaryTitle
        self.primaryStyle = primaryStyle
        self.onCancel = onCancel
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(themeStore.font(for: .inlineTitle))
                .foregroundStyle(.primary)

            if let message {
                Text(message)
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(.secondary)
            }
            TextField(placeholder, text: $text)
                .font(themeStore.font(for: .inlineTitle))
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.12))
                }
                .onSubmit {
                    submitAndDismiss()
                }

            Spacer(minLength: 0)

            AppModalActionRow(
                secondaryTitle: secondaryTitle,
                primaryTitle: primaryTitle,
                primaryStyle: primaryStyle,
                isPrimaryDisabled: trimmedValue.isEmpty,
                onSecondary: {
                    onCancel?()
                    dismiss()
                },
                onPrimary: submitAndDismiss
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .presentationDetents([.height(message == nil ? 230 : 260)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }

    private var trimmedValue: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitAndDismiss() {
        guard !trimmedValue.isEmpty else { return }
        onSubmit(trimmedValue)
        dismiss()
    }
}
