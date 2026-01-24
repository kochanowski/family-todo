import SwiftUI

struct MemberManagementView: View {
    @ObservedObject var memberStore: MemberStore
    @ObservedObject var householdStore: HouseholdStore
    @EnvironmentObject var userSession: UserSession

    @State private var editingMember: Member?
    @State private var newDisplayName = ""
    @State private var showEditNameAlert = false
    @State private var showDeleteConfirmation = false
    @State private var memberToDelete: Member?
    @State private var errorMessage: String?

    var currentUserIsOwner: Bool {
        guard let userId = userSession.userId else { return false }
        return memberStore.members.first(where: { $0.userId == userId })?.role == .owner
    }

    var body: some View {
        NavigationStack {
            List {
                // Members section
                Section("Members") {
                    ForEach(memberStore.members) { member in
                        HStack {
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

                            Spacer()

                            // Actions menu
                            Menu {
                                if member.id
                                    == memberStore.members.first(where: { $0.userId == userSession.userId })?.id
                                {
                                    // Current user - can edit name only
                                    Button("Edit Name") {
                                        editingMember = member
                                        newDisplayName = member.displayName
                                        showEditNameAlert = true
                                    }
                                } else if currentUserIsOwner {
                                    // Owner can change roles and delete
                                    Button("Edit Name") {
                                        editingMember = member
                                        newDisplayName = member.displayName
                                        showEditNameAlert = true
                                    }

                                    Button(member.role == .owner ? "Change to Member" : "Make Owner") {
                                        _Concurrency.Task {
                                            await changeRole(member: member)
                                        }
                                    }

                                    Button("Remove", role: .destructive) {
                                        memberToDelete = member
                                        showDeleteConfirmation = true
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Invite section
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
            .navigationTitle("Household Members")
            .alert("Edit Name", isPresented: $showEditNameAlert) {
                TextField("Display Name", text: $newDisplayName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    _Concurrency.Task {
                        await saveName()
                    }
                }
            }
            .alert("Remove Member", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    _Concurrency.Task {
                        await deleteMember()
                    }
                }
            } message: {
                if let member = memberToDelete {
                    Text("Are you sure you want to remove \(member.displayName)? This cannot be undone.")
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let message = errorMessage {
                    Text(message)
                }
            }
        }
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
        }
    }

    private func changeRole(member: Member) async {
        let newRole: Member.MemberRole = member.role == .owner ? .member : .owner

        do {
            try await memberStore.updateRole(
                id: member.id,
                newRole: newRole,
                currentUserId: userSession.userId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteMember() async {
        guard let member = memberToDelete else { return }

        do {
            try await memberStore.deleteMember(id: member.id, currentUserId: userSession.userId)
        } catch {
            errorMessage = error.localizedDescription
        }

        memberToDelete = nil
    }
}
