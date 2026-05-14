import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager
    @EnvironmentObject private var premiumSubscriptionManager: SubscriptionManager
    @EnvironmentObject private var shareAcceptanceCoordinator: ShareAcceptanceCoordinator
    @EnvironmentObject private var celebrationManager: CelebrationManager
    @EnvironmentObject private var developerModeState: DeveloperModeState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var notificationSettings = NotificationSettingsStore()
    @AppStorage("recommendedWipLimit") private var recommendedWipLimit = TaskStore.defaultRecommendedWipLimit

    // Hard reset state
    @State private var showHardResetConfirmation = false
    @State private var isPerformingHardReset = false

    // Delete account state
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountProgressMessage = "Deleting account..."
    @State private var deleteAccountErrorMessage: String?
    @State private var premiumFeaturePrompt: PremiumFeature?

    var body: some View {
        settingsContent
            .environment(\.font, themeStore.font(for: .inlineTitle))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                NotificationService.shared.setSettingsStore(notificationSettings)
                await NotificationService.shared.checkAuthorizationStatus()
                await syncNotificationSchedules()
                await premiumSubscriptionManager.refreshCustomerInfo()
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
            .alert("Hard Reset App?", isPresented: $showHardResetConfirmation) {
                Button("Maybe Later", role: .cancel) {}
                Button("Hard Reset", role: .destructive) {
                    HapticManager.warning()
                    performHardReset()
                }
            } message: {
                Text("This clears local cache, resets app state, and signs you out locally. Your iCloud household stays untouched.")
            }
            .alert("Delete Account?", isPresented: $showDeleteAccountConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    HapticManager.warning()
                    performDeleteAccount()
                }
            } message: {
                Text(deleteAccountMessageText)
            }
            .alert(
                "Delete Account Failed",
                isPresented: Binding(
                    get: { deleteAccountErrorMessage != nil },
                    set: { if !$0 { deleteAccountErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    deleteAccountErrorMessage = nil
                }
            } message: {
                Text(deleteAccountErrorMessage ?? "Unknown error")
            }
            .alert(
                premiumFeaturePrompt?.alertTitle ?? "Dwello Pro",
                isPresented: Binding(
                    get: { premiumFeaturePrompt != nil },
                    set: { if !$0 { premiumFeaturePrompt = nil } }
                )
            ) {
                Button("Upgrade") {
                    premiumSubscriptionManager.displayPaywall = true
                    premiumFeaturePrompt = nil
                }
                Button("Not Now", role: .cancel) {
                    premiumFeaturePrompt = nil
                }
            } message: {
                Text(premiumFeaturePrompt?.alertMessage ?? "")
            }
    }

    private var settingsContent: some View {
        List {
            appearanceSection
            fontScaleSection
            accentColorSection
            celebrationSection
            tasksSection
            notificationsSection
            deleteAccountSection
            signOutSection
            developerSection
        }
    }

    private var appearanceSection: some View {
        Section {
            ThemeMiniatureCarousel(selectedTheme: Binding(
                get: { themeStore.unifiedTheme },
                set: { newTheme in
                    HapticManager.selection()
                    guard PremiumAccessPolicy.canUseTheme(
                        newTheme,
                        isPremium: premiumSubscriptionManager.isPremium
                    ) else {
                        premiumFeaturePrompt = .premiumTheme
                        return
                    }
                    themeStore.unifiedTheme = newTheme
                }
            ))
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("Appearance")
        }
    }

    private var fontScaleSection: some View {
        Section {
            Picker("System Font Size", selection: selectedFontScaleBinding) {
                ForEach(FontSizeScale.allCases) { scale in
                    Text(scale.displayName)
                        .font(themeStore.font(for: .bodyStrong))
                        .tag(scale)
                }
            }
            .font(themeStore.font(for: .bodyStrong))
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
    }

    @ViewBuilder
    private var accentColorSection: some View {
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
                        tabTintButton(for: tint)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text("Accent Color")
            }
        }
    }

    private var celebrationSection: some View {
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
    }

    private var tasksSection: some View {
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
    }

    private var notificationsSection: some View {
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

            Toggle("Shared activity", isOn: $notificationSettings.sharedActivityEnabled)
                .disabled(!notificationSettings.isEnabled)

            if shouldShowReminderTimePicker {
                DatePicker(
                    "Default reminder time",
                    selection: Binding(
                        get: { notificationSettings.reminderTime },
                        set: { notificationSettings.reminderTime = $0 }
                    ),
                    displayedComponents: [.hourAndMinute]
                )
                .font(themeStore.font(for: .bodyStrong))
                .disabled(!notificationSettings.isEnabled)
            }

            Toggle("Notification sound", isOn: $notificationSettings.soundEnabled)
                .disabled(!notificationSettings.isEnabled)
        }
        .tint(themeStore.settingsToggleTint(for: colorScheme))
    }

    private var deleteAccountSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAccountConfirmation = true
            } label: {
                destructiveActionLabel(
                    title: "Delete Account",
                    isProcessing: isDeletingAccount,
                    processingTitle: deleteAccountProgressMessage
                )
            }
            .disabled(isDeletingAccount)
        } footer: {
            Text(deleteAccountFooterText)
                .font(themeStore.font(for: .bodySmall))
        }
    }

    private var signOutSection: some View {
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

    @ViewBuilder
    private var developerSection: some View {
        if developerModeState.isUnlocked {
            Section {
                Button(role: .destructive) {
                    showHardResetConfirmation = true
                } label: {
                    destructiveActionLabel(
                        title: "Hard Reset App",
                        isProcessing: isPerformingHardReset,
                        processingTitle: "Resetting app..."
                    )
                }
                .disabled(isPerformingHardReset)
            } header: {
                Label("Developer", systemImage: "hammer.fill")
                    .foregroundStyle(.orange)
            } footer: {
                Text("Clears local cache, app defaults, TipKit/tutorial progress, and signs out locally.")
                    .font(themeStore.font(for: .bodySmall))
            }
        }
    }

    private var shouldShowReminderTimePicker: Bool {
        notificationSettings.isEnabled &&
            (notificationSettings.taskRemindersEnabled || notificationSettings.dailyDigestEnabled)
    }

    private func tabTintButton(for tint: TabTintColor) -> some View {
        Button {
            HapticManager.selection()
            guard PremiumAccessPolicy.canUseAccentColor(
                tint,
                isPremium: premiumSubscriptionManager.isPremium
            ) else {
                premiumFeaturePrompt = .accentColor
                return
            }
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
                    .foregroundStyle(themeStore.tabTintColor == tint ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func destructiveActionLabel(
        title: String,
        isProcessing: Bool,
        processingTitle: String
    ) -> some View {
        HStack {
            Spacer()
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text(processingTitle)
            } else {
                Text(title)
            }
            Spacer()
        }
        .font(themeStore.font(for: .buttonLabel))
    }

    // MARK: - Private helpers

    private func signOut() {
        _Concurrency.Task {
            await premiumSubscriptionManager.prepareForSignOut()
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

    private func performHardReset() {
        guard !isPerformingHardReset else { return }
        isPerformingHardReset = true

        _Concurrency.Task { @MainActor in
            await premiumSubscriptionManager.prepareForSignOut()
            await LocalAppReset.performHardReset(
                modelContext: modelContext,
                userSession: userSession,
                householdStore: householdStore,
                onboardingState: onboardingState,
                subscriptionManager: subscriptionManager,
                shareAcceptanceCoordinator: shareAcceptanceCoordinator,
                celebrationManager: celebrationManager
            )
            premiumSubscriptionManager.refreshDeveloperPremiumOverride()
            isPerformingHardReset = false
        }
    }

    private func performDeleteAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        deleteAccountProgressMessage = "Deleting data from iCloud..."
        deleteAccountErrorMessage = nil

        _Concurrency.Task { @MainActor in
            if userSession.syncMode == .cloud, let userId = userSession.userId {
                let remoteResult = await householdStore.deleteAccountRemotely(userId: userId)
                switch remoteResult {
                case .success:
                    break
                case let .failure(message):
                    deleteAccountErrorMessage = "We couldn't delete your iCloud data yet. \(message)"
                    isDeletingAccount = false
                    deleteAccountProgressMessage = "Deleting account..."
                    return
                }
            }

            deleteAccountProgressMessage = "Clearing local app data..."
            await premiumSubscriptionManager.prepareForSignOut()
            await LocalAppReset.performHardReset(
                modelContext: modelContext,
                userSession: userSession,
                householdStore: householdStore,
                onboardingState: onboardingState,
                subscriptionManager: subscriptionManager,
                shareAcceptanceCoordinator: shareAcceptanceCoordinator,
                celebrationManager: celebrationManager
            )
            premiumSubscriptionManager.refreshDeveloperPremiumOverride()
            isDeletingAccount = false
            deleteAccountProgressMessage = "Deleting account..."
        }
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

    private var deleteAccountFooterText: String {
        if householdStore.currentHousehold?.ownerId == userSession.userId {
            return "You own this household. Deleting your account will permanently remove the entire household and all shared data for every member."
        }
        return "Deletes your personal Dwello data, removes you from the household, clears local app data, and signs you out. Your Apple ID is not affected."
    }

    private var deleteAccountMessageText: String {
        if householdStore.currentHousehold?.ownerId == userSession.userId {
            return "You are the owner of this household. Deleting your account will permanently delete the entire household, all tasks, shopping items, and ideas for ALL members. This action cannot be undone."
        }
        return "Deleting your account will remove you from this household and delete your personal data. The household will remain active for other members."
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
