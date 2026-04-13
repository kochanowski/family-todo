import Combine
import SwiftUI

/// Session-scoped developer mode toggle. Unlocked with a secret 5-tap gesture on the
/// "Settings" navigation title. Resets to locked on every cold start.
final class DeveloperModeState: ObservableObject {
    static let shared = DeveloperModeState()

    @Published private(set) var isUnlocked = false

    private init() {}

    func toggle() {
        isUnlocked.toggle()
    }
}
