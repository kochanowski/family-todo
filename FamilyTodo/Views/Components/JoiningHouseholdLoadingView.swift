import SwiftUI

struct JoiningHouseholdLoadingView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let isActive: Bool
    var title: String = "Joining household..."
    var messages: [String] = Self.defaultMessages
    var cycleIntervalNanoseconds: UInt64 = 1_350_000_000

    @State private var activeMessageIndex = 0

    private static let defaultMessages = [
        "We're preparing your household...",
        "Syncing your data...",
        "Fetching tasks and ideas...",
        "Can't wait for your shopping bundles!",
        "Almost there...",
    ]

    var body: some View {
        ZStack {
            themeStore.canvasColor
                .opacity(0.24)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.1)
                    .tint(themeStore.accentTabColor)

                VStack(spacing: 8) {
                    Text(title)
                        .font(themeStore.font(for: .screenHeader))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                        .multilineTextAlignment(.center)

                    Text(activeMessage)
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                        .id(activeMessage)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(themeStore.surfaceElevatedColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(themeStore.borderLightColor.opacity(0.55), lineWidth: 1)
                    }
                    .shadow(color: themeStore.inkColor.opacity(0.14), radius: 22, x: 0, y: 12)
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(activeMessage)")
        }
        .task(id: isActive) {
            await cycleMessagesIfNeeded()
        }
        .onDisappear {
            activeMessageIndex = 0
        }
    }

    private var activeMessage: String {
        let resolvedMessages = messages.isEmpty ? Self.defaultMessages : messages
        let safeIndex = min(activeMessageIndex, resolvedMessages.count - 1)
        return resolvedMessages[safeIndex]
    }

    private func cycleMessagesIfNeeded() async {
        guard isActive else {
            activeMessageIndex = 0
            return
        }

        let resolvedMessages = messages.isEmpty ? Self.defaultMessages : messages
        guard resolvedMessages.count > 1 else {
            activeMessageIndex = 0
            return
        }

        activeMessageIndex = 0
        while !_Concurrency.Task.isCancelled, isActive {
            try? await _Concurrency.Task.sleep(nanoseconds: cycleIntervalNanoseconds)
            guard !_Concurrency.Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                activeMessageIndex = (activeMessageIndex + 1) % resolvedMessages.count
            }
        }
    }
}

#Preview {
    JoiningHouseholdLoadingView(isActive: true)
        .environmentObject(ThemeStore())
}
