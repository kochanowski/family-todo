import SwiftUI

#if !targetEnvironment(simulator) && !CI
    import UserNotifications
#endif

/// Duolingo-style gentle celebrations — private, optional, never competitive.
@MainActor
final class CelebrationManager: ObservableObject {
    static let shared = CelebrationManager()

    @Published var activeCelebration: Celebration?
    @Published var confettiTrigger: Int = 0

    struct Celebration: Identifiable, Equatable {
        let id = UUID()
        let emoji: String
        let message: String
        let style: Style

        enum Style {
            case normal // Simple toast
            case milestone // Toast + confetti
        }

        static func == (lhs: Celebration, rhs: Celebration) -> Bool {
            lhs.id == rhs.id
        }
    }

    private init() {}

    /// Celebrate a single task completion.
    func celebrateTaskCompletion(taskTitle: String) {
        let messages = [
            ("✨", "Done! \(taskTitle)"),
            ("👏", "Nice one!"),
            ("✅", "\(taskTitle) — sorted!"),
            ("💪", "Crushed it!"),
        ]
        guard let pick = messages.randomElement() else { return }
        show(Celebration(emoji: pick.0, message: pick.1, style: .normal))
    }

    /// Celebrate all tasks cleared from Next.
    func celebrateAllTasksComplete() {
        show(Celebration(emoji: "🎉", message: "All tasks done! Time to relax", style: .milestone))
    }

    /// Celebrate shopping list cleared.
    func celebrateShoppingComplete() {
        show(Celebration(emoji: "🛒", message: "Shopping done! Fridge is happy", style: .milestone))
    }

    /// Trigger confetti independently if needed.
    func triggerConfetti() {
        confettiTrigger += 1
    }

    /// Notify partner about completion (local notification).
    func notifyPartner(completedBy memberName: String, action: String) {
        #if !targetEnvironment(simulator) && !CI
            let content = UNMutableNotificationContent()
            content.title = "💙 \(memberName) is on fire!"
            content.body = action
            content.sound = .default
            content.categoryIdentifier = "CELEBRATION"

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "celebration-\(UUID().uuidString)",
                content: content,
                trigger: trigger
            )

            _ = _Concurrency.Task {
                try? await UNUserNotificationCenter.current().add(request)
            }
        #endif
    }

    private func show(_ celebration: Celebration) {
        withAnimation(WowAnimation.spring) {
            activeCelebration = celebration
        }
        HapticManager.success()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard self?.activeCelebration?.id == celebration.id else { return }
            withAnimation(WowAnimation.easeOut) {
                self?.activeCelebration = nil
            }
        }
    }
}
