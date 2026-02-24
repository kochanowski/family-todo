import SwiftUI

/// Toast notification with glassmorphism and undo action
struct ToastView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let message: String
    var undoAction: (() -> Void)?
    var onDismiss: (() -> Void)?
    var displayDuration: TimeInterval = 4

    @State private var isVisible = true

    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                if let undoAction {
                    Button("Undo") {
                        undoAction()
                        dismiss()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .fontWeight(.bold)
                    .foregroundStyle(themeStore.accentTabColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration) {
                    dismiss()
                }
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            isVisible = false
        }
        onDismiss?()
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            Spacer()
            ToastView(message: "3 items cleared", undoAction: { print("Undo!") })
                .padding(.bottom, 100)
        }
    }
}
