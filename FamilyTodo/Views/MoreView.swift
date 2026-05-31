import Foundation
import SwiftData
import SwiftUI
import UIKit

/// More screen - hub for settings, profile, and configuration
struct MoreView: View {
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var premiumSubscriptionManager: SubscriptionManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                .padding(.top, AppChromeMetrics.screenHeaderTopPadding)
                .padding(.bottom, AppChromeMetrics.screenHeaderBottomPadding)

            // Menu items
            ScrollView {
                VStack(spacing: 16) {
                    premiumStatusBanner

                    // Household hero card
                    NavigationLink {
                        ProfileView()
                    } label: {
                        HouseholdHeroCard()
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        HapticManager.lightTap()
                    })

                    if userSession.isGuest {
                        GuestUpgradeBanner {
                            userSession.endGuestSession()
                            onboardingState.openAuth()
                        }
                    }

                    // Settings group
                    VStack(spacing: 0) {
                        NavigationLink {
                            if let householdId = userSession.currentHouseholdID {
                                CategoriesManagementView(householdId: householdId, modelContext: modelContext)
                            } else {
                                GuidedEmptyStateView()
                            }
                        } label: {
                            MoreRow(icon: "folder", title: "Idea Categories")
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            HapticManager.lightTap()
                        })

                        Divider()
                            .padding(.leading, 52)

                        NavigationLink {
                            SettingsView()
                        } label: {
                            MoreRow(icon: "gear", title: "Settings")
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            HapticManager.lightTap()
                        })
                        .accessibilityIdentifier("Settings")
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(cardBackground)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Spacer()
        }
        .appAdaptiveWidth(
            maxWidth: AppChromeMetrics.regularContentMaxWidth,
            alignment: .topLeading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await premiumSubscriptionManager.refreshCustomerInfo()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("More")
                .font(themeStore.font(for: .screenHeader))
                .foregroundStyle(themeStore.contentPrimaryColor)

            Spacer()
        }
    }

    private var cardBackground: Color {
        themeStore.surfaceColor
    }

    private var premiumStatusBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: premiumSubscriptionManager.isPremium ? "crown.fill" : "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))

                VStack(alignment: .leading, spacing: 3) {
                    Text(premiumSubscriptionManager.isPremium ? "Dwello Pro Active" : "Dwello Pro")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(.white)

                    Text(premiumBannerSubtitle)
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer(minLength: 8)
            }

            if premiumSubscriptionManager.isPremium {
                Button {
                    HapticManager.lightTap()
                    premiumSubscriptionManager.displayCustomerCenter = true
                } label: {
                    Text("Manage Subscription")
                        .frame(maxWidth: .infinity)
                }
                .font(themeStore.font(for: .buttonLabel))
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.2))
                .foregroundStyle(.white)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: premiumBannerGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
        }
    }

    private var premiumBannerSubtitle: String {
        if premiumSubscriptionManager.developerPremiumOverride {
            return "Developer mode currently grants premium access."
        }
        if premiumSubscriptionManager.hasRevenueCatEntitlement || premiumSubscriptionManager.hasHouseholdPremium {
            return "Your premium benefits are active for this household."
        }
        if premiumSubscriptionManager.isInGracePeriod {
            return "You're in your 14-day free trial. Explore everything Dwello has to offer."
        }
        return "Your trial has ended. Upgrade to keep premium features."
    }

    private var premiumBannerGradientColors: [Color] {
        if premiumSubscriptionManager.isPremium {
            return [
                themeStore.accentTabColor.opacity(0.78),
                themeStore.accentTabColor.opacity(0.56),
            ]
        }

        return [
            themeStore.accentTabColor,
            themeStore.accentTabColor.opacity(0.72),
            Color(hex: "C89A2B"),
        ]
    }
}

// MARK: - Household Hero

struct HouseholdHeroCard: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession
    @Query(sort: \CachedMember.joinedAt) private var cachedMembers: [CachedMember]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: householdStore.currentHousehold?.iconSymbol ?? "house.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(householdColor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(householdStore.currentHousehold?.name ?? "Domownicy")
                    .font(themeStore.font(for: .inlineTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                    .lineLimit(1)

                Text(membersLine)
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(themeStore.contentSecondaryColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        }
        .contentShape(Rectangle())
    }

    private var cardBackground: Color {
        themeStore.surfaceColor
    }

    private var householdColor: Color {
        themeStore.accentTabColor
    }

    private var membersLine: String {
        guard let householdId = householdStore.currentHousehold?.id else {
            return userSession.displayName ?? "Tap to configure household"
        }

        let names = cachedMembers
            .filter { $0.householdId == householdId && $0.isActive }
            .map(\.displayName)
            .sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }

        guard !names.isEmpty else {
            return userSession.displayName ?? "No members yet"
        }

        let previewNames = names.prefix(3)
        let preview = previewNames.joined(separator: ", ")
        let remaining = names.count - previewNames.count
        return remaining > 0 ? "\(preview) +\(remaining)" : preview
    }
}

