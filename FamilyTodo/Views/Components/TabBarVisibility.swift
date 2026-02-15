import SwiftUI

private struct AppTabBarVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

private struct AppTabBarVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}

extension EnvironmentValues {
    var appTabBarVisible: Bool {
        get { self[AppTabBarVisibleKey.self] }
        set { self[AppTabBarVisibleKey.self] = newValue }
    }
}

extension View {
    func appTabBarVisibility(_ visible: Bool) -> some View {
        environment(\.appTabBarVisible, visible)
            .preference(key: AppTabBarVisibilityPreferenceKey.self, value: visible)
    }

    func onTabBarVisibilityChange(_ action: @escaping (Bool) -> Void) -> some View {
        onPreferenceChange(AppTabBarVisibilityPreferenceKey.self, perform: action)
    }
}
