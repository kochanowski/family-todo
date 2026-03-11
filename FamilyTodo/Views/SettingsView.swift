import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager
    @Environment(\.modelContext) private var modelContext
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
                .controlSize(.large)
                .padding(.vertical, 6)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            } header: {
                Text("System Font Size")
            } footer: {
                if themeStore.isRetroFamily {
                    Text("Regular is the default font size.")
                }
            }

            // MARK: - Tab Color Section

            if !themeStore.isRetroFamily {
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
                                await syncNotificationSchedules()
                            }
                        }
                    }

                Toggle("Task reminders", isOn: $notificationSettings.taskRemindersEnabled)
                    .disabled(!notificationSettings.isEnabled)

                Toggle("Daily digest", isOn: $notificationSettings.dailyDigestEnabled)
                    .disabled(!notificationSettings.isEnabled)

                if notificationSettings.isEnabled,
                   notificationSettings.taskRemindersEnabled || notificationSettings.dailyDigestEnabled
                {
                    DatePicker(
                        "Default reminder time",
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
            await syncNotificationSchedules()
        }
        .onChange(of: notificationSettings.isEnabled) { _, _ in
            _ = _Concurrency.Task {
                await syncNotificationSchedules()
            }
        }
        .onChange(of: notificationSettings.taskRemindersEnabled) { _, _ in
            _ = _Concurrency.Task {
                await syncNotificationSchedules()
            }
        }
        .onChange(of: notificationSettings.dailyDigestEnabled) { _, _ in
            _ = _Concurrency.Task {
                await syncNotificationSchedules()
            }
        }
        .onChange(of: notificationSettings.reminderTime) { _, _ in
            _ = _Concurrency.Task {
                await syncNotificationSchedules()
            }
        }
        .onChange(of: notificationSettings.soundEnabled) { _, _ in
            _ = _Concurrency.Task {
                await syncNotificationSchedules()
            }
        }
    }

    private func signOut() {
        _Concurrency.Task {
            await subscriptionManager.removeSubscriptions()
            NotificationService.shared.cancelDailyDigest()
            NotificationService.shared.removeAllTaskReminders()
            householdStore.clearCurrentHousehold()
            userSession.clearCurrentHousehold()
            userSession.signOut()
        }
    }

    private func syncNotificationSchedules() async {
        await NotificationService.shared.refreshScheduledNotifications(
            householdId: userSession.currentHouseholdID ?? householdStore.currentHousehold?.id,
            modelContext: modelContext
        )
    }

    private var selectedFontScaleBinding: Binding<FontSizeScale> {
        switch themeStore.preset {
        case .paper:
            Binding(
                get: { themeStore.paperFontScale },
                set: { HapticManager.selection(); themeStore.paperFontScale = $0 }
            )
        case .retroDark, .retroLight:
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
    @EnvironmentObject private var themeStore: ThemeStore
    let theme: UnifiedTheme

    var body: some View {
        ZStack {
            background
            skeletonOverlay
            accentDot
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
        case .retroDark:
            Color(hex: "090A0E")
        case .retroLight:
            Color(hex: "E7DFC9")
        case .paper:
            Color(hex: "F6EEDC")
        }
    }

    @ViewBuilder
    private var skeletonOverlay: some View {
        switch theme {
        case .light:
            skeletonRows(
                headerColor: Color(hex: "E5E5EA"),
                lineColor: Color(hex: "D1D1D6")
            )
        case .dark:
            skeletonRows(
                headerColor: Color(hex: "2C2C2E"),
                lineColor: Color(hex: "3A3A3C")
            )
        case .auto:
            ZStack {
                skeletonRows(
                    headerColor: Color(hex: "E5E5EA"),
                    lineColor: Color(hex: "D1D1D6")
                )
                .mask(AutoMiniatureHalfShape(isLeading: true))

                skeletonRows(
                    headerColor: Color(hex: "2C2C2E"),
                    lineColor: Color(hex: "3A3A3C")
                )
                .mask(AutoMiniatureHalfShape(isLeading: false))
            }
        case .retroDark:
            skeletonRows(
                headerColor: Color(hex: "1D223A"),
                lineColor: Color(hex: "1E9E58")
            )
        case .retroLight:
            skeletonRows(
                headerColor: Color(hex: "FFF6E5"),
                lineColor: Color(hex: "4B4338")
            )
        case .paper:
            skeletonRows(
                headerColor: Color(hex: "B79263"),
                lineColor: Color(hex: "8C6C42")
            )
        }
    }

    private func skeletonRows(headerColor: Color, lineColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: 4)
                .fill(headerColor)
                .frame(height: 14)

            RoundedRectangle(cornerRadius: 3)
                .fill(lineColor.opacity(0.9))
                .frame(width: 56, height: 7)
            RoundedRectangle(cornerRadius: 3)
                .fill(lineColor.opacity(0.8))
                .frame(width: 63, height: 7)
            RoundedRectangle(cornerRadius: 3)
                .fill(lineColor.opacity(0.75))
                .frame(width: 48, height: 7)
            Spacer()
        }
        .padding(10)
    }

    private var accentDot: some View {
        let previewAccentColor: Color = switch theme {
        case .retroDark:
            AppColors.palette(for: .retroDark).accent
        case .retroLight:
            AppColors.palette(for: .retroLight).accent
        case .light, .dark, .auto, .paper:
            themeStore.tabTintColor.color
        }

        return VStack {
            Spacer()
            HStack {
                Spacer()
                Circle()
                    .fill(previewAccentColor)
                    .frame(width: 9, height: 9)
                    .overlay {
                        Circle()
                            .stroke(
                                Color.black.opacity(theme == .dark || theme == .retroDark ? 0.35 : 0.22),
                                lineWidth: 0.6
                            )
                    }
            }
        }
        .padding(10)
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