struct GuestUpgradeBanner: View {
    @EnvironmentObject private var themeStore: ThemeStore
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unlock syncing & sharing")
                .font(themeStore.font(for: .inlineTitle))
                .foregroundStyle(themeStore.contentPrimaryColor)

            Text("Sign in with Apple to join households, invite members, and keep devices in sync.")
                .font(themeStore.font(for: .bodySmall))
                .foregroundStyle(themeStore.contentSecondaryColor)

            Button("Sign in with Apple", action: onUpgrade)
                .font(themeStore.font(for: .buttonLabel))
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeStore.surfaceColor)
        )
    }
}

// MARK: - More Row Component

/// Standardized row for More menu items to ensure consistent icon sizing and styling.
struct MoreRow: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(themeStore.font(for: .inlineTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                if let subtitle {
                    Text(subtitle)
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Sub-screens

struct CategoriesManagementView: View {
    @StateObject private var store: BacklogStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var premiumSubscriptionManager: SubscriptionManager
    @State private var selectedCategory: BacklogCategory?
    @State private var isAddingCategory = false
    @State private var newCategoryColorHex = MemberColorToken.randomHex()
    @State private var editMode: EditMode = .inactive
    @State private var categoryDeletionBlockReason: BacklogStore.CategoryDeletionBlockReason?

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext))
    }

    var body: some View {
        List {
            ForEach(store.categories) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 10, height: 10)
                        Text(category.title)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        HapticManager.warning()
                        _ = _Concurrency.Task {
                            let result = await store.deleteCategory(category)
                            if case let .blocked(reason) = result {
                                await MainActor.run {
                                    categoryDeletionBlockReason = reason
                                }
                            }
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove { source, destination in
                var reordered = store.categories
                reordered.move(fromOffsets: source, toOffset: destination)
                let orderedIds = reordered.map(\.id)
                _ = _Concurrency.Task {
                    await store.reorderCategories(orderedIds: orderedIds)
                }
            }

            Section {
                Button {
                    guard canCreateCategory else {
                        HapticManager.lightTap()
                        premiumSubscriptionManager.presentUpsell(.backlogCategoryLimit)
                        return
                    }
                    HapticManager.lightTap()
                    newCategoryColorHex = MemberColorToken.randomHex()
                    isAddingCategory = true
                } label: {
                    HStack(spacing: 8) {
                        Label("New category", systemImage: "plus.circle")
                        if isAtFreeCategoryLimit {
                            ProBadgeView(size: .inline)
                        }
                    }
                }
            }
        }
        .environment(\.font, themeStore.font(for: .inlineTitle))
        .environment(\.editMode, $editMode)
        .navigationTitle("Idea Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Idea Categories")
                    .font(themeStore.font(for: .inlineTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Done" : "Reorder") {
                    HapticManager.lightTap()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }
                .font(themeStore.font(for: .buttonLabel))
            }
        }
        .alert(
            "Cannot delete category.",
            isPresented: Binding(
                get: { categoryDeletionBlockReason != nil },
                set: { if !$0 { categoryDeletionBlockReason = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                categoryDeletionBlockReason = nil
            }
        } message: {
            Text(categoryDeletionBlockReason?.alertDetail ?? "")
        }
        .task {
            store.setCloudContext(householdStore.currentSyncContext(userId: userSession.userId))
            store.setSyncMode(userSession.syncMode)
            await store.loadData()
        }
        .sheet(item: $selectedCategory) { category in
            CategoryEditorSheet(
                title: "Edit Category",
                initialName: category.title,
                initialColorHex: category.colorHex,
                primaryTitle: "Save",
                onCancel: {},
                onSubmit: { name, colorHex in
                    _ = _Concurrency.Task {
                        await store.updateCategory(
                            category,
                            newTitle: name,
                            newColorHex: colorHex
                        )
                    }
                }
            )
        }
        .sheet(isPresented: $isAddingCategory) {
            CategoryEditorSheet(
                title: "New Category",
                initialName: "",
                initialColorHex: newCategoryColorHex,
                primaryTitle: "Create",
                onCancel: {
                    newCategoryColorHex = MemberColorToken.randomHex()
                },
                onSubmit: { name, colorHex in
                    newCategoryColorHex = MemberColorToken.randomHex()
                    _ = _Concurrency.Task {
                        let result = await store.addCategory(
                            name,
                            colorHex: colorHex,
                            isPremium: premiumSubscriptionManager.isPremium
                        )
                        if case let .blocked(feature) = result {
                            premiumSubscriptionManager.presentUpsell(UpsellContext(feature: feature))
                        }
                    }
                }
            )
        }
    }

    private var canCreateCategory: Bool {
        PremiumAccessPolicy.canCreateBacklogCategory(
            currentCount: store.categories.count,
            isPremium: premiumSubscriptionManager.isPremium
        )
    }

    private var isAtFreeCategoryLimit: Bool {
        !premiumSubscriptionManager.isPremium &&
            !PremiumAccessPolicy.canCreateBacklogCategory(
                currentCount: store.categories.count,
                isPremium: false
            )
    }
}

struct CompletedTasksView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                CompletedTasksContent(householdId: householdId, modelContext: modelContext)
            } else {
                ThemedEmptyStateView(
                    title: "No Household",
                    systemImage: "house",
                    description: "Join or create a household to see task history."
                )
            }
        }
    }
}

