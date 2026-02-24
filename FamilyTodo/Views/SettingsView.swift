import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var notificationSettings = NotificationSettingsStore()
    @AppStorage("recommendedWipLimit") private var recommendedWipLimit = TaskStore.defaultRecommendedWipLimit

    var body: some View {
        List {
            // MARK: - Theme + Appearance Section

            Section {
                ThemeMiniatureCarousel(selectedTheme: Binding(
                    get: { themeStore.unifiedTheme },
                    set: {
                        HapticManager.selection()
                        themeStore.unifiedTheme = $0
                    }
                ))
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            } header: {
                Text("Appearance")
            }

            // MARK: - Font Management Settings Section

            Section {
                Picker("System Font Size", selection: selectedFontScaleBinding) {
                    ForEach(FontSizeScale.allCases) { scale in
                        Text(scale.displayName).tag(scale)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            } header: {
                Text("System Font Size")
            } footer: {
                if themeStore.preset == .retro {
                    Text("Regular is the default font size.")
                }
            }

            // MARK: - Tab Color Section

            Section {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ],
                    spacing: 12
                ) {
                    ForEach(TabTintColor.allCases) { tint in
                        Button {
                            HapticManager.selection()
                            themeStore.tabTintColor = tint
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(tint.color)
                                    .frame(height: 34)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                themeStore.tabTintColor == tint ? Color.primary : Color.secondary.opacity(0.2),
                                                lineWidth: themeStore.tabTintColor == tint ? 2.5 : 1
                                            )
                                    }
                                    .shadow(
                                        color: tint.color.opacity(0.28),
                                        radius: 4,
                                        x: 0,
                                        y: 2
                                    )
                                Text(tint.displayName)
                                    .font(themeStore.font(for: .tabLabel))
                                    .foregroundStyle(
                                        themeStore.tabTintColor == tint ? .primary : .secondary
                                    )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text("Accent Color")
            }

            // MARK: - Toggles Section

            Section {
                Toggle(isOn: Binding(
                    get: { themeStore.celebrationsEnabled },
                    set: { themeStore.celebrationsEnabled = $0 }
                )) {
                    Label("Celebrations", systemImage: "party.popper.fill")
                        .foregroundStyle(.primary)
                }
                .tint(themeStore.settingsToggleTint(for: colorScheme))
                .accessibilityIdentifier("settingsToggle_celebrations")
            }

            Section("Tasks") {
                HStack {
                    Label("Recommended task limit", systemImage: "target")
                        .foregroundStyle(.primary)

                    Spacer()

                    Stepper(value: $recommendedWipLimit, in: 1 ... 7) {
                        Text("\(recommendedWipLimit)")
                            .font(themeStore.font(for: .bodyStrong))
                    }
                    .frame(width: 130)
                }
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationSettings.isEnabled)
                    .onChange(of: notificationSettings.isEnabled) { _, enabled in
                        if enabled {
                            _ = _Concurrency.Task {
                                await NotificationService.shared.requestAuthorization()
                            }
                        }
                    }

                Toggle("Task reminders", isOn: $notificationSettings.taskRemindersEnabled)
                    .disabled(!notificationSettings.isEnabled)

                Toggle("Daily digest", isOn: $notificationSettings.dailyDigestEnabled)
                    .disabled(!notificationSettings.isEnabled)

                if notificationSettings.dailyDigestEnabled {
                    DatePicker(
                        "Digest time",
                        selection: Binding(
                            get: { notificationSettings.reminderTime },
                            set: { notificationSettings.reminderTime = $0 }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                    .disabled(!notificationSettings.isEnabled)
                }

                Toggle("Notification sound", isOn: $notificationSettings.soundEnabled)
                    .disabled(!notificationSettings.isEnabled)
            }
            .tint(themeStore.settingsToggleTint(for: colorScheme))

            // MARK: - Sign Out

            Section {
                Button(role: .destructive) {
                    signOut()
                } label: {
                    HStack {
                        Spacer()
                        Text("Sign Out")
                        Spacer()
                    }
                }
            }
        }
        .environment(\.font, themeStore.font(for: .inlineTitle))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            NotificationService.shared.setSettingsStore(notificationSettings)
            await NotificationService.shared.checkAuthorizationStatus()
            await syncDailyDigest()
        }
        .onChange(of: notificationSettings.dailyDigestEnabled) { _, _ in
            _ = _Concurrency.Task {
                await syncDailyDigest()
            }
        }
        .onChange(of: notificationSettings.reminderTime) { _, _ in
            _ = _Concurrency.Task {
                await syncDailyDigest()
            }
        }
    }

    private func signOut() {
        _Concurrency.Task {
            await subscriptionManager.removeSubscriptions()
            householdStore.clearCurrentHousehold()
            userSession.clearCurrentHousehold()
            userSession.signOut()
        }
    }

    private func syncDailyDigest() async {
        if notificationSettings.isEnabled, notificationSettings.dailyDigestEnabled {
            let components = Calendar.current.dateComponents([.hour, .minute], from: notificationSettings.reminderTime)
            await NotificationService.shared.scheduleDailyDigest(
                at: components.hour ?? 8,
                minute: components.minute ?? 0
            )
        } else {
            NotificationService.shared.cancelDailyDigest()
        }
    }

    private var selectedFontScaleBinding: Binding<FontSizeScale> {
        switch themeStore.preset {
        case .paper:
            Binding(
                get: { themeStore.paperFontScale },
                set: { HapticManager.selection(); themeStore.paperFontScale = $0 }
            )
        case .retro:
            Binding(
                get: { themeStore.retroFontScale },
                set: { HapticManager.selection(); themeStore.retroFontScale = $0 }
            )
        case .system:
            Binding(
                get: { themeStore.systemFontScale },
                set: { HapticManager.selection(); themeStore.systemFontScale = $0 }
            )
        }
    }
}

