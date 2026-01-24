import Foundation
import SwiftUI

@MainActor
final class NotificationSettingsStore: ObservableObject {
    // Daily digest
    @AppStorage("notifications.dailyDigest.enabled")
    var dailyDigestEnabled = false {
        didSet { objectWillChange.send() }
    }

    @AppStorage("notifications.dailyDigest.hour")
    var dailyDigestHour = 8 {
        didSet { objectWillChange.send() }
    }

    @AppStorage("notifications.dailyDigest.minute")
    var dailyDigestMinute = 0 {
        didSet { objectWillChange.send() }
    }

    // Task reminders
    @AppStorage("notifications.taskReminders.enabled")
    var taskRemindersEnabled = true {
        didSet { objectWillChange.send() }
    }

    // Celebrations (UI implementation post-MVP)
    @AppStorage("notifications.celebrations.enabled")
    var celebrationsEnabled = true {
        didSet { objectWillChange.send() }
    }

    // Sound
    @AppStorage("notifications.sound.enabled")
    var soundEnabled = true {
        didSet { objectWillChange.send() }
    }
}