private struct CompletedTasksContent: View {
    private enum CleanupAction: String, Identifiable {
        case clearAll
        case keepLast7Days
        case keepLast30Days

        var id: String {
            rawValue
        }
    }

    @StateObject private var store: TaskStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var pendingCleanup: CleanupAction?

    init(householdId: UUID, modelContext: ModelContext) {
        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(householdId)
        _store = StateObject(wrappedValue: taskStore)
    }

    var body: some View {
        Group {
            if store.archivedDoneTasks.isEmpty {
                ThemedEmptyStateView(
                    title: "No Task History",
                    systemImage: "checkmark.circle",
                    description: "Completed tasks older than 24h appear here."
                )
            } else {
                List {
                    ForEach(store.archivedDoneTasks) { task in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(task.title)
                                .font(themeStore.font(for: .listRowTitle))
                                .strikethrough(true)
                                .foregroundStyle(.secondary)

                            if let notes = task.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(themeStore.font(for: .bodySmall))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }

                            if let completedAt = task.completedAt {
                                Text(completedAt, style: .relative)
                                    .font(themeStore.font(for: .chip))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .environment(\.font, themeStore.font(for: .inlineTitle))
        .navigationTitle("Task History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !store.archivedDoneTasks.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            pendingCleanup = .clearAll
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }

                        Button {
                            pendingCleanup = .keepLast7Days
                        } label: {
                            Label("Keep Last 7 Days", systemImage: "calendar")
                        }

                        Button {
                            pendingCleanup = .keepLast30Days
                        } label: {
                            Label("Keep Last 30 Days", systemImage: "calendar.badge.clock")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17))
                    }
                }
            }
        }
        .sheet(item: $pendingCleanup) { action in
            AppConfirmationSheet(
                title: "Task History Cleanup",
                message: cleanupMessage(for: action),
                primaryTitle: cleanupPrimaryTitle(for: action),
                primaryStyle: action == .clearAll ? .destructive : .accent,
                onPrimary: {
                    runCleanupAction(action)
                }
            )
        }
        .task {
            store.setCloudContext(householdStore.currentSyncContext(userId: userSession.userId))
            store.setSyncMode(userSession.syncMode)
            await store.loadTasks()
        }
    }

    private func runCleanupAction(_ action: CleanupAction) {
        pendingCleanup = nil
        _ = _Concurrency.Task {
            switch action {
            case .clearAll:
                await store.clearArchivedTasks(keepingDays: nil)
            case .keepLast7Days:
                await store.clearArchivedTasks(keepingDays: 7)
            case .keepLast30Days:
                await store.clearArchivedTasks(keepingDays: 30)
            }
        }
    }

    private func cleanupPrimaryTitle(for action: CleanupAction) -> String {
        switch action {
        case .clearAll:
            "Clear All"
        case .keepLast7Days:
            "Keep Last 7 Days"
        case .keepLast30Days:
            "Keep Last 30 Days"
        }
    }

    private func cleanupMessage(for action: CleanupAction) -> String {
        switch action {
        case .clearAll:
            "This permanently removes all items from Task History."
        case .keepLast7Days:
            "This removes history older than 7 days."
        case .keepLast30Days:
            "This removes history older than 30 days."
        }
    }
}

#Preview {
    MoreView()
        .environmentObject(UserSession.shared)
        .environmentObject(HouseholdStore())
        .environmentObject(OnboardingState())
        .environmentObject(ThemeStore())
        .environmentObject(SubscriptionManager())
}
