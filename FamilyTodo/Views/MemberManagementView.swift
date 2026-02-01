import SwiftData
import SwiftUI

struct MemberManagementView: View {
    @StateObject private var memberStore: MemberStore
    @EnvironmentObject var householdStore: HouseholdStore
    @EnvironmentObject var userSession: UserSession
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
                .alert("Edit Name", isPresented: $showEditNameAlert) {
                    editNameAlertContent
                }
                .alert("Remove Member", isPresented: $showDeleteConfirmation) {
                    deleteAlertButtons
                } message: {
                    deleteAlertMessage
                }
                .alert("Error", isPresented: $showErrorAlert) {
                    Button("OK") {}
                } message: {
                    Text(errorMessage)
                }
        }
        .task {
            memberStore.setModelContext(modelContext)
            await memberStore.loadMembers()
        }
    }

    // MARK: - Subviews

    private var listContent: some View {
        List {
            membersSection
            inviteSection
        }
    }

    private var membersSection: some View {
        Section("Members") {
            ForEach(memberStore.members) { member in
                MemberRow(
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
                NavigationLink {
                    ShareInviteView()
                        .environmentObject(householdStore)
                } label: {
                    Label("Invite Member", systemImage: "person.badge.plus")
                }
            }
        }
    }

    @ViewBuilder
    private var editNameAlertContent: some View {
        TextField("Display Name", text: $newDisplayName)
        Button("Cancel", role: .cancel) {}
        Button("Save") {
            _Concurrency.Task { await saveName() }
        }
    }

    @ViewBuilder
    private var deleteAlertButtons: some View {
        Button("Cancel", role: .cancel) {}
        Button("Remove", role: .destructive) {
            _Concurrency.Task { await deleteMember() }
        }
    }

    @ViewBuilder
    private var deleteAlertMessage: some View {
        if let member = memberToDelete {
            Text("Are you sure you want to remove \(member.displayName)? This cannot be undone.")
        } else {
            Text("")
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

private struct MemberRow: View {
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
