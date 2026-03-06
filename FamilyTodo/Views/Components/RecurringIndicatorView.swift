import SwiftUI

struct RecurringIndicatorView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        Image(systemName: "repeat")
            .font(themeStore.font(for: .chip))
            .foregroundStyle(themeStore.accentTabColor)
            .accessibilityLabel("Recurring task")
    }
}