// MARK: - Theme Miniatures Carousel

private struct ThemeMiniatureCarousel: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Binding var selectedTheme: UnifiedTheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(UnifiedTheme.allCases) { theme in
                    ThemeMiniatureCard(
                        theme: theme,
                        isSelected: selectedTheme == theme
                    ) {
                        selectedTheme = theme
                    }
                    .environmentObject(themeStore)
                }
            }
            .padding(.vertical, 2)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

private struct ThemeMiniatureCard: View {
    @EnvironmentObject private var themeStore: ThemeStore
    let theme: UnifiedTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ThemeMiniatureContent(theme: theme)
                    .frame(width: 85, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? themeStore.accentTabColor : Color.primary.opacity(0.12),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }

                Group {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(themeStore.accentTabColor)
                    } else {
                        Color.clear
                            .frame(width: 14, height: 14)
                    }
                }

                Text(theme.displayName)
                    .font(themeStore.font(for: .bodyStrong))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("themeMiniatureCard_\(theme.rawValue)")
    }
}

private struct ThemeMiniatureContent: View {
    let theme: UnifiedTheme

    var body: some View {
        ZStack {
            background
            miniatureRows
            themeSymbol
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var background: some View {
        switch theme {
        case .light:
            Color.white
        case .dark:
            Color.black
        case .auto:
            ZStack {
                AutoMiniatureHalfShape(isLeading: true)
                    .fill(Color.white)
                AutoMiniatureHalfShape(isLeading: false)
                    .fill(Color.black)
            }
        case .retro:
            Color(hex: "090A0E")
        case .paper:
            Color(hex: "F6EEDC")
        }
    }

    private var miniatureRows: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: 4)
                .fill(rowColor.opacity(0.9))
                .frame(width: 52, height: 10)
            RoundedRectangle(cornerRadius: 4)
                .fill(rowColor.opacity(0.72))
                .frame(width: 62, height: 10)
            RoundedRectangle(cornerRadius: 4)
                .fill(rowColor.opacity(0.6))
                .frame(width: 48, height: 10)
            RoundedRectangle(cornerRadius: 4)
                .fill(rowColor.opacity(0.48))
                .frame(width: 58, height: 10)
            Spacer()
        }
        .padding(10)
    }

    private var themeSymbol: some View {
        VStack {
            Spacer()
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(symbolColor)
                .padding(8)
                .background(
                    Circle()
                        .fill(symbolBackground)
                )
                .padding(.bottom, 10)
        }
    }

    private var rowColor: Color {
        switch theme {
        case .light:
            Color(hex: "D1D1D6")
        case .dark:
            Color(hex: "2C2C2E")
        case .auto:
            Color(hex: "8E8E93")
        case .retro:
            Color(hex: "2BFF88")
        case .paper:
            Color(hex: "8C6C42")
        }
    }

    private var symbolName: String {
        switch theme {
        case .light:
            "sun.max.fill"
        case .dark:
            "moon.fill"
        case .auto:
            "circle.lefthalf.filled"
        case .retro:
            "gamecontroller.fill"
        case .paper:
            "newspaper.fill"
        }
    }

    private var symbolColor: Color {
        switch theme {
        case .light:
            Color(hex: "6B6B70")
        case .dark:
            .white
        case .auto:
            .primary
        case .retro:
            Color(hex: "00FF66")
        case .paper:
            Color(hex: "6D4C2F")
        }
    }

    private var symbolBackground: Color {
        switch theme {
        case .light:
            Color.black.opacity(0.06)
        case .dark:
            Color.white.opacity(0.08)
        case .auto:
            Color.white.opacity(0.28)
        case .retro:
            Color(hex: "131A2B")
        case .paper:
            Color.white.opacity(0.52)
        }
    }
}

private struct AutoMiniatureHalfShape: Shape {
    let isLeading: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isLeading {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
