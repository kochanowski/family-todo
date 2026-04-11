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
    let syncRole: HouseholdSyncRole?
    let syncScope: CloudKitManager.HouseholdDatabaseScope?
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
        syncRole: HouseholdSyncRole? = nil,
        syncScope: CloudKitManager.HouseholdDatabaseScope? = nil,
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
        self.syncRole = syncRole
        self.syncScope = syncScope
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
    let visibleChanges: HouseholdSyncVisibleChanges

    init(
        fetchResult: UIBackgroundFetchResult,
        events: [HouseholdSyncEvent],
        diagnostics: HouseholdSyncDiagnostics,
        visibleChanges: HouseholdSyncVisibleChanges = .empty
    ) {
        self.fetchResult = fetchResult
        self.events = events
        self.diagnostics = diagnostics
        self.visibleChanges = visibleChanges
    }
}

struct HouseholdSyncBatch: Equatable, Identifiable {
    let id: UUID
    let events: [HouseholdSyncEvent]
    let diagnostics: HouseholdSyncDiagnostics
    let classification: HouseholdSyncBatchClassification
    let visibleChanges: HouseholdSyncVisibleChanges

    init(
        events: [HouseholdSyncEvent],
        diagnostics: HouseholdSyncDiagnostics,
        visibleChanges: HouseholdSyncVisibleChanges = .empty
    ) {
        id = diagnostics.batchID
        self.events = events
        self.diagnostics = diagnostics
        self.visibleChanges = visibleChanges
        classification = HouseholdSyncBatchClassification.resolve(
            reason: diagnostics.reason,
            events: events
        )
    }

    var domains: Set<HouseholdSyncChangedDomain> {
        Set(events.flatMap(\.domains))
    }

    var shoppingChangedItemIDs: Set<UUID> {
        diagnostics.changedIDsByDomain[.shopping] ?? []
    }

    var backlogChangedCategoryIDs: Set<UUID> {
        diagnostics.changedIDsByDomain[.backlog] ?? []
    }

    var taskChangedIDs: Set<UUID> {
        diagnostics.changedIDsByDomain[.tasks] ?? []
    }

    var ideaChangedIDs: Set<UUID> {
        diagnostics.changedIDsByDomain[.ideas] ?? []
    }

    var memberChangedIDs: Set<UUID> {
        diagnostics.changedIDsByDomain[.members] ?? []
    }
}

struct ForegroundRepairConfiguration: Equatable {
    let isEnabled: Bool
    let burstIntervalNanoseconds: UInt64
    let burstMaxPassCount: Int
    let maxConsecutiveNoDataBurstPasses: Int
    let steadyIntervalNanoseconds: UInt64
    let steadyMaxPassCount: Int
    let ownerFallbackIntervalNanoseconds: UInt64
    let ownerFallbackMaxPassCount: Int

