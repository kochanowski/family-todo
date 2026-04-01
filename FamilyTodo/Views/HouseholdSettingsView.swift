import SwiftData
import SwiftUI

// swiftlint:disable file_length
struct ProfileView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var cloudKitDiagnostics: CloudKitDiagnosticsState
    @Environment(\.modelContext) private var modelContext

    @StateObject private var memberStore = MemberStore(householdId: nil)

    @State private var showEditProfile = false
    @State private var householdBeingEdited: Household?
    @State private var showInviteMember = false
    @State private var showLeaveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showDeleteMemberConfirmation = false
    @State private var memberToDelete: Member?
    @State private var actionErrorMessage: String?

    var body: some View {
        List {
            diagnosticsSection
            householdSection
            membersSection
            inviteSection
            actionsSection
        }
        .environment(\.font, themeStore.font(for: .inlineTitle))
        .navigationTitle("Household Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditProfile) {
            if let householdId = householdStore.currentHousehold?.id {
                NavigationStack {
                    EditProfileView(householdId: householdId, modelContext: modelContext)
                }
            }
        }
        .sheet(item: $householdBeingEdited, onDismiss: handleHouseholdEditDismiss) { household in
            NavigationStack {
                EditHouseholdView(household: household)
                    .id(household.id)
            }
        }
        .sheet(isPresented: $showInviteMember) {
            InviteMemberView()
                .environmentObject(householdStore)
                .environmentObject(cloudKitDiagnostics)
        }
        .sheet(isPresented: $showLeaveConfirmation) {
            AppConfirmationSheet(
                title: "Leave household?",
                message: "You will lose access until invited again.",
                primaryTitle: "Leave",
                primaryStyle: .destructive,
                onPrimary: leaveHousehold
            )
        }
        .sheet(isPresented: $showDeleteConfirmation) {
            AppConfirmationSheet(
                title: "Delete household permanently?",
                message: "This action removes members and shared data.",
                primaryTitle: "Delete",
                primaryStyle: .destructive,
                onPrimary: deleteHousehold
            )
        }
        .sheet(isPresented: $showDeleteMemberConfirmation) {
            if let member = memberToDelete {
                AppConfirmationSheet(
                    title: "Remove Member",
                    message: "Remove \(member.displayName) from this household?",
                    primaryTitle: "Remove",
                    primaryStyle: .destructive,
                    onPrimary: {
                        removeMember(member)
                    }
                )
            }
        }
        .alert("Action failed", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "Unknown error")
        }
        .task(id: householdStore.currentHousehold?.id) {
            memberStore.setModelContext(modelContext)
            memberStore.setSyncMode(userSession.syncMode)
            memberStore.setHousehold(householdStore.currentHousehold?.id)
            memberStore.setCloudContext(householdStore.currentSyncContext(userId: userSession.userId))
            await memberStore.loadMembers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memberProfileDidChange)) { notification in
            memberStore.markLocalSnapshotStale()
            if (notification.object as? String) == "local" {
                memberStore.rehydrateVisibleSnapshotFromCache()
            }
            _ = _Concurrency.Task {
                memberStore.setCloudContext(householdStore.currentSyncContext(userId: userSession.userId))
                await memberStore.loadMembers()
            }
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        if cloudKitDiagnostics.hasVisibleDiagnostics {
            Section {
                CloudKitDiagnosticsBanner()
                    .environmentObject(themeStore)
                    .environmentObject(cloudKitDiagnostics)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
            }
        }
    }

    private var householdSection: some View {
        Section {
            if let household = householdStore.currentHousehold {
                if currentUserIsOwner {
                    Button {
                        householdBeingEdited = household
                    } label: {
                        householdRow(household: household, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        householdRow(household: household, showsChevron: false)

                        Text("Only the household owner can edit the household name and icon.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No Household Selected")
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            }
        } header: {
            sectionHeader("Household")
        }
    }

    private func householdRow(household: Household, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: household.iconSymbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(themeStore.accentTabColor)
                .frame(width: 28, height: 28)
            Text(household.name)
                .font(themeStore.font(for: .listRowTitle))
                .foregroundStyle(themeStore.contentPrimaryColor)
            Spacer()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var membersSection: some View {
        Section {
            if activeMembers.isEmpty {
                Text("No members yet.")
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            } else {
                ForEach(activeMembers) { member in
                    if member.userId == userSession.userId {
                        Button {
                            showEditProfile = true
                        } label: {
                            memberRowContent(
                                member: member,
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 12) {
                            memberRowContent(
                                member: member,
                                showsChevron: false
                            )

                            if currentUserIsOwner {
                                Menu {
                                    Button(member.role == .owner ? "Change to Member" : "Make Owner") {
                                        toggleRole(for: member)
                                    }
                                    Button("Remove", role: .destructive) {
                                        memberToDelete = member
                                        showDeleteMemberConfirmation = true
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(themeStore.contentSecondaryColor)
                                        .frame(width: 28, height: 28)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
        } header: {
            sectionHeader("Members")
        }
    }

    @ViewBuilder
    private var inviteSection: some View {
        if householdStore.currentHousehold != nil {
            Section {
                Button {
                    showInviteMember = true
                } label: {
                    Label("Invite Member", systemImage: "person.crop.circle.badge.plus")
                        .font(themeStore.font(for: .bodyStrong))
                }
                .disabled(!canCreateInvite)

                if !currentUserIsOwner {
                    Text("Only the household owner can create invites.")
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                } else if userSession.syncMode != .cloud {
                    Text("Invites are available only when iCloud sync is enabled.")
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }
            } header: {
                sectionHeader("Invite")
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Leave Household", role: .destructive) {
                showLeaveConfirmation = true
            }
            .disabled(!canLeaveHousehold)

            if currentUserIsOwner {
                Button("Delete Household", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        } header: {
            sectionHeader("Actions")
        }
    }

    private var activeMembers: [Member] {
        memberStore.members
            .filter(\.isActive)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private var currentMember: Member? {
        memberStore.activeMember(for: userSession.userId)
    }

    private var currentUserIsOwner: Bool {
        currentMember?.role == .owner
    }

    private var canLeaveHousehold: Bool {
        guard householdStore.currentHousehold != nil, userSession.userId != nil else {
            return false
        }
        if userSession.syncMode == .localOnly {
            return false
        }
        guard let currentMember else {
            return false
        }

        let leaveResolution = householdStore.resolveLeaveBehavior(
            for: currentMember,
            activeMembers: activeMembers
        )
        return leaveResolution == .deactivateMembership
    }

    private var canCreateInvite: Bool {
        currentUserIsOwner && userSession.syncMode == .cloud
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(themeStore.font(for: .sectionHeader))
            .foregroundStyle(themeStore.contentSecondaryColor)
            .textCase(nil)
    }

    private func memberRowContent(
        member: Member,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 10) {
            (Text(member.displayName)
                + Text(member.userId == userSession.userId ? " (You)" : ""))
                .foregroundStyle(themeStore.contentPrimaryColor)
            Spacer()
            if member.role == .owner {
                Text("Owner")
                    .font(themeStore.font(for: .chip))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func toggleRole(for member: Member) {
        guard let userId = userSession.userId else { return }
        let newRole: Member.MemberRole = member.role == .owner ? .member : .owner
        _ = _Concurrency.Task {
            do {
                try await memberStore.updateRole(
                    id: member.id,
                    newRole: newRole,
                    currentUserId: userId
                )
                memberStore.setCloudContext(householdStore.currentSyncContext(userId: userSession.userId))
                await memberStore.loadMembers()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func removeMember(_ member: Member) {
        guard let userId = userSession.userId else { return }
        _ = _Concurrency.Task {
            do {
                try await memberStore.deleteMember(id: member.id, currentUserId: userId)
                memberToDelete = nil
                memberStore.setCloudContext(householdStore.currentSyncContext(userId: userSession.userId))
                await memberStore.loadMembers()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func leaveHousehold() {
        guard let userId = userSession.userId else {
            actionErrorMessage = "Session expired. Sign in again to manage household."
            return
        }
        _ = _Concurrency.Task {
            do {
                try await householdStore.leaveCurrentHousehold(
                    userId: userId,
                    activeMembersSnapshot: activeMembers
                )
                NotificationService.shared.cancelDailyDigest()
                NotificationService.shared.removeAllTaskReminders()
                userSession.clearCurrentHousehold()
                onboardingState.openHouseholdSetup()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteHousehold() {
        guard let userId = userSession.userId else {
            actionErrorMessage = "Session expired. Sign in again to manage household."
            return
        }
        _ = _Concurrency.Task {
            do {
                try await householdStore.deleteCurrentHousehold(requestedBy: userId)
                NotificationService.shared.cancelDailyDigest()
                NotificationService.shared.removeAllTaskReminders()
                userSession.clearCurrentHousehold()
                onboardingState.openHouseholdSetup()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func handleHouseholdEditDismiss() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .tabBarAppearanceRefreshRequested,
                object: nil
            )
        }
    }
}

private struct InviteMemberView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var inviteLoadGeneration = 0
    @State private var inviteToken: InviteToken?
    @State private var isLoadingInviteCode = true
    @State private var isInviteLoadTakingLongerThanExpected = false
    @State private var errorMessage: String?

    private static let inviteSlowLoadThresholdNanoseconds: UInt64 = 12_000_000_000

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(themeStore.accentTabColor)
                        .frame(width: 72, height: 72)
                        .background(
                            Circle()
                                .fill(themeStore.surfaceElevatedColor)
                        )

                    VStack(spacing: 10) {
                        Text("Invite Member")
                            .font(themeStore.font(for: .screenHeader))
                            .foregroundStyle(themeStore.contentPrimaryColor)
                            .multilineTextAlignment(.center)

                        Text("Share the 6-character invite code or let someone scan the QR code to join this household.")
                            .font(themeStore.font(for: .bodyStrong))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .multilineTextAlignment(.center)
                    }

                    if isLoadingInviteCode {
                        VStack(spacing: 12) {
                            ProgressView("Preparing invite code...")
                                .font(themeStore.font(for: .bodyStrong))

                            if isInviteLoadTakingLongerThanExpected {
                                Text(
                                    "The first invite can take a little longer while HousePulse finishes preparing iCloud sharing. Keep this screen open for a moment."
                                )
                                .font(themeStore.font(for: .bodySmall))
                                .foregroundStyle(themeStore.contentSecondaryColor)
                                .multilineTextAlignment(.center)
                            }
                        }
                    } else if let errorMessage {
                        ThemedEmptyStateView(
                            title: "Invite unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: errorMessage
                        )
                    } else if let inviteToken {
                        VStack(spacing: 18) {
                            InviteQRCodeCard(inviteCode: inviteToken.code)

                            VStack(spacing: 8) {
                                Text("Invite code")
                                    .font(themeStore.font(for: .bodySmall))
                                    .foregroundStyle(themeStore.contentSecondaryColor)
                                Text(inviteToken.code)
                                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                                    .foregroundStyle(themeStore.contentPrimaryColor)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(themeStore.surfaceElevatedColor)
                            )
                            .accessibilityElement(children: .combine)

                            ShareLink(item: shareText(for: inviteToken.code)) {
                                Label("Share Invite Code", systemImage: "square.and.arrow.up")
                                    .font(themeStore.font(for: .buttonLabel))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Text("The other person can scan the QR code or type the code into HousePulse to join.")
                                .font(themeStore.font(for: .bodySmall))
                                .foregroundStyle(themeStore.contentSecondaryColor)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(24)
                .appAdaptiveWidth(
                    maxWidth: AppChromeMetrics.regularFormMaxWidth,
                    alignment: .top
                )
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                }
                ToolbarItem(placement: .principal) {
                    Text("Invite Member")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
            }
            .task {
                await loadInviteCode()
            }
        }
    }

    @MainActor
    private func loadInviteCode() async {
        inviteLoadGeneration += 1
        let generation = inviteLoadGeneration
        isLoadingInviteCode = true
        isInviteLoadTakingLongerThanExpected = false
        inviteToken = nil
        errorMessage = nil

        let timeoutTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(nanoseconds: Self.inviteSlowLoadThresholdNanoseconds)
            guard !_Concurrency.Task.isCancelled,
                  inviteLoadGeneration == generation,
                  isLoadingInviteCode
            else {
                return
            }

            isInviteLoadTakingLongerThanExpected = true
        }
        defer { timeoutTask.cancel() }

        do {
            let token = try await householdStore.fetchOrCreateInviteToken()
            guard inviteLoadGeneration == generation else { return }
            inviteToken = token
            isInviteLoadTakingLongerThanExpected = false
            errorMessage = nil
        } catch {
            guard inviteLoadGeneration == generation else { return }
            inviteToken = nil
            isInviteLoadTakingLongerThanExpected = false
            errorMessage = inviteErrorMessage(for: error)
        }

        guard inviteLoadGeneration == generation else { return }
        isLoadingInviteCode = false
    }

    private func inviteErrorMessage(for error: Error) -> String {
        let localized = error.localizedDescription
        let reflected = String(describing: error)
        if reflected.isEmpty || reflected == localized {
            return localized
        }
        return "\(localized) | \(reflected)"
    }

    private func shareText(for inviteCode: String) -> String {
        "Join my household in HousePulse with code: \(inviteCode)"
    }
}

private struct EditProfileView: View {
    @StateObject private var memberStore: MemberStore

    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var selectedColorHex = MemberColorToken.fallbackHex
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let modelContext: ModelContext

    init(householdId: UUID, modelContext: ModelContext) {
        self.modelContext = modelContext
        _memberStore = StateObject(wrappedValue: MemberStore(householdId: householdId, modelContext: modelContext))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $displayName)
                    .font(themeStore.font(for: .bodyStrong))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
            } header: {
                Text("Display Name")
                    .font(themeStore.font(for: .sectionHeader))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    ForEach(MemberColorToken.allCases, id: \.self) { token in
                        let hex = token.hex
                        Button {
                            selectedColorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if selectedColorHex == hex {
                                        Circle()
                                            .stroke(Color.primary, lineWidth: 2)
                                            .padding(1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Profile Color")
                    .font(themeStore.font(for: .sectionHeader))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .font(themeStore.font(for: .buttonLabel))
            }
            ToolbarItem(placement: .principal) {
                Text("Edit Profile")
                    .font(themeStore.font(for: .inlineTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveProfile()
                } label: {
                    Text("Save")
                        .font(themeStore.font(for: .buttonLabel))
                }
                .disabled(
                    displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving
                )
            }
        }
        .alert("Save failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            memberStore.setModelContext(modelContext)
            memberStore.setSyncMode(userSession.syncMode)
            memberStore.setCloudContext(householdStore.currentSyncContext(userId: userSession.userId))
            hydrateInitialValues()
            await memberStore.loadMembersForDisplay()
            hydrateInitialValues()
        }
    }

    private func hydrateInitialValues() {
        guard let userId = userSession.userId else { return }
        if let currentMember = memberStore.members.first(where: { $0.userId == userId }) {
            displayName = currentMember.displayName
            selectedColorHex = currentMember.colorHex
            return
        }

        displayName = userSession.confirmedMembershipDisplayName ?? userSession.displayName ?? ""
        selectedColorHex = MemberColorToken.fallbackHex
    }

    private func saveProfile() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        do {
            _ = try DisplayNameValidator.validate(trimmedName)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard let currentUserId = userSession.userId else {
            errorMessage = "Session expired. Sign in again."
            return
        }

        isSaving = true
        _ = _Concurrency.Task {
            do {
                try await memberStore.updateCurrentUserProfile(
                    displayName: trimmedName,
                    colorHex: selectedColorHex,
                    currentUserId: currentUserId
                )
                await MainActor.run {
                    userSession.applyProfileUpdate(displayName: trimmedName)
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct EditHouseholdView: View {
    private struct HouseholdMetadataDraft: Equatable {
        var name: String
        var iconSymbol: String

        var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let household: Household

    private let initialDraft: HouseholdMetadataDraft
    @State private var draft: HouseholdMetadataDraft
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let iconOptions = [
        "house.fill",
        "building.2.fill",
        "star.fill",
        "heart.fill",
        "leaf.fill",
        "pawprint.fill",
        "sparkles",
        "cart.fill",
        "checklist",
        "fork.knife",
        "bed.double.fill",
        "figure.2.and.child.holdinghands",
        "sun.max.fill",
        "moon.stars.fill",
        "bolt.heart.fill",
    ]

    init(
        household: Household
    ) {
        self.household = household
        let initialDraft = HouseholdMetadataDraft(
            name: household.name,
            iconSymbol: household.iconSymbol
        )
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        Form {
            Section {
                TextField("Household name", text: $draft.name)
                    .font(themeStore.font(for: .bodyStrong))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
            } header: {
                Text("Household Name")
                    .font(themeStore.font(for: .sectionHeader))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            }

            Section {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                    spacing: 12
                ) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button {
                            draft.iconSymbol = icon
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        draft.iconSymbol == icon
                                            ? themeStore.accentTabColor.opacity(0.18)
                                            : Color.secondary.opacity(0.12)
                                    )
                                    .frame(width: 40, height: 40)
                                Image(systemName: icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(
                                        draft.iconSymbol == icon
                                            ? themeStore.foregroundOnAccent(
                                                for: themeStore.accentTabColor,
                                                colorScheme: colorScheme
                                            )
                                            : .primary
                                    )
                            }
                            .overlay {
                                if draft.iconSymbol == icon {
                                    Circle()
                                        .stroke(themeStore.accentTabColor, lineWidth: 2)
                                        .frame(width: 40, height: 40)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Household Icon")
                    .font(themeStore.font(for: .sectionHeader))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            }
        }
        .font(themeStore.font(for: .bodyStrong))
        .navigationTitle("Edit Household")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(themeStore.font(for: .buttonLabel))
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveHousehold()
                } label: {
                    Text("Save")
                        .font(themeStore.font(for: .buttonLabel))
                }
                .disabled(!canSave)
            }
            ToolbarItem(placement: .principal) {
                Text("Edit Household")
                    .font(themeStore.font(for: .inlineTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)
            }
        }
        .alert("Save failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var trimmedName: String {
        draft.trimmedName
    }

    private var hasChanges: Bool {
        trimmedName != initialDraft.trimmedName || draft.iconSymbol != initialDraft.iconSymbol
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && hasChanges && !isSaving
    }

    private func saveHousehold() {
        guard !trimmedName.isEmpty else { return }
        guard !isSaving else { return }
        guard let userId = userSession.userId else {
            errorMessage = "Session expired. Sign in again."
            return
        }

        isSaving = true
        _ = _Concurrency.Task { @MainActor in
            do {
                try await householdStore.updateCurrentHousehold(
                    name: trimmedName,
                    userId: userId,
                    iconSymbol: draft.iconSymbol
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

// swiftlint:enable file_length
