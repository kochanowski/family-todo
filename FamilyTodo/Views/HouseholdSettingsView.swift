import CloudKit
import SwiftData
import SwiftUI

@MainActor
final class HouseholdSettingsUIState: ObservableObject {
    enum Route: Identifiable {
        case shareInvite(share: CKShare, container: CKContainer)
        case inviteQR

        var id: String {
            switch self {
            case let .shareInvite(share, _):
                "share-\(share.recordID.recordName)"
            case .inviteQR:
                "invite-qr"
            }
        }
    }

    @Published var route: Route?
}

struct ProfileView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var cloudKitDiagnostics: CloudKitDiagnosticsState
    @Environment(\.modelContext) private var modelContext

    @StateObject private var memberStore = MemberStore(householdId: nil)
    @StateObject private var uiState = HouseholdSettingsUIState()

    @State private var showEditProfile = false
    @State private var showEditHousehold = false
    @State private var isPreparingShareInvite = false
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
        .sheet(isPresented: $showEditHousehold) {
            if let household = householdStore.currentHousehold {
                NavigationStack {
                    EditHouseholdView(household: household)
                }
            }
        }
        .sheet(item: $uiState.route) { route in
            switch route {
            case let .shareInvite(share, container):
                ShareInviteView(share: share, container: container)
            case .inviteQR:
                InviteQRCodeView()
                    .environmentObject(householdStore)
            }
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
            await memberStore.loadMembers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memberProfileDidChange)) { _ in
            _ = _Concurrency.Task {
                await memberStore.loadMembers()
            }
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        if cloudKitDiagnostics.lastCloudKitError != nil {
            Section {
                CloudKitDiagnosticsBanner()
                    .environmentObject(cloudKitDiagnostics)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
            }
        }
    }

    private var householdSection: some View {
        Section("Household") {
            if let household = householdStore.currentHousehold {
                Button {
                    showEditHousehold = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: household.iconSymbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(household.name)
                                .foregroundStyle(themeStore.contentPrimaryColor)
                            Text("Name")
                                .font(themeStore.font(for: .bodySmall))
                                .foregroundStyle(themeStore.contentSecondaryColor)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("No Household Selected")
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            }
        }
    }

    @ViewBuilder
    private var membersSection: some View {
        Section("Members") {
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
                                roleLabel: member.role == .owner ? "Owner" : "Member",
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 12) {
                            memberRowContent(
                                member: member,
                                roleLabel: member.role == .owner ? "Owner" : "Member",
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
        }
    }

    @ViewBuilder
    private var inviteSection: some View {
        if householdStore.currentHousehold != nil {
            Section("Invite") {
                Button {
                    _ = _Concurrency.Task { await prepareShareInvite() }
                } label: {
                    if isPreparingShareInvite {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Preparing invite...")
                        }
                    } else {
                        Label("Invite Member", systemImage: "person.crop.circle.badge.plus")
                    }
                }
                .disabled(isPreparingShareInvite || !currentUserIsOwner)

                Button {
                    uiState.route = .inviteQR
                } label: {
                    Label("Show Invite QR", systemImage: "qrcode")
                }
                .disabled(isPreparingShareInvite || !currentUserIsOwner)

                if !currentUserIsOwner {
                    Text("Only the household owner can create invites.")
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            Button("Leave Household", role: .destructive) {
                showLeaveConfirmation = true
            }
            .disabled(householdStore.currentHousehold == nil || userSession.userId == nil)

            if currentUserIsOwner {
                Button("Delete Household", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
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

    private func memberRowContent(
        member: Member,
        roleLabel: String,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 12) {
            MemberBadgeView(name: member.displayName, colorHex: member.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                (Text(member.displayName)
                    + Text(member.userId == userSession.userId ? " (You)" : ""))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                Text(roleLabel)
                    .font(themeStore.font(for: .chip))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
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
                await memberStore.loadMembers()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func prepareShareInvite() async {
        guard !isPreparingShareInvite else { return }
        isPreparingShareInvite = true
        defer { isPreparingShareInvite = false }

        do {
            let (share, container) = try await householdStore.createShare()
            _ = try? await householdStore.fetchOrCreateInviteCode()
            uiState.route = .shareInvite(share: share, container: container)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func leaveHousehold() {
        guard let userId = userSession.userId else {
            actionErrorMessage = "Session expired. Sign in again to manage household."
            return
        }
        _ = _Concurrency.Task {
            do {
                try await householdStore.leaveCurrentHousehold(userId: userId)
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
                userSession.clearCurrentHousehold()
                onboardingState.openHouseholdSetup()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct EditProfileView: View {
    @StateObject private var memberStore: MemberStore

    @EnvironmentObject private var userSession: UserSession
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
            Section("Display Name") {
                TextField("Display name", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
            }

            Section("Profile Color") {
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
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveProfile()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            await memberStore.loadMembers()
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

        displayName = userSession.displayName ?? ""
        selectedColorHex = MemberColorToken.fallbackHex
    }

    private func saveProfile() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isSaving = true
        _ = _Concurrency.Task {
            do {
                try await memberStore.updateCurrentUserProfile(
                    displayName: trimmedName,
                    colorHex: selectedColorHex,
                    currentUserId: userSession.userId
                )
                userSession.applyProfileUpdate(displayName: trimmedName)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct EditHouseholdView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.dismiss) private var dismiss

    let household: Household

    @State private var name: String
    @State private var selectedIconSymbol: String
    @State private var isSaving = false
    @State private var errorMessage: String?

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

    init(household: Household) {
        self.household = household
        _name = State(initialValue: household.name)
        _selectedIconSymbol = State(initialValue: household.iconSymbol)
    }

    var body: some View {
        Form {
            Section("Household Name") {
                TextField("Household name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
            }

            Section("Household Icon") {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                    spacing: 12
                ) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button {
                            selectedIconSymbol = icon
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        selectedIconSymbol == icon
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.secondary.opacity(0.12)
                                    )
                                    .frame(width: 40, height: 40)
                                Image(systemName: icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            .overlay {
                                if selectedIconSymbol == icon {
                                    Circle()
                                        .stroke(Color.accentColor, lineWidth: 2)
                                        .frame(width: 40, height: 40)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Edit Household")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveHousehold()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func saveHousehold() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let userId = userSession.userId else {
            errorMessage = "Session expired. Sign in again."
            return
        }

        isSaving = true
        _ = _Concurrency.Task {
            do {
                try await householdStore.updateCurrentHousehold(
                    name: trimmedName,
                    userId: userId,
                    iconSymbol: selectedIconSymbol
                )
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
