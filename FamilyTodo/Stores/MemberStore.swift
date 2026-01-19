import Foundation

/// Store for household members
@MainActor
final class MemberStore: ObservableObject {
    @Published private(set) var members: [Member] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private lazy var cloudKit = CloudKitManager.shared
    private let householdId: UUID?

    init(householdId: UUID?) {
        self.householdId = householdId
    }

    func loadMembers() async {
        guard let householdId else { return }

        isLoading = true
        error = nil

        do {
            members = try await cloudKit.fetchMembers(householdId: householdId)
            members.sort {
                if $0.role != $1.role {
                    return $0.role == .owner
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
