import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager
    @StateObject private var notificationSettings = NotificationSettingsStore()
    @AppStorage("recommendedWipLimit") private var recommendedWipLimit = TaskStore.defaultRecommendedWipLimit

    var body: some View {
        List {
            // MARK: - Theme + Appearance Section

            Section {
                UnifiedThemeSelector(selectedTheme: Binding(
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

            if themeStore.preset == .paper {
                Section {
                    Picker("Font Style", selection: Binding(
                        get: { themeStore.paperVariant },
                        set: { HapticManager.selection(); themeStore.paperVariant = $0 }
                    )) {
                        ForEach(PaperVariant.allCases) { variant in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(variant.displayName)
                                Text(variant.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(variant)
                        }
                    }
                    .pickerStyle(.inline)

                    FontScaleSelector(
                        selectedScale: Binding(
                            get: { themeStore.paperFontScale },
                            set: { HapticManager.selection(); themeStore.paperFontScale = $0 }
                        )
                    )
                } header: {
                    Text("Paper Font")
                }
            } else if themeStore.preset == .retro {
                Section {
                    Picker("Font Style", selection: Binding(
                        get: { themeStore.retroVariant },
                        set: { HapticManager.selection(); themeStore.retroVariant = $0 }
                    )) {
                        ForEach(RetroVariant.allCases) { variant in
                            Text(variant.displayName).tag(variant)
                        }
                    }
                    .pickerStyle(.inline)

                    FontScaleSelector(
                        selectedScale: Binding(
                            get: { themeStore.retroFontScale },
                            set: { HapticManager.selection(); themeStore.retroFontScale = $0 }
                        )
                    )
                } header: {
                    Text("Retro Font")
                } footer: {
                    Text("Regular is the default font size.")
                }
            } else if themeStore.preset == .system {
                Section {
                    FontScaleSelector(
                        selectedScale: Binding(
                            get: { themeStore.systemFontScale },
                            set: { HapticManager.selection(); themeStore.systemFontScale = $0 }
                        ),
                        showSelectionPill: false,
                        showBorder: false
                    )
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeStore.surfaceColor)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("System Font Size")
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
}

// MARK: - Unified Theme Selector

private struct UnifiedThemeSelector: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Binding var selectedTheme: UnifiedTheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(UnifiedTheme.allCases) { theme in
                UnifiedThemeCard(
                    theme: theme,
                    isSelected: selectedTheme == theme
                ) {
                    selectedTheme = theme
                }
                .environmentObject(themeStore)
            }
        }
    }
}

private struct UnifiedThemeCard: View {
    @EnvironmentObject private var themeStore: ThemeStore
    let theme: UnifiedTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(swatchGradient)
                        .frame(maxWidth: .infinity, minHeight: 64)
                    themeIcon
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 3 : 1)
                )

                Text(theme.displayName)
                    .font(themeStore.font(for: .bodyStrong))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var swatchGradient: LinearGradient {
        let colors: [Color] = switch theme {
        case .light:
            [Color(hex: "FFFFFF"), Color(hex: "F5F5F5")]
        case .dark:
            [Color(hex: "1C1C1E"), Color(hex: "2C2C2E")]
        case .auto:
            [Color(hex: "D1D1D6"), Color(hex: "D1D1D6")]
        case .light2:
            [Color(hex: "FFFFFF"), Color(hex: "FFFFFF")]
        case .dark2:
            [Color(hex: "000000"), Color(hex: "000000")]
        case .retro:
            [Color(hex: "0F0F23"), Color(hex: "1A1A3E")]
        case .paper:
            [Color(hex: "FFF8E7"), Color(hex: "F0E6CE")]
        }
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var themeIcon: some View {
        if theme == .auto {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 26, weight: .regular))
                .rotationEffect(.degrees(-45))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black.opacity(0.8), .white.opacity(0.9))
        } else {
            Image(systemName: theme.iconName)
                .font(.system(size: 24))
                .foregroundStyle(iconColor)
        }
    }

    private var iconColor: Color {
        switch theme {
        case .light:
            Color(hex: "666666")
        case .dark:
            .white
        case .auto:
            .primary
        case .light2:
            Color(hex: "5A5A5A")
        case .dark2:
            .white
        case .retro:
            Color(hex: "00FF41")
        case .paper:
            Color(hex: "8B4513")
        }
    }
}

private struct FontScaleSelector: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Binding var selectedScale: FontSizeScale
    var showSelectionPill = true
    var showBorder = true
    @Namespace private var selectorNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FontSizeScale.allCases) { scale in
                Button {
                    selectedScale = scale
                } label: {
                    Text(scale.displayName)
                        .font(themeStore.font(for: .filterLabel))
                        .foregroundStyle(selectedScale == scale ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selectedScale == scale, showSelectionPill {
                                Capsule()
                                    .fill(themeStore.surfaceColor)
                                    .matchedGeometryEffect(
                                        id: "font_scale_indicator",
                                        in: selectorNamespace
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(themeStore.surfaceElevatedColor)
                .overlay {
                    if showBorder {
                        Capsule()
                            .stroke(themeStore.borderLightColor.opacity(0.45), lineWidth: 1)
                    }
                }
        )
    }
}
