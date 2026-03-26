import Foundation
import SwiftUI
import UIKit

enum HouseholdSyncRemoteContext: Equatable {
    case sharedDatabase
    case privateDatabase
    case unknown

    init(from context: RemoteCloudChangeContext) {
        switch context.databaseScope {
        case .shared:
            self = .sharedDatabase
        case .private:
            self = .privateDatabase
        default:
            self = .unknown
        }
    }
}

enum HouseholdSyncReason: Equatable {
    case remotePush(context: HouseholdSyncRemoteContext)
    case appBecameActive
    case manualRefresh
    case localMutationFollowUp
    case householdJoined
    case householdSwitched
    case debugRepair

    func merged(with newer: HouseholdSyncReason) -> HouseholdSyncReason {
        max(self, newer)
    }

    private var priority: Int {
        switch self {
        case .remotePush:
            0
        case .appBecameActive:
            1
        case .localMutationFollowUp:
            2
        case .householdJoined:
            3
        case .householdSwitched:
            4
        case .debugRepair:
            5
        case .manualRefresh:
            6
        }
    }

    private static func max(_ lhs: HouseholdSyncReason, _ rhs: HouseholdSyncReason) -> HouseholdSyncReason {
        switch (lhs, rhs) {
        case let (.remotePush(leftContext), .remotePush(rightContext)):
            if leftContext == .sharedDatabase || rightContext == .sharedDatabase {
                return .remotePush(context: .sharedDatabase)
            }
            if leftContext == .privateDatabase || rightContext == .privateDatabase {
                return .remotePush(context: .privateDatabase)
            }
            return .remotePush(context: .unknown)
        default:
            return lhs.priority >= rhs.priority ? lhs : rhs
        }
    }
}

enum HouseholdSyncEventSource: Equatable {
    case remote
    case foregroundRepair
    case manual
    case localFollowUp
    case lifecycle
    case debug

    init(reason: HouseholdSyncReason) {
        switch reason {
        case .remotePush:
            self = .remote
        case .appBecameActive:
            self = .foregroundRepair
        case .manualRefresh:
            self = .manual
        case .localMutationFollowUp:
            self = .localFollowUp
        case .householdJoined, .householdSwitched:
            self = .lifecycle
        case .debugRepair:
            self = .debug
        }
    }
}

enum HouseholdSyncDirection: String, Equatable {
    case ownerToParticipant = "owner_to_participant"
    case participantToOwner = "participant_to_owner"
    case unknown
}

enum HouseholdSyncChangedDomain: String, Equatable, Hashable {
    case household
    case members
    case shopping
    case tasks
    case ideas
    case backlog
}

enum HouseholdSyncEventKind: Equatable {
    case householdMetadataChanged
    case membersChanged(ids: Set<UUID>)
    case shoppingAdded(ids: Set<UUID>, titles: [String])
    case shoppingUpdated(itemIDs: Set<UUID>, bundleIDs: Set<UUID>)
    case shoppingRemoved(itemIDs: Set<UUID>, bundleIDs: Set<UUID>)
    case tasksChanged(addedIDs: Set<UUID>, changedIDs: Set<UUID>, removedIDs: Set<UUID>)
    case ideasChanged(addedIDs: Set<UUID>, changedIDs: Set<UUID>, removedIDs: Set<UUID>)
    case backlogCategoriesChanged(addedIDs: Set<UUID>, changedIDs: Set<UUID>, removedIDs: Set<UUID>)
}

struct HouseholdSyncEvent: Equatable {
    let householdId: UUID
    let batchID: UUID
    let source: HouseholdSyncEventSource
    let reason: HouseholdSyncReason
    let timestamp: Date
    let direction: HouseholdSyncDirection
    let kind: HouseholdSyncEventKind

    var domains: Set<HouseholdSyncChangedDomain> {
        switch kind {
        case .householdMetadataChanged:
            [.household]
        case .membersChanged:
            [.members]
        case .shoppingAdded, .shoppingUpdated, .shoppingRemoved:
            [.shopping]
        case .tasksChanged:
            [.tasks]
        case .ideasChanged:
            [.ideas]
        case .backlogCategoriesChanged:
            [.backlog]
        }
    }
}

struct HouseholdSyncDiagnostics: Equatable {
    let batchID: UUID
    let reason: HouseholdSyncReason
    let direction: HouseholdSyncDirection
    let triggerReceivedAt: Date
    let syncStartedAt: Date
    let syncFinishedAt: Date
    let changedDomains: Set<HouseholdSyncChangedDomain>
    let changedIDsByDomain: [HouseholdSyncChangedDomain: Set<UUID>]
}

struct HouseholdSyncPassResult: Equatable {
    let fetchResult: UIBackgroundFetchResult
    let events: [HouseholdSyncEvent]
    let diagnostics: HouseholdSyncDiagnostics
}

struct HouseholdSyncBatch: Equatable, Identifiable {
    let id: UUID
    let events: [HouseholdSyncEvent]
    let diagnostics: HouseholdSyncDiagnostics

