import Foundation

struct HouseholdCloudSnapshot {
    let members: [Member]
    let unifiedWorkItems: [WorkItem]
    let shoppingItems: [ShoppingItem]
    let shoppingBundles: [ShoppingBundle]
    let backlogCategories: [BacklogCategory]
    let backlogItems: [BacklogItem]

    func hasActiveMembership(userId: String) -> Bool {
        members.contains { $0.userId == userId && $0.isActive }
    }
}

enum HouseholdCloudSnapshotLoaderError: LocalizedError, Equatable {
    case domainFetchTimedOut(String)
    case snapshotTimedOut

    var errorDescription: String? {
        switch self {
        case let .domainFetchTimedOut(domain):
            "Cloud snapshot fetch timed out for \(domain)."
        case .snapshotTimedOut:
            "Cloud snapshot fetch timed out."
        }
    }
}

actor HouseholdCloudSnapshotLoader {
    private let cloud: any HouseholdCloudSyncing
    private let domainFetchTimeoutNanoseconds: UInt64
    private let snapshotTimeoutNanoseconds: UInt64

    init(
        cloud: any HouseholdCloudSyncing,
        domainFetchTimeoutNanoseconds: UInt64 = 10_000_000_000,
        snapshotTimeoutNanoseconds: UInt64 = 60_000_000_000
    ) {
        self.cloud = cloud
        self.domainFetchTimeoutNanoseconds = domainFetchTimeoutNanoseconds
        self.snapshotTimeoutNanoseconds = snapshotTimeoutNanoseconds
    }

    func loadSnapshot(
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope
    ) async throws -> HouseholdCloudSnapshot {
        await cloud.ensureReady()

        return try await withTimeout(
            nanoseconds: snapshotTimeoutNanoseconds,
            timeoutError: HouseholdCloudSnapshotLoaderError.snapshotTimedOut
        ) { [self] in
            let members = try await fetchDomain(
                "members",
                householdId: householdId,
                scope: scope
            ) {
                try await self.cloud.fetchMembers(
                    householdId: householdId,
                    scope: scope
                )
            }
            let shoppingItems = try await fetchDomain(
                "shoppingItems",
                householdId: householdId,
                scope: scope
            ) {
                try await self.cloud.fetchShoppingItems(
                    householdId: householdId,
                    scope: scope
                )
            }
            let shoppingBundles = try await fetchDomain(
                "shoppingBundles",
                householdId: householdId,
                scope: scope
            ) {
                try await self.cloud.fetchShoppingBundles(
                    householdId: householdId,
                    scope: scope
                )
            }
            let backlogCategories = try await fetchDomain(
                "backlogCategories",
                householdId: householdId,
                scope: scope
            ) {
                try await self.cloud.fetchBacklogCategories(
                    householdId: householdId,
                    scope: scope
                )
            }
            let backlogItems = try await fetchDomain(
                "backlogItems",
                householdId: householdId,
                scope: scope
            ) {
                try await self.cloud.fetchBacklogItems(
                    householdId: householdId,
                    scope: scope
                )
            }
            let tasks = try await fetchDomain(
                "tasks",
                householdId: householdId,
                scope: scope
            ) {
                try await self.cloud.fetchTasks(
                    householdId: householdId,
                    scope: scope
                )
            }
            let workItems = try await fetchDomain(
                "workItems",
                householdId: householdId,
                scope: scope
            ) {
                try await self.cloud.fetchWorkItems(
                    householdId: householdId,
                    scope: scope
                )
            }

            return HouseholdCloudSnapshot(
                members: members,
                unifiedWorkItems: Self.mergeUnifiedWorkItems(
                    workItems: workItems,
                    tasks: tasks,
                    ideas: backlogItems
                ),
                shoppingItems: shoppingItems,
                shoppingBundles: shoppingBundles,
                backlogCategories: backlogCategories,
                backlogItems: backlogItems
            )
        }
    }

    private func fetchDomain<Value>(
        _ domain: String,
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        await recordSnapshotProgress(
            "snapshot.fetch.started domain=\(domain) scope=\(scopeLabel(scope)) householdId=\(householdId.uuidString)"
        )

        do {
            let value = try await withTimeout(
                nanoseconds: domainFetchTimeoutNanoseconds,
                timeoutError: HouseholdCloudSnapshotLoaderError.domainFetchTimedOut(domain),
                operation: operation
            )
            await recordSnapshotProgress(
                "snapshot.fetch.completed domain=\(domain) scope=\(scopeLabel(scope)) householdId=\(householdId.uuidString) \(countLabel(for: value))"
            )
            return value
        } catch {
            await recordSnapshotProgress(
                "snapshot.fetch.failed domain=\(domain) scope=\(scopeLabel(scope)) householdId=\(householdId.uuidString) error=\(String(describing: error))"
            )
            throw error
        }
    }

    private func withTimeout<Value>(
        nanoseconds: UInt64,
        timeoutError: some Error & Sendable,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await _Concurrency.Task.sleep(nanoseconds: nanoseconds)
                throw timeoutError
            }

            let result = try await group.next()
            group.cancelAll()
            return try result.unwrap()
        }
    }

    private static func mergeUnifiedWorkItems(
        workItems: [WorkItem],
        tasks: [Task],
        ideas: [BacklogItem]
    ) -> [WorkItem] {
        var mergedByLogicalID = Dictionary(uniqueKeysWithValues: workItems.map { ($0.logicalItemID, $0) })

        for task in tasks {
            let candidate = WorkItem(task: task)
            guard mergedByLogicalID[candidate.logicalItemID] == nil else { continue }
            mergedByLogicalID[candidate.logicalItemID] = candidate
        }

        for idea in ideas {
            let candidate = WorkItem(idea: idea)
            if let existing = mergedByLogicalID[candidate.logicalItemID],
               !shouldReplaceUnifiedWorkItem(existing: existing, with: candidate)
            {
                continue
            }
            mergedByLogicalID[candidate.logicalItemID] = candidate
        }

        return mergedByLogicalID.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func shouldReplaceUnifiedWorkItem(existing: WorkItem, with candidate: WorkItem)
        -> Bool
    {
        let existingPriority = unifiedWorkItemStatusPriority(existing.status)
        let candidatePriority = unifiedWorkItemStatusPriority(candidate.status)

        if candidatePriority != existingPriority {
            return candidatePriority > existingPriority
        }

        return candidate.updatedAt > existing.updatedAt
    }

    private static func unifiedWorkItemStatusPriority(_ status: WorkItem.Status) -> Int {
        switch status {
        case .done:
            4
        case .next:
            3
        case .backlog:
            2
        case .idea:
            1
        }
    }

    private func countLabel(for value: some Any) -> String {
        if let members = value as? [Member] {
            return "count=\(members.count)"
        }
        if let shoppingItems = value as? [ShoppingItem] {
            return "count=\(shoppingItems.count)"
        }
        if let shoppingBundles = value as? [ShoppingBundle] {
            return "count=\(shoppingBundles.count)"
        }
        if let backlogCategories = value as? [BacklogCategory] {
            return "count=\(backlogCategories.count)"
        }
        if let backlogItems = value as? [BacklogItem] {
            return "count=\(backlogItems.count)"
        }
        if let tasks = value as? [Task] {
            return "count=\(tasks.count)"
        }
        if let workItems = value as? [WorkItem] {
            return "count=\(workItems.count)"
        }
        return "completed=true"
    }

    private func recordSnapshotProgress(_ operation: String) async {
        await MainActor.run {
            CloudKitDiagnosticsState.shared.recordProgress(operation: operation)
        }
    }

    private func scopeLabel(_ scope: CloudKitManager.HouseholdDatabaseScope) -> String {
        switch scope {
        case .ownerPrivate:
            "ownerPrivate"
        case .participantShared:
            "participantShared"
        }
    }
}

private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let self else {
            throw HouseholdCloudSnapshotLoaderError.snapshotTimedOut
        }
        return self
    }
}