    static let `default` = ForegroundRepairConfiguration(
        isEnabled: true,
        burstIntervalNanoseconds: 4_000_000_000,
        burstMaxPassCount: 8,
        maxConsecutiveNoDataBurstPasses: 2,
        steadyIntervalNanoseconds: 30_000_000_000,
        steadyMaxPassCount: 20,
        ownerFallbackIntervalNanoseconds: 15_000_000_000,
        ownerFallbackMaxPassCount: 40
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
    let applicationStateProvider: @MainActor () -> UIApplication.State
    let currentHouseholdIDProvider: @MainActor () -> UUID?
    private let foregroundRepairConfiguration: ForegroundRepairConfiguration
    let inviteAcceptanceWatchConfiguration: InviteAcceptanceWatchConfiguration
    private let interactiveManualRefreshBudgetNanoseconds: UInt64
    private let sharedShoppingAlertDelivery: @MainActor ([String], UUID, String?) async -> Void
    private let passiveSharedActivityAlertDelivery: @MainActor (PassiveSharedActivityAlertDescriptor) async -> Void
    private var activeSyncTask: _Concurrency.Task<UIBackgroundFetchResult, Never>?
    private var pendingReason: HouseholdSyncReason?
    private var lastLifecycleSyncedHouseholdID: UUID?
    private var scheduledForegroundRepairTask: _Concurrency.Task<Void, Never>?
    private var scheduledOwnerFallbackTask: _Concurrency.Task<Void, Never>?
    var inviteAcceptanceWatchTask: _Concurrency.Task<Void, Never>?
    var inviteAcceptanceWatchedHouseholdID: UUID?
    private var currentForegroundRepairMode: ForegroundRepairMode = .burst
    private var remainingForegroundRepairBurstPasses = 0
    private var remainingForegroundRepairSteadyPasses = 0
    private var consecutiveForegroundRepairNoDataPasses = 0
    private var remainingOwnerFallbackPasses = 0

    init(
        engine: HouseholdSyncEngine,
        applicationStateProvider: @escaping @MainActor () -> UIApplication.State = {
            UIApplication.shared.applicationState
        },
        currentHouseholdIDProvider: @escaping @MainActor () -> UUID? = {
            UserSession.shared.currentHouseholdID
        },
        foregroundRepairConfiguration: ForegroundRepairConfiguration = .default,
        inviteAcceptanceWatchConfiguration: InviteAcceptanceWatchConfiguration = .default,
        interactiveManualRefreshBudgetNanoseconds: UInt64 = 2_500_000_000,
        sharedShoppingAlertDelivery: @escaping @MainActor ([String], UUID, String?) async -> Void = { titles, householdId, householdName in
            await NotificationService.shared.deliverSharedShoppingItemsAddedAlert(
                itemTitles: titles,
                householdId: householdId,
                householdName: householdName
            )
        },
        passiveSharedActivityAlertDelivery: (@MainActor (PassiveSharedActivityAlertDescriptor) async -> Void)? = nil
    ) {
        let resolvedPassiveSharedActivityAlertDelivery =
            passiveSharedActivityAlertDelivery ?? { descriptor in
                if descriptor.domain == .shopping,
                   descriptor.preservesShoppingTitles,
                   descriptor.changeCount == descriptor.shoppingTitles.count
                {
                    await sharedShoppingAlertDelivery(
                        descriptor.shoppingTitles,
                        descriptor.householdId,
                        descriptor.householdName
                    )
                } else {
                    await NotificationService.shared.deliverPassiveSharedActivityAlert(descriptor)
                }
            }
        self.engine = engine
        self.applicationStateProvider = applicationStateProvider
        self.currentHouseholdIDProvider = currentHouseholdIDProvider
        self.foregroundRepairConfiguration = foregroundRepairConfiguration
        self.inviteAcceptanceWatchConfiguration = inviteAcceptanceWatchConfiguration
        self.interactiveManualRefreshBudgetNanoseconds = interactiveManualRefreshBudgetNanoseconds
        self.sharedShoppingAlertDelivery = sharedShoppingAlertDelivery
        self.passiveSharedActivityAlertDelivery = resolvedPassiveSharedActivityAlertDelivery
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

    func performHouseholdLifecycleSyncIfNeeded(
        currentHouseholdID: UUID?
    ) async -> UIBackgroundFetchResult {
        guard let currentHouseholdID else {
            lastLifecycleSyncedHouseholdID = nil
            return .noData
        }

        guard lastLifecycleSyncedHouseholdID != currentHouseholdID else {
            return .noData
        }

        let reason: HouseholdSyncReason = if lastLifecycleSyncedHouseholdID == nil {
            .householdJoined
        } else {
            .householdSwitched
        }
        lastLifecycleSyncedHouseholdID = currentHouseholdID
        return await performSync(reason: reason)
    }

    func performSync(reason: HouseholdSyncReason) async -> UIBackgroundFetchResult {
        prioritizeRemotePushIfNeeded(reason)
        pendingReason = pendingReason?.merged(with: reason) ?? reason
        recordSchedulerProgress(
            "sync.pass.enqueued requestedReason=\(schedulerReasonLabel(reason)) effectivePendingReason=\(schedulerReasonLabel(pendingReason ?? reason)) activeTask=\(activeSyncTask != nil)"
        )

        if let activeSyncTask {
            return await activeSyncTask.value
        }

        let syncTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return UIBackgroundFetchResult.noData }

            var aggregateResult: UIBackgroundFetchResult = .noData

            while let nextReason = pendingReason {
                pendingReason = nil
                recordSchedulerProgress(
                    "sync.pass.started reason=\(schedulerReasonLabel(nextReason)) triggerSource=\(triggerSourceLabel(nextReason))"
                )
                let result = await engine.runSync(for: nextReason)
                await publish(result)
                aggregateResult = mergedBackgroundFetchResult(
                    aggregateResult,
                    with: result.fetchResult
                )
                recordSchedulerProgress(
                    "sync.pass.completed reason=\(schedulerReasonLabel(nextReason)) triggerSource=\(triggerSourceLabel(nextReason)) fetchResult=\(backgroundFetchResultLabel(result.fetchResult)) direction=\(result.diagnostics.direction.rawValue) eventCount=\(result.events.count)"
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
            diagnostics: result.diagnostics,
            visibleChanges: result.visibleChanges
        )
        latestBatch = batch
        let changedDomainLabels = batch.domains.map(\.rawValue).sorted().joined(separator: ",")
        recordSchedulerProgress(
            "sync.batch.published reason=\(schedulerReasonLabel(result.diagnostics.reason)) triggerSource=\(triggerSourceLabel(result.diagnostics.reason)) direction=\(result.diagnostics.direction.rawValue) changedDomains=\(changedDomainLabels) eventCount=\(batch.events.count)"
        )
        stopInviteAcceptanceWatchIfSatisfied(after: batch)
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
        guard batch.classification == .steadyStateRemote else {
            recordNotificationProgress(
                "notification.sharedActivity.batchSkipped classification=\(batchClassificationLabel(batch.classification)) eventCount=\(batch.events.count) reason=nonRemoteBatch"
            )
            return
        }

        let descriptors = passiveSharedActivityDescriptors(for: batch)
        guard !descriptors.isEmpty else {
            let householdLabel = batch.events.first?.householdId.uuidString ?? "unknown"
            recordNotificationProgress(
                "notification.sharedActivity.batchSuppressed householdId=\(householdLabel) eventCount=\(batch.events.count) reason=noRemoteNonLocalChanges"
            )
            return
        }

        for descriptor in descriptors {
            recordNotificationProgress(
                "notification.sharedActivity.descriptorPrepared householdId=\(descriptor.householdId.uuidString) domain=\(descriptor.domain.rawValue) changeCount=\(descriptor.changeCount) preservesShoppingTitles=\(descriptor.preservesShoppingTitles) titleCount=\(descriptor.shoppingTitles.count)"
            )
            await passiveSharedActivityAlertDelivery(descriptor)
        }
    }

    private func passiveSharedActivityDescriptors(
        for batch: HouseholdSyncBatch
    ) -> [PassiveSharedActivityAlertDescriptor] {
        var shoppingCount = 0
        var shoppingTitles: [String] = []
        var shoppingPreservesTitles = true
        var taskIDs = Set<UUID>()
        var ideaIDs = Set<UUID>()

        for event in batch.events {
            guard event.source == .remote else { continue }

            switch event.kind {
            case let .shoppingAdded(ids, titles):
                let nonLocalIDs = CloudKitSubscriptionManager.shared.filteredNonLocalIDs(ids)
                guard !nonLocalIDs.isEmpty else { continue }
                shoppingCount += nonLocalIDs.count

                if shoppingPreservesTitles, nonLocalIDs.count == ids.count {
                    shoppingTitles.append(contentsOf: titles)
                } else {
                    shoppingPreservesTitles = false
                    shoppingTitles.removeAll()
                }
            case let .shoppingUpdated(itemIDs, bundleIDs),
                 let .shoppingRemoved(itemIDs, bundleIDs):
                let itemCount = CloudKitSubscriptionManager.shared.filteredNonLocalIDs(itemIDs).count
                let bundleCount = CloudKitSubscriptionManager.shared.filteredNonLocalIDs(bundleIDs).count
                let nonLocalCount = itemCount + bundleCount
                guard nonLocalCount > 0 else { continue }
                shoppingCount += nonLocalCount
                shoppingPreservesTitles = false
                shoppingTitles.removeAll()
            case let .tasksChanged(addedIDs, changedIDs, removedIDs):
                taskIDs.formUnion(CloudKitSubscriptionManager.shared.filteredNonLocalIDs(addedIDs))
                taskIDs.formUnion(CloudKitSubscriptionManager.shared.filteredNonLocalIDs(changedIDs))
                taskIDs.formUnion(CloudKitSubscriptionManager.shared.filteredNonLocalIDs(removedIDs))
            case let .ideasChanged(addedIDs, changedIDs, removedIDs):
                ideaIDs.formUnion(CloudKitSubscriptionManager.shared.filteredNonLocalIDs(addedIDs))
                ideaIDs.formUnion(CloudKitSubscriptionManager.shared.filteredNonLocalIDs(changedIDs))
                ideaIDs.formUnion(CloudKitSubscriptionManager.shared.filteredNonLocalIDs(removedIDs))
            case let .backlogCategoriesChanged(addedIDs, changedIDs, removedIDs):
                ideaIDs.formUnion(CloudKitSubscriptionManager.shared.filteredNonLocalIDs(addedIDs))
                ideaIDs.formUnion(CloudKitSubscriptionManager.shared.filteredNonLocalIDs(changedIDs))
                ideaIDs.formUnion(CloudKitSubscriptionManager.shared.filteredNonLocalIDs(removedIDs))
            case .householdMetadataChanged, .membersChanged:
                continue
            }
        }

        guard let householdId = batch.events.first?.householdId else { return [] }
        var descriptors: [PassiveSharedActivityAlertDescriptor] = []

        if shoppingCount > 0 {
            descriptors.append(
                PassiveSharedActivityAlertDescriptor(
                    householdId: householdId,
                    householdName: nil,
                    domain: .shopping,
                    changeCount: shoppingCount,
                    shoppingTitles: shoppingTitles,
                    preservesShoppingTitles: shoppingPreservesTitles && !shoppingTitles.isEmpty
                )
            )
        }

        if !taskIDs.isEmpty {
            descriptors.append(
                PassiveSharedActivityAlertDescriptor(
                    householdId: householdId,
                    householdName: nil,
                    domain: .tasks,
                    changeCount: taskIDs.count
                )
            )
        }

        if !ideaIDs.isEmpty {
            descriptors.append(
                PassiveSharedActivityAlertDescriptor(
                    householdId: householdId,
                    householdName: nil,
                    domain: .ideas,
                    changeCount: ideaIDs.count
                )
            )
        }

        return descriptors
    }

    private func scheduleForegroundRepairIfNeeded(
        for batch: HouseholdSyncBatch,
        fetchResult: UIBackgroundFetchResult
    ) {
        guard applicationStateProvider() == .active,
              (batch.diagnostics.activeMemberCount ?? 0) > 1
        else {
            cancelForegroundRepair()
            cancelOwnerFallback()
            return
        }

        updateOwnerFallbackIfNeeded(for: batch)
        guard foregroundRepairConfiguration.isEnabled else { return }

        switch batch.diagnostics.reason {
        case .remotePush:
            guard batch.diagnostics.direction != .ownerToParticipant else {
                cancelForegroundRepair(reason: "remotePushPriority")
                recordSchedulerProgress(
                    "sync.scheduler.skipped reason=remotePush followUpAlreadyActive=true direction=\(batch.diagnostics.direction.rawValue)"
                )
                return
            }
            startBurstForegroundRepair(trigger: batch.diagnostics.reason)
        case .appBecameActive, .localMutationFollowUp, .householdJoined, .householdSwitched:
            startBurstForegroundRepair(trigger: batch.diagnostics.reason)
        case .manualRefresh:
            cancelForegroundRepair()
        case .foregroundRepairWindow:
            switch fetchResult {
            case .newData:
                handleForegroundRepairDataPass()
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

    private func updateOwnerFallbackIfNeeded(for batch: HouseholdSyncBatch) {
        let applicationState = applicationStateProvider()
        let activeMemberCount = batch.diagnostics.activeMemberCount ?? 0
        let shouldScheduleOwnerFallback =
            foregroundRepairConfiguration.ownerFallbackMaxPassCount > 0 &&
            batch.diagnostics.syncRole == .owner &&
            applicationState == .active &&
            activeMemberCount > 1

        recordSchedulerProgress(
            "sync.scheduler.ownerFallbackDecision eligible=\(shouldScheduleOwnerFallback) role=\(syncRoleLabel(batch.diagnostics.syncRole)) scope=\(syncScopeLabel(batch.diagnostics.syncScope)) direction=\(batch.diagnostics.direction.rawValue) reason=\(schedulerReasonLabel(batch.diagnostics.reason)) activeMembers=\(activeMemberCount) appState=\(applicationStateLabel(applicationState))"
        )

        guard shouldScheduleOwnerFallback else {
            cancelOwnerFallback()
            return
        }

        switch batch.diagnostics.reason {
        case .appBecameActive, .householdJoined, .householdSwitched, .localMutationFollowUp:
            startOwnerFallback(trigger: batch.diagnostics.reason)
        case .foregroundRepairWindow:
            handleOwnerFallbackPassCompletion()
        case .remotePush, .manualRefresh, .debugRepair:
            break
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

    private func handleForegroundRepairDataPass() {
        switch currentForegroundRepairMode {
        case .burst:
            remainingForegroundRepairBurstPasses = max(
                remainingForegroundRepairBurstPasses - 1,
                0
            )
            consecutiveForegroundRepairNoDataPasses = 0

            guard remainingForegroundRepairBurstPasses > 0 else {
                startSteadyForegroundRepairIfNeeded()
                return
            }
            scheduleNextForegroundRepairPass(
                intervalNanoseconds: foregroundRepairConfiguration.burstIntervalNanoseconds
            )
        case .steady:
            remainingForegroundRepairSteadyPasses = max(
                remainingForegroundRepairSteadyPasses - 1,
                0
            )
            consecutiveForegroundRepairNoDataPasses = 0

            guard remainingForegroundRepairSteadyPasses > 0 else {
                cancelForegroundRepair()
                return
            }
            scheduleNextForegroundRepairPass(
                intervalNanoseconds: foregroundRepairConfiguration.steadyIntervalNanoseconds
            )
        }
    }

    func recordSchedulerProgress(_ operation: String) {
        CloudKitDiagnosticsState.shared.recordProgress(operation: operation)
    }

    private func recordNotificationProgress(_ operation: String) {
        CloudKitDiagnosticsState.shared.recordProgress(operation: operation)
    }

    private func prioritizeRemotePushIfNeeded(_ reason: HouseholdSyncReason) {
        guard case .remotePush(context: .sharedDatabase) = reason else { return }
        cancelForegroundRepair(reason: "remotePushPriority")
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

    private func triggerSourceLabel(_ reason: HouseholdSyncReason) -> String {
        switch HouseholdSyncEventSource(reason: reason) {
        case .remote:
            "push"
        case .foregroundRepair:
            "foregroundRepair"
        case .manual:
            "manual"
        case .localFollowUp:
            "localMutationFollowUp"
        case .lifecycle:
            "lifecycle"
        case .debug:
            "debug"
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

    private func batchClassificationLabel(_ classification: HouseholdSyncBatchClassification) -> String {
        switch classification {
        case .bootstrap:
            "bootstrap"
        case .steadyStateRemote:
            "steadyStateRemote"
        case .steadyStateLifecycle:
            "steadyStateLifecycle"
        }
    }

    private func startOwnerFallback(trigger: HouseholdSyncReason) {
        remainingOwnerFallbackPasses = foregroundRepairConfiguration.ownerFallbackMaxPassCount
        recordSchedulerProgress(
            "sync.scheduler.started reason=\(schedulerReasonLabel(trigger)) ownerFallback=true intervalNs=\(foregroundRepairConfiguration.ownerFallbackIntervalNanoseconds) maxPasses=\(remainingOwnerFallbackPasses)"
        )
        scheduleNextOwnerFallbackPass()
    }

    private func handleOwnerFallbackPassCompletion() {
        guard scheduledOwnerFallbackTask != nil else { return }

        remainingOwnerFallbackPasses = max(remainingOwnerFallbackPasses - 1, 0)
        guard remainingOwnerFallbackPasses > 0 else {
            cancelOwnerFallback()
            return
        }
        scheduleNextOwnerFallbackPass()
    }

    private func scheduleNextOwnerFallbackPass() {
        guard remainingOwnerFallbackPasses > 0 else {
            cancelOwnerFallback()
            return
        }

        scheduledOwnerFallbackTask?.cancel()
        let intervalNanoseconds = foregroundRepairConfiguration.ownerFallbackIntervalNanoseconds
        recordSchedulerProgress(
            "sync.scheduler.scheduled kind=ownerFallback intervalNs=\(intervalNanoseconds) remainingPasses=\(remainingOwnerFallbackPasses)"
        )
        scheduledOwnerFallbackTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            if intervalNanoseconds > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: intervalNanoseconds)
            }
            guard !_Concurrency.Task.isCancelled else { return }
            recordSchedulerProgress(
                "sync.scheduler.fired kind=ownerFallback remainingPasses=\(remainingOwnerFallbackPasses)"
            )
            _ = await performSync(reason: .foregroundRepairWindow)
        }
    }

    private func scheduleNextForegroundRepairPass(intervalNanoseconds: UInt64) {
        scheduledForegroundRepairTask?.cancel()
        recordSchedulerProgress(
            "sync.scheduler.scheduled kind=foregroundRepair mode=\(foregroundRepairModeLabel(currentForegroundRepairMode)) intervalNs=\(intervalNanoseconds) remainingBurstPasses=\(remainingForegroundRepairBurstPasses) remainingSteadyPasses=\(remainingForegroundRepairSteadyPasses)"
        )
        scheduledForegroundRepairTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            if intervalNanoseconds > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: intervalNanoseconds)
            }
            guard !_Concurrency.Task.isCancelled else { return }
            recordSchedulerProgress(
                "sync.scheduler.fired kind=foregroundRepair mode=\(foregroundRepairModeLabel(currentForegroundRepairMode)) remainingBurstPasses=\(remainingForegroundRepairBurstPasses) remainingSteadyPasses=\(remainingForegroundRepairSteadyPasses)"
            )
            _ = await performSync(reason: .foregroundRepairWindow)
        }
    }

    private func cancelForegroundRepair(reason: String? = nil) {
        let hadScheduledPass = scheduledForegroundRepairTask != nil
        let hadRemainingPasses =
            remainingForegroundRepairBurstPasses > 0 ||
            remainingForegroundRepairSteadyPasses > 0 ||
            consecutiveForegroundRepairNoDataPasses > 0
        scheduledForegroundRepairTask?.cancel()
        scheduledForegroundRepairTask = nil
        currentForegroundRepairMode = .burst
        remainingForegroundRepairBurstPasses = 0
        remainingForegroundRepairSteadyPasses = 0
        consecutiveForegroundRepairNoDataPasses = 0

        guard let reason, hadScheduledPass || hadRemainingPasses else { return }
        recordSchedulerProgress(
            "sync.scheduler.cancelled kind=foregroundRepair reason=\(reason)"
        )
    }

    private func cancelOwnerFallback() {
        scheduledOwnerFallbackTask?.cancel()
        scheduledOwnerFallbackTask = nil
        remainingOwnerFallbackPasses = 0
    }

    private func foregroundRepairModeLabel(_ mode: ForegroundRepairMode) -> String {
        switch mode {
        case .burst:
            "burst"
        case .steady:
            "steady"
        }
    }

    private func backgroundFetchResultLabel(_ result: UIBackgroundFetchResult) -> String {
        switch result {
        case .newData:
            "newData"
        case .noData:
            "noData"
        case .failed:
            "failed"
        @unknown default:
            "unknown"
        }
    }

    private func syncRoleLabel(_ role: HouseholdSyncRole?) -> String {
        guard let role else { return "nil" }
        return switch role {
        case .owner:
            "owner"
        case .participant:
            "participant"
        }
    }

    private func syncScopeLabel(_ scope: CloudKitManager.HouseholdDatabaseScope?) -> String {
        guard let scope else { return "nil" }
        return switch scope {
        case .ownerPrivate:
            "ownerPrivate"
        case .participantShared:
            "participantShared"
        }
    }

    private func applicationStateLabel(_ state: UIApplication.State) -> String {
        switch state {
        case .active:
            "active"
        case .inactive:
            "inactive"
        case .background:
            "background"
        @unknown default:
            "unknown"
        }
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