    init(events: [HouseholdSyncEvent], diagnostics: HouseholdSyncDiagnostics) {
        id = diagnostics.batchID
        self.events = events
        self.diagnostics = diagnostics
    }

    var domains: Set<HouseholdSyncChangedDomain> {
        Set(events.flatMap(\.domains))
    }

    var shoppingChangedItemIDs: Set<UUID> {
        events.reduce(into: Set<UUID>()) { partialResult, event in
            switch event.kind {
            case let .shoppingAdded(ids, _):
                partialResult.formUnion(ids)
            case let .shoppingUpdated(itemIDs, _):
                partialResult.formUnion(itemIDs)
            case let .shoppingRemoved(itemIDs, _):
                partialResult.formUnion(itemIDs)
            default:
                break
            }
        }
    }

    var backlogChangedCategoryIDs: Set<UUID> {
        events.reduce(into: Set<UUID>()) { partialResult, event in
            switch event.kind {
            case let .backlogCategoriesChanged(addedIDs, changedIDs, removedIDs):
                partialResult.formUnion(addedIDs)
                partialResult.formUnion(changedIDs)
                partialResult.formUnion(removedIDs)
            default:
                break
            }
        }
    }

    var taskChangedIDs: Set<UUID> {
        events.reduce(into: Set<UUID>()) { partialResult, event in
            switch event.kind {
            case let .tasksChanged(addedIDs, changedIDs, removedIDs):
                partialResult.formUnion(addedIDs)
                partialResult.formUnion(changedIDs)
                partialResult.formUnion(removedIDs)
            default:
                break
            }
        }
    }

    var ideaChangedIDs: Set<UUID> {
        events.reduce(into: Set<UUID>()) { partialResult, event in
            switch event.kind {
            case let .ideasChanged(addedIDs, changedIDs, removedIDs):
                partialResult.formUnion(addedIDs)
                partialResult.formUnion(changedIDs)
                partialResult.formUnion(removedIDs)
            default:
                break
            }
        }
    }

    var memberChangedIDs: Set<UUID> {
        events.reduce(into: Set<UUID>()) { partialResult, event in
            switch event.kind {
            case let .membersChanged(ids):
                partialResult.formUnion(ids)
            default:
                break
            }
        }
    }
}

@MainActor
protocol HouseholdSyncEngine: AnyObject {
    func runSync(for reason: HouseholdSyncReason) async -> HouseholdSyncPassResult
}

@MainActor
final class HouseholdSyncCoordinator: ObservableObject {
    @Published private(set) var latestBatch: HouseholdSyncBatch?
    @Published private(set) var lastPublishedEvents: [HouseholdSyncEvent] = []
    @Published private(set) var lastDiagnostics: HouseholdSyncDiagnostics?

    private let engine: HouseholdSyncEngine
    private var activeSyncTask: _Concurrency.Task<UIBackgroundFetchResult, Never>?
    private var pendingReason: HouseholdSyncReason?

    init(engine: HouseholdSyncEngine) {
        self.engine = engine
    }

    func performSync(reason: HouseholdSyncReason) async -> UIBackgroundFetchResult {
        pendingReason = pendingReason?.merged(with: reason) ?? reason

        if let activeSyncTask {
            return await activeSyncTask.value
        }

        let syncTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return UIBackgroundFetchResult.noData }

            var aggregateResult: UIBackgroundFetchResult = .noData

            while let nextReason = pendingReason {
                pendingReason = nil
                let result = await engine.runSync(for: nextReason)
                await publish(result)
                aggregateResult = mergedBackgroundFetchResult(
                    aggregateResult,
                    with: result.fetchResult
                )
            }

            activeSyncTask = nil
            return aggregateResult
        }

        activeSyncTask = syncTask
        return await syncTask.value
    }

    private func publish(_ result: HouseholdSyncPassResult) async {
        lastPublishedEvents = result.events
        lastDiagnostics = result.diagnostics
        let batch = HouseholdSyncBatch(
            events: result.events,
            diagnostics: result.diagnostics
        )
        latestBatch = batch
        CloudKitSubscriptionManager.shared.consumeSyncBatch(batch)
        await deliverSystemAlerts(for: batch)
    }

    private func mergedBackgroundFetchResult(
        _ lhs: UIBackgroundFetchResult,
        with rhs: UIBackgroundFetchResult
    ) -> UIBackgroundFetchResult {
        if lhs == .failed || rhs == .failed {
            return .failed
        }
        if lhs == .newData || rhs == .newData {
            return .newData
        }
        return .noData
    }

    private func deliverSystemAlerts(for batch: HouseholdSyncBatch) async {
        for event in batch.events {
            switch event.kind {
            case let .shoppingAdded(_, titles):
                guard !titles.isEmpty else { continue }
                await NotificationService.shared.deliverSharedShoppingItemsAddedAlert(
                    itemTitles: titles,
                    householdId: event.householdId,
                    householdName: nil
                )
            default:
                continue
            }
        }
    }
}
