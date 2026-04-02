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
    case foregroundRepairWindow
    case appBecameActive
    case manualRefresh
    case localMutationFollowUp
    case householdJoined
    case householdSwitched
    case debugRepair

    func merged(with newer: HouseholdSyncReason) -> HouseholdSyncReason {
        Self.max(self, newer)
    }

    private var priority: Int {
        switch self {
        case .remotePush:
            0
        case .foregroundRepairWindow:
            1
        case .appBecameActive:
            2
        case .localMutationFollowUp:
            3
        case .householdJoined:
            4
        case .householdSwitched:
            5
        case .debugRepair:
            6
        case .manualRefresh:
            7
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
        case let (.remotePush(context), .foregroundRepairWindow),
             let (.foregroundRepairWindow, .remotePush(context)):
            return .remotePush(context: context)
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
        case .foregroundRepairWindow, .appBecameActive:
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

enum HouseholdSyncBatchClassification: Equatable {
    case bootstrap
    case steadyStateRemote
    case steadyStateLifecycle

    static func resolve(
        reason: HouseholdSyncReason,
        events: [HouseholdSyncEvent]
    ) -> HouseholdSyncBatchClassification {
        if reason.isBootstrapLike || events.contains(where: \.isMembershipChange) {
            return .bootstrap
        }

        switch reason {
        case .remotePush:
            return .steadyStateRemote
        case .foregroundRepairWindow, .appBecameActive, .manualRefresh, .localMutationFollowUp, .debugRepair:
            return .steadyStateLifecycle
        case .householdJoined, .householdSwitched:
            return .bootstrap
        }
    }
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

    var isMembershipChange: Bool {
        if case .membersChanged = kind {
            return true
        }
        return false
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
    let activeMemberCount: Int?

    init(
        batchID: UUID,
        reason: HouseholdSyncReason,
        direction: HouseholdSyncDirection,
        triggerReceivedAt: Date,
        syncStartedAt: Date,
        syncFinishedAt: Date,
        changedDomains: Set<HouseholdSyncChangedDomain>,
        changedIDsByDomain: [HouseholdSyncChangedDomain: Set<UUID>],
        activeMemberCount: Int? = nil
    ) {
        self.batchID = batchID
        self.reason = reason
        self.direction = direction
        self.triggerReceivedAt = triggerReceivedAt
        self.syncStartedAt = syncStartedAt
        self.syncFinishedAt = syncFinishedAt
        self.changedDomains = changedDomains
        self.changedIDsByDomain = changedIDsByDomain
        self.activeMemberCount = activeMemberCount
    }
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
    let classification: HouseholdSyncBatchClassification

    init(events: [HouseholdSyncEvent], diagnostics: HouseholdSyncDiagnostics) {
        id = diagnostics.batchID
        self.events = events
        self.diagnostics = diagnostics
        classification = HouseholdSyncBatchClassification.resolve(
            reason: diagnostics.reason,
            events: events
        )
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

struct ForegroundRepairConfiguration: Equatable {
    let isEnabled: Bool
    let burstIntervalNanoseconds: UInt64
    let burstMaxPassCount: Int
    let maxConsecutiveNoDataBurstPasses: Int
    let steadyIntervalNanoseconds: UInt64
    let steadyMaxPassCount: Int

    static let `default` = ForegroundRepairConfiguration(
        isEnabled: true,
        burstIntervalNanoseconds: 4_000_000_000,
        burstMaxPassCount: 8,
        maxConsecutiveNoDataBurstPasses: 2,
        steadyIntervalNanoseconds: 30_000_000_000,
        steadyMaxPassCount: 20
    )
}

private enum ForegroundRepairMode: Equatable {
    case burst
    case steady
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
    private let applicationStateProvider: @MainActor () -> UIApplication.State
    private let foregroundRepairConfiguration: ForegroundRepairConfiguration
    private let interactiveManualRefreshBudgetNanoseconds: UInt64
    private let sharedShoppingAlertDelivery: @MainActor ([String], UUID, String?) async -> Void
    private var activeSyncTask: _Concurrency.Task<UIBackgroundFetchResult, Never>?
    private var pendingReason: HouseholdSyncReason?
    private var scheduledForegroundRepairTask: _Concurrency.Task<Void, Never>?
    private var currentForegroundRepairMode: ForegroundRepairMode = .burst
    private var remainingForegroundRepairBurstPasses = 0
    private var remainingForegroundRepairSteadyPasses = 0
    private var consecutiveForegroundRepairNoDataPasses = 0

    init(
        engine: HouseholdSyncEngine,
        applicationStateProvider: @escaping @MainActor () -> UIApplication.State = {
            UIApplication.shared.applicationState
        },
        foregroundRepairConfiguration: ForegroundRepairConfiguration = .default,
        interactiveManualRefreshBudgetNanoseconds: UInt64 = 2_500_000_000,
        sharedShoppingAlertDelivery: @escaping @MainActor ([String], UUID, String?) async -> Void = {
            titles, householdId, householdName in
            await NotificationService.shared.deliverSharedShoppingItemsAddedAlert(
                itemTitles: titles,
                householdId: householdId,
                householdName: householdName
            )
        }
    ) {
        self.engine = engine
        self.applicationStateProvider = applicationStateProvider
        self.foregroundRepairConfiguration = foregroundRepairConfiguration
        self.interactiveManualRefreshBudgetNanoseconds = interactiveManualRefreshBudgetNanoseconds
        self.sharedShoppingAlertDelivery = sharedShoppingAlertDelivery
    }

    func performInteractiveManualRefresh() async {
        let syncTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return UIBackgroundFetchResult.noData }
            return await performSync(reason: .manualRefresh)
        }

        let budgetNanoseconds = interactiveManualRefreshBudgetNanoseconds
        guard budgetNanoseconds > 0 else { return }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = await syncTask.value
            }
            group.addTask {
                try? await _Concurrency.Task.sleep(nanoseconds: budgetNanoseconds)
            }
            await group.next()
            group.cancelAll()
        }
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
        scheduleForegroundRepairIfNeeded(for: batch, fetchResult: result.fetchResult)
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
        guard batch.classification != .bootstrap else { return }
        for event in batch.events {
            switch event.kind {
            case let .shoppingAdded(ids, titles):
                guard let payload = CloudKitSubscriptionManager.shared.filteredShoppingAdditionPayload(
                    ids: ids,
                    titles: titles
                ) else {
                    continue
                }
                guard !payload.titles.isEmpty else { continue }
                await sharedShoppingAlertDelivery(payload.titles, event.householdId, nil)
            default:
                continue
            }
        }
    }

    private func scheduleForegroundRepairIfNeeded(
        for batch: HouseholdSyncBatch,
        fetchResult: UIBackgroundFetchResult
    ) {
        guard foregroundRepairConfiguration.isEnabled else { return }

        guard applicationStateProvider() == .active,
              (batch.diagnostics.activeMemberCount ?? 0) > 1
        else {
            cancelForegroundRepair()
            return
        }

        switch batch.diagnostics.reason {
        case .remotePush, .appBecameActive, .localMutationFollowUp, .householdJoined, .householdSwitched:
            startBurstForegroundRepair(trigger: batch.diagnostics.reason)
        case .manualRefresh:
            cancelForegroundRepair()
        case .foregroundRepairWindow:
            switch fetchResult {
            case .newData:
                startBurstForegroundRepair(trigger: batch.diagnostics.reason)
            case .noData:
                handleForegroundRepairNoDataPass()
            case .failed:
                cancelForegroundRepair()
            @unknown default:
                cancelForegroundRepair()
            }
        case .debugRepair:
            cancelForegroundRepair()
        }
    }

    private func startBurstForegroundRepair(trigger: HouseholdSyncReason) {
        currentForegroundRepairMode = .burst
        remainingForegroundRepairBurstPasses = foregroundRepairConfiguration.burstMaxPassCount
        remainingForegroundRepairSteadyPasses = foregroundRepairConfiguration.steadyMaxPassCount
        consecutiveForegroundRepairNoDataPasses = 0
        recordSchedulerProgress(
            "sync.scheduler.started reason=\(schedulerReasonLabel(trigger)) burstPasses=\(remainingForegroundRepairBurstPasses) steadyPasses=\(remainingForegroundRepairSteadyPasses)"
        )
        print(
            "[RemoteSync] Starting burst foreground repair window. burstPasses=\(remainingForegroundRepairBurstPasses) steadyPasses=\(remainingForegroundRepairSteadyPasses)"
        )
        scheduleNextForegroundRepairPass(
            intervalNanoseconds: foregroundRepairConfiguration.burstIntervalNanoseconds
        )
    }

    private func handleForegroundRepairNoDataPass() {
        switch currentForegroundRepairMode {
        case .burst:
            remainingForegroundRepairBurstPasses = max(
                remainingForegroundRepairBurstPasses - 1,
                0
            )
            consecutiveForegroundRepairNoDataPasses += 1

            if remainingForegroundRepairBurstPasses > 0,
               consecutiveForegroundRepairNoDataPasses <
               foregroundRepairConfiguration.maxConsecutiveNoDataBurstPasses
            {
                scheduleNextForegroundRepairPass(
                    intervalNanoseconds: foregroundRepairConfiguration.burstIntervalNanoseconds
                )
            } else {
                startSteadyForegroundRepairIfNeeded()
            }
        case .steady:
            remainingForegroundRepairSteadyPasses = max(
                remainingForegroundRepairSteadyPasses - 1,
                0
            )
            guard remainingForegroundRepairSteadyPasses > 0 else {
                cancelForegroundRepair()
                return
            }
            scheduleNextForegroundRepairPass(
                intervalNanoseconds: foregroundRepairConfiguration.steadyIntervalNanoseconds
            )
        }
    }

    private func recordSchedulerProgress(_ operation: String) {
        CloudKitDiagnosticsState.shared.recordProgress(operation: operation)
    }

    private func schedulerReasonLabel(_ reason: HouseholdSyncReason) -> String {
        switch reason {
        case let .remotePush(context):
            switch context {
            case .sharedDatabase:
                "remotePushShared"
            case .privateDatabase:
                "remotePushPrivate"
            case .unknown:
                "remotePushUnknown"
            }
        case .foregroundRepairWindow:
            "foregroundRepairWindow"
        case .appBecameActive:
            "appBecameActive"
        case .manualRefresh:
            "manualRefresh"
        case .localMutationFollowUp:
            "localMutationFollowUp"
        case .householdJoined:
            "householdJoined"
        case .householdSwitched:
            "householdSwitched"
        case .debugRepair:
            "debugRepair"
        }
    }

    private func startSteadyForegroundRepairIfNeeded() {
        guard foregroundRepairConfiguration.steadyMaxPassCount > 0 else {
            cancelForegroundRepair()
            return
        }

        currentForegroundRepairMode = .steady
        consecutiveForegroundRepairNoDataPasses = 0
        remainingForegroundRepairSteadyPasses = max(
            remainingForegroundRepairSteadyPasses,
            foregroundRepairConfiguration.steadyMaxPassCount
        )
        print(
            "[RemoteSync] Extending foreground repair into steady mode. remainingSteadyPasses=\(remainingForegroundRepairSteadyPasses)"
        )
        scheduleNextForegroundRepairPass(
            intervalNanoseconds: foregroundRepairConfiguration.steadyIntervalNanoseconds
        )
    }

    private func scheduleNextForegroundRepairPass(intervalNanoseconds: UInt64) {
        scheduledForegroundRepairTask?.cancel()
        scheduledForegroundRepairTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            if intervalNanoseconds > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: intervalNanoseconds)
            }
            guard !_Concurrency.Task.isCancelled else { return }
            _ = await performSync(reason: .foregroundRepairWindow)
        }
    }

    private func cancelForegroundRepair() {
        scheduledForegroundRepairTask?.cancel()
        scheduledForegroundRepairTask = nil
        currentForegroundRepairMode = .burst
        remainingForegroundRepairBurstPasses = 0
        remainingForegroundRepairSteadyPasses = 0
        consecutiveForegroundRepairNoDataPasses = 0
    }
}

private extension HouseholdSyncReason {
    var isBootstrapLike: Bool {
        switch self {
        case .householdJoined, .householdSwitched:
            true
        default:
            false
        }
    }
}
