import Foundation
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

    enum TaskCompletionTier {
        case milestone
        case surprise
        case fallback
    }

    struct TaskCompletionDecision {
        let celebration: Celebration
        let tier: TaskCompletionTier
    }

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

    private enum DefaultsKey {
        static let lastSurpriseAt = "celebrations.lastSurpriseAt"
    }

    private let userDefaults: UserDefaults
    private let nowProvider: () -> Date
    private let randomInt: (ClosedRange<Int>) -> Int

    private static let milestoneMessages: [(emoji: String, message: String)] = [
        ("🎉", "Weekly milestone hit! Home is glowing."),
        ("🏡", "Big win this week. HousePulse is strong."),
        ("✨", "Milestone unlocked. Nice household teamwork!"),
    ]

    private static let surpriseMessages: [(emoji: String, message: String)] = [
        ("🎈", "Surprise boost! You are making home life smoother."),
        ("💫", "Tiny celebration moment. Keep that flow going!"),
        ("🌟", "Unexpected cheer: your consistency shows."),
    ]

    init(
        userDefaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = Date.init,
        randomInt: @escaping (ClosedRange<Int>) -> Int = { Int.random(in: $0) }
    ) {
        self.userDefaults = userDefaults
        self.nowProvider = nowProvider
        self.randomInt = randomInt
    }

    /// Celebrate a single task completion.
    func celebrateTaskCompletion(taskTitle: String, weeklyCompletedCount: Int) {
        let now = nowProvider()
        let decision = decideTaskCompletion(
            taskTitle: taskTitle,
            weeklyCompletedCount: weeklyCompletedCount,
            now: now
        )
        show(decision.celebration)
    }

    func decideTaskCompletion(
        taskTitle: String,
        weeklyCompletedCount: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskCompletionDecision {
        if isMilestoneCount(weeklyCompletedCount) {
            let message = pickMessage(
                from: Self.milestoneMessages,
                fallback: ("🎉", "All tasks done! Time to relax")
            )
            return TaskCompletionDecision(
                celebration: Celebration(
                    emoji: message.emoji,
                    message: message.message,
                    style: .milestone
                ),
                tier: .milestone
            )
        }

        if canTriggerSurprise(now: now, calendar: calendar), randomInt(1 ... 10) == 1 {
            userDefaults.set(now, forKey: DefaultsKey.lastSurpriseAt)
            let message = pickMessage(
                from: Self.surpriseMessages,
                fallback: ("🎈", "Surprise boost. Great energy today!")
            )
            return TaskCompletionDecision(
                celebration: Celebration(
                    emoji: message.emoji,
                    message: message.message,
                    style: .normal
                ),
                tier: .surprise
            )
        }

        let fallbackMessage = pickMessage(
            from: fallbackMessages(for: taskTitle),
            fallback: ("✨", "Done! \(taskTitle)")
        )
        return TaskCompletionDecision(
            celebration: Celebration(
                emoji: fallbackMessage.emoji,
                message: fallbackMessage.message,
                style: .normal
            ),
            tier: .fallback
        )
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

    /// Clears transient celebration UI and cadence state for fresh-start testing.
    func resetForDevelopment() {
        activeCelebration = nil
        confettiTrigger = 0
        userDefaults.removeObject(forKey: DefaultsKey.lastSurpriseAt)
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
        if celebration.style == .milestone {
            confettiTrigger += 1
        }
        HapticManager.success()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard self?.activeCelebration?.id == celebration.id else { return }
            withAnimation(WowAnimation.easeOut) {
                self?.activeCelebration = nil
            }
        }
    }

    private func isMilestoneCount(_ weeklyCompletedCount: Int) -> Bool {
        weeklyCompletedCount == 5 || weeklyCompletedCount == 10
    }

    private func canTriggerSurprise(
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let lastSurpriseAt = userDefaults.object(forKey: DefaultsKey.lastSurpriseAt) as? Date else {
            return true
        }
        guard let nextEligibleDate = calendar.date(byAdding: .day, value: 7, to: lastSurpriseAt) else {
            return true
        }
        return now >= nextEligibleDate
    }

    private func fallbackMessages(for taskTitle: String) -> [(emoji: String, message: String)] {
        [
            ("✨", "Done! \(taskTitle)"),
            ("👏", "Nice one!"),
            ("✅", "\(taskTitle) - sorted!"),
            ("💪", "Crushed it!"),
            ("🧹", "Another task off the board."),
            ("🏠", "Home is looking better already."),
        ]
    }

    private func pickMessage(
        from messages: [(emoji: String, message: String)],
        fallback: (emoji: String, message: String)
    ) -> (emoji: String, message: String) {
        guard !messages.isEmpty else { return fallback }
        let validRange = 0 ... (messages.count - 1)
        let index = min(max(randomInt(validRange), validRange.lowerBound), validRange.upperBound)
        return messages[index]
    }
}
