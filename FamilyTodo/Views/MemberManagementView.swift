import SwiftData
import SwiftUI

struct MemberManagementView: View {
    @StateObject private var memberStore: MemberStore
    @EnvironmentObject var householdStore: HouseholdStore
    @EnvironmentObject var userSession: UserSession
    @EnvironmentObject private var cloudKitDiagnostics: CloudKitDiagnosticsState
    @Environment(\.modelContext) private var modelContext

    init(householdId: UUID) {
        _memberStore = StateObject(wrappedValue: MemberStore(householdId: householdId))
    }

    @State private var editingMember: Member?
    @State private var newDisplayName = ""
    @State private var showEditNameAlert = false
    @State private var showDeleteConfirmation = false
    @State private var memberToDelete: Member?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showShareInvite = false
    @State private var showInviteQR = false

    private var currentUserIsOwner: Bool {
        guard let userId = userSession.userId else { return false }
        return memberStore.members.first(where: { $0.userId == userId })?.role == .owner
    }

    private func isCurrentUser(_ member: Member) -> Bool {
        member.id == memberStore.members.first(where: { $0.userId == userSession.userId })?.id
    }

    var body: some View {
        NavigationStack {
            listContent
                .navigationTitle("Household Members")
                .sheet(isPresented: $showEditNameAlert) {
                    AppPromptSheet(
                        title: "Edit Name",
                        placeholder: "Display Name",
                        text: $newDisplayName,
                        primaryTitle: "Save",
                        onSubmit: { _ in
                            _Concurrency.Task { await saveName() }
                        }
                    )
                }
                .sheet(isPresented: $showDeleteConfirmation) {
                    if let member = memberToDelete {
                        AppConfirmationSheet(
                            title: "Remove Member",
                            message: "Are you sure you want to remove \(member.displayName)? This cannot be undone.",
                            primaryTitle: "Remove",
                            primaryStyle: .destructive,
                            onPrimary: {
                                _Concurrency.Task { await deleteMember() }
                            }
                        )
                    }
                }
                .alert("Error", isPresented: $showErrorAlert) {
                    Button("OK") {}
                } message: {
                    Text(errorMessage)
                }
        }
        .task {
            memberStore.setModelContext(modelContext)
            memberStore.setSyncMode(userSession.syncMode)
            await memberStore.loadMembers()
        }
    }

    // MARK: - Subviews

    private var listContent: some View {
        List {
            diagnosticsSection
            membersSection
            inviteSection
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

    private var membersSection: some View {
        Section("Members") {
            ForEach(memberStore.members) { member in
                MemberManagementRow(
                    member: member,
                    isCurrentUser: isCurrentUser(member),
                    currentUserIsOwner: currentUserIsOwner,
                    onEditName: { editName(member) },
                    onChangeRole: { changeRole(member: member) },
                    onDelete: { confirmDelete(member) }
                )
            }
        }
    }

    @ViewBuilder
    private var inviteSection: some View {
        if currentUserIsOwner, householdStore.currentHousehold != nil {
            Section("Invite New Members") {
                Button {
                    showShareInvite = true
                } label: {
                    Label("Invite Member", systemImage: "person.badge.plus")
                }

                Button {
                    showInviteQR = true
                } label: {
                    Label("Show Invite QR", systemImage: "qrcode")
                }
            }
            .sheet(isPresented: $showShareInvite) {
                ShareInviteView(isPresented: $showShareInvite)
                    .environmentObject(householdStore)
            }
            .sheet(isPresented: $showInviteQR) {
                InviteQRCodeView()
                    .environmentObject(householdStore)
            }
        }
    }

    // MARK: - Actions

    private func editName(_ member: Member) {
        editingMember = member
        newDisplayName = member.displayName
        showEditNameAlert = true
    }

    private func confirmDelete(_ member: Member) {
        memberToDelete = member
        showDeleteConfirmation = true
    }

    private func saveName() async {
        guard let member = editingMember else { return }

        do {
            try await memberStore.updateMember(
                id: member.id,
                displayName: newDisplayName,
                currentUserId: userSession.userId
            )
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func changeRole(member: Member) {
        let newRole: Member.MemberRole = member.role == .owner ? .member : .owner

        _Concurrency.Task {
            do {
                try await memberStore.updateRole(
                    id: member.id,
                    newRole: newRole,
                    currentUserId: userSession.userId
                )
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func deleteMember() async {
        guard let member = memberToDelete else { return }

        do {
            try await memberStore.deleteMember(id: member.id, currentUserId: userSession.userId)
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }

        memberToDelete = nil
    }
}

// MARK: - Member Row

private struct MemberManagementRow: View {
    let member: Member
    let isCurrentUser: Bool
    let currentUserIsOwner: Bool
    let onEditName: () -> Void
    let onChangeRole: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            memberInfo
            Spacer()
            actionMenu
        }
    }

    private var memberInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(member.displayName)
                .font(.body)

            HStack(spacing: 4) {
                Image(systemName: member.role == .owner ? "star.fill" : "person.fill")
                    .font(.caption2)
                Text(member.role == .owner ? "Owner" : "Member")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var actionMenu: some View {
        Menu {
            menuContent
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if isCurrentUser {
            Button("Edit Name", action: onEditName)
        } else if currentUserIsOwner {
            Button("Edit Name", action: onEditName)
            Button(member.role == .owner ? "Change to Member" : "Make Owner", action: onChangeRole)
            Button("Remove", role: .destructive, action: onDelete)
        }
    }
}
