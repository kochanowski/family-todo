import CloudKit
import Combine
import Foundation
import SwiftUI
import UIKit

enum RemoteSyncPresentationDomain: Equatable {
    case shopping
    case tasks
    case ideas
}

enum RemoteSyncPresentationKind: Equatable {
    case additions
    case updates
}

struct RemoteSyncPresentation: Equatable {
    let domain: RemoteSyncPresentationDomain
    let kind: RemoteSyncPresentationKind
    let changeCount: Int
    let titles: [String]
}

struct InlineRemoteSyncFeedback: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

struct InlineRemoteSyncIndicator: Identifiable, Equatable {
    let id = UUID()
}

struct CloudKitSubscriptionPlan: Equatable {
    let databaseSubscriptionIDs: [String]
    let zoneSubscriptionID: String?

    var requiresOwnerZoneSubscription: Bool {
        zoneSubscriptionID != nil
    }
}

/// Manages CloudKit subscriptions for real-time change notifications
@MainActor
final class CloudKitSubscriptionManager: ObservableObject {
    static let shared = CloudKitSubscriptionManager()
    static let sharedDatabaseSubscriptionID = "shared-database-changes"
    static let privateDatabaseSubscriptionID = "private-database-changes"

    // MARK: - Published State

    @Published var pendingShoppingChanges: [String] = []
    @Published var pendingTaskChanges: [String] = []
    @Published var showNewItemsBanner = false
    @Published var newItemsCount = 0
    @Published private(set) var activeTab: AppTab = .shopping
    @Published private(set) var shoppingInlineFeedback: InlineRemoteSyncFeedback?
    @Published private(set) var shoppingInlineIndicator: InlineRemoteSyncIndicator?
    @Published private(set) var tasksInlineIndicator: InlineRemoteSyncIndicator?
    @Published private(set) var tasksInlineFeedback: InlineRemoteSyncFeedback?
    @Published private(set) var ideasInlineIndicator: InlineRemoteSyncIndicator?

    // MARK: - Private State

    /// Use CloudKitManager for consistent container access
    private let cloudKit = CloudKitManager.shared
    private var databaseSubscriptionIds: Set<String> = []
    private var householdZoneSubscriptionIds: Set<String> = []
    private var configuredUserId: String?
    private var configuredHouseholdId: UUID?
    private var configuredScope: CloudKitManager.HouseholdDatabaseScope?
    private var recentLocalMutationByRecordName: [String: Date] = [:]
    private var shoppingInlineDismissTask: _Concurrency.Task<Void, Never>?
    private var tasksInlineDismissTask: _Concurrency.Task<Void, Never>?
    private var ideasInlineDismissTask: _Concurrency.Task<Void, Never>?

    private let selfNoiseWindow: TimeInterval = 8
    private let inlineFeedbackDurationNanoseconds: UInt64 = 2_500_000_000

    // MARK: - Initialization

    init() {}

    static func shouldCreateZoneSubscription(
        for scope: CloudKitManager.HouseholdDatabaseScope
    ) -> Bool {
        scope == .ownerPrivate
    }

    static func makeSubscriptionPlan(
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope?
    ) -> CloudKitSubscriptionPlan {
        let zoneSubscriptionID: String?
        if let scope, shouldCreateZoneSubscription(for: scope) {
            let scopeName = scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
            zoneSubscriptionID = "household-zone-\(scopeName)-\(householdId.uuidString)"
        } else {
            zoneSubscriptionID = nil
        }

        let databaseSubscriptionIDs: [String] = switch scope {
        case .participantShared:
            [sharedDatabaseSubscriptionID]
        case .ownerPrivate, nil:
            [privateDatabaseSubscriptionID]
        }

        return CloudKitSubscriptionPlan(
            databaseSubscriptionIDs: databaseSubscriptionIDs,
            zoneSubscriptionID: zoneSubscriptionID
        )
    }

    // MARK: - Setup

    func configure(
        syncContext: HouseholdSyncContext?
    ) {
        guard let syncContext else { return }
        configure(
            userId: syncContext.currentUserId,
            householdId: syncContext.householdId,
            scope: syncContext.scope
        )
    }

    func configure(
        userId: String,
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope?
    ) {
        let configurationChanged =
            configuredUserId != userId ||
            configuredHouseholdId != householdId ||
            configuredScope != scope
        guard configurationChanged else { return }

        configuredUserId = userId
        configuredHouseholdId = householdId
        configuredScope = scope
        resetTransientPresentationState()
        recordSubscriptionProgress(
            "subscription.configure userId=\(userId) householdId=\(householdId.uuidString) scope=\(scopeLabel(scope))"
        )

        _Concurrency.Task {
            await setupSubscriptions(householdId: householdId, scope: scope)
            await registerForRemoteNotifications()
        }
    }

    // MARK: - Subscriptions

    private func setupSubscriptions(
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope?
    ) async {
        // Ensure CloudKit is ready before accessing
        await cloudKit.ensureReady()

        let container = await cloudKit.getContainer()
        let sharedDatabase = container.sharedCloudDatabase
        let privateDatabase = container.privateCloudDatabase
        let subscriptionPlan = Self.makeSubscriptionPlan(
            householdId: householdId,
            scope: scope
        )

        recordSubscriptionProgress(
            "subscription.plan householdId=\(householdId.uuidString) scope=\(scopeLabel(scope)) databaseIds=\(subscriptionPlan.databaseSubscriptionIDs.joined(separator: ",")) zoneId=\(subscriptionPlan.zoneSubscriptionID ?? "none")"
        )

        for subscriptionId in subscriptionPlan.databaseSubscriptionIDs {
            let database: CKDatabase = switch subscriptionId {
            case Self.privateDatabaseSubscriptionID:
                privateDatabase
            default:
                sharedDatabase
            }

            await createDatabaseSubscription(
                subscriptionId: subscriptionId,
                database: database
            )
        }

        await syncHouseholdZoneSubscriptions(
            householdId: householdId,
            scope: scope,
            sharedDatabase: sharedDatabase,
            privateDatabase: privateDatabase
        )
    }

    private func createDatabaseSubscription(
        subscriptionId: String,
        database: CKDatabase
    ) async {
        do {
            let existingSubscription = try await database.subscription(for: subscriptionId)
            databaseSubscriptionIds.insert(subscriptionId)
            recordSubscriptionProgress(
                "subscription.database.reused id=\(subscriptionId) type=\(type(of: existingSubscription))"
            )
            print(
                "[CloudKitSubscription] Reusing database subscription id=\(subscriptionId) type=\(type(of: existingSubscription))"
            )
            return
        } catch {
            print("[CloudKitSubscription] Database subscription lookup missed for id=\(subscriptionId): \(error.localizedDescription)")
        }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionId)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent push
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            let confirmedSubscription = try await database.subscription(for: subscriptionId)
            databaseSubscriptionIds.insert(subscriptionId)
            recordSubscriptionProgress(
                "subscription.database.created id=\(subscriptionId) type=\(type(of: confirmedSubscription))"
            )
            print(
                "✅ Created database subscription id=\(subscriptionId) confirmedType=\(type(of: confirmedSubscription))"
            )
        } catch {
            reportSubscriptionFailure(
                error,
                context: "createDatabaseSubscription.\(subscriptionId)"
            )
        }
    }

    private func syncHouseholdZoneSubscriptions(
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope?,
        sharedDatabase: CKDatabase,
        privateDatabase: CKDatabase
    ) async {
        let subscriptionPlan = Self.makeSubscriptionPlan(
            householdId: householdId,
            scope: scope
        )
        let requiredSubscriptionIds = Set(subscriptionPlan.zoneSubscriptionID.map { [$0] } ?? [])
        let obsoleteSubscriptionIds = householdZoneSubscriptionIds.subtracting(requiredSubscriptionIds)

        for subscriptionId in obsoleteSubscriptionIds {
            await deleteSubscriptionIfPresent(
                subscriptionId: subscriptionId,
                databases: [sharedDatabase, privateDatabase]
            )
            householdZoneSubscriptionIds.remove(subscriptionId)
        }

        guard let scope,
              Self.shouldCreateZoneSubscription(for: scope),
              let zoneID = try? await cloudKit.resolveSubscriptionZone(
                  householdId: householdId,
                  scope: scope
              )
        else {
            return
        }

        let database: CKDatabase = switch scope {
        case .ownerPrivate:
            privateDatabase
        case .participantShared:
            sharedDatabase
        }

        let subscriptionId = zoneSubscriptionID(
            householdId: householdId,
            scope: scope
        )
        await createZoneSubscription(
            subscriptionId: subscriptionId,
            database: database,
            zoneID: zoneID
        )
    }

    private func createZoneSubscription(
        subscriptionId: String,
        database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async {
        do {
            let existingSubscription = try await database.subscription(for: subscriptionId)
            householdZoneSubscriptionIds.insert(subscriptionId)
            recordSubscriptionProgress(
                "subscription.zone.reused id=\(subscriptionId) zone=\(zoneID.zoneName)|\(zoneID.ownerName) type=\(type(of: existingSubscription))"
            )
            print(
                "[CloudKitSubscription] Reusing zone subscription id=\(subscriptionId) zone=\(zoneID.zoneName)|\(zoneID.ownerName) type=\(type(of: existingSubscription))"
            )
            return
        } catch {
            print(
                "[CloudKitSubscription] Zone subscription lookup missed for id=\(subscriptionId) zone=\(zoneID.zoneName)|\(zoneID.ownerName): \(error.localizedDescription)"
            )
        }

        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: subscriptionId
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            let confirmedSubscription = try await database.subscription(for: subscriptionId)
            householdZoneSubscriptionIds.insert(subscriptionId)
            recordSubscriptionProgress(
                "subscription.zone.created id=\(subscriptionId) zone=\(zoneID.zoneName)|\(zoneID.ownerName) type=\(type(of: confirmedSubscription))"
            )
            print(
                "✅ Created zone subscription id=\(subscriptionId) zone=\(zoneID.zoneName)|\(zoneID.ownerName) confirmedType=\(type(of: confirmedSubscription))"
            )
        } catch {
            reportSubscriptionFailure(
                error,
                context: "createZoneSubscription.\(subscriptionId).\(zoneID.zoneName)"
            )
        }
    }

    private func deleteSubscriptionIfPresent(
        subscriptionId: String,
        databases: [CKDatabase]
    ) async {
        for database in databases {
            do {
                try await database.deleteSubscription(withID: subscriptionId)
                recordSubscriptionProgress("subscription.deleted id=\(subscriptionId)")
                print("🗑️ Removed subscription: \(subscriptionId)")
            } catch let ckError as CKError where ckError.code == .unknownItem {
                continue
            } catch {
                reportSubscriptionFailure(
                    error,
                    context: "deleteSubscriptionIfPresent.\(subscriptionId)"
                )
            }
        }
    }

    private func zoneSubscriptionID(
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope
    ) -> String {
        let scopeName = scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        return "household-zone-\(scopeName)-\(householdId.uuidString)"
    }

    private func zoneSubscriptionIDs(
        for householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope?
    ) -> [String] {
        guard let zoneSubscriptionID = Self.makeSubscriptionPlan(
            householdId: householdId,
            scope: scope
        ).zoneSubscriptionID else {
            return []
        }
        return [zoneSubscriptionID]
    }

    // MARK: - Push Notification Registration

    private func registerForRemoteNotifications() async {
        #if !CI
            recordSubscriptionProgress("push.registration.requested")
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        #endif
    }

    // MARK: - Handle Remote Notification

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            print("[CloudKitSubscription] Ignoring remote notification because it was not recognized as CloudKit.")
            return
        }

        if let dbNotification = notification as? CKDatabaseNotification {
            recordSubscriptionProgress("push.received type=database")
            print("[CloudKitSubscription] Received database notification.")
            handleDatabaseNotification(dbNotification)
        } else if let zoneNotification = notification as? CKRecordZoneNotification {
            recordSubscriptionProgress("push.received type=recordZone")
            print("[CloudKitSubscription] Received record-zone notification.")
            handleRecordZoneNotification(zoneNotification)
        } else if let queryNotification = notification as? CKQueryNotification {
            let recordType = (queryNotification.recordFields?["recordType"] as? String) ?? "unknown"
            recordSubscriptionProgress("push.received type=query recordType=\(recordType)")
            print("[CloudKitSubscription] Received query notification for recordType=\(recordType).")
            handleQueryNotification(queryNotification)
        } else {
            print("[CloudKitSubscription] Received CloudKit notification of unsupported type \(notification.notificationType.rawValue).")
        }
    }

    func registerLocalMutation(recordName: String?) {
        let now = Date()
        if let recordName {
            recentLocalMutationByRecordName[recordName] = now
        }
        pruneLocalMutationNoiseWindow(relativeTo: now)
    }

    private func pruneLocalMutationNoiseWindow(relativeTo now: Date) {
        recentLocalMutationByRecordName = recentLocalMutationByRecordName.filter { _, timestamp in
            now.timeIntervalSince(timestamp) <= selfNoiseWindow
        }
    }

    private func isLikelySelfNoise(recordName: String?) -> Bool {
        let now = Date()
        pruneLocalMutationNoiseWindow(relativeTo: now)

        if let recordName,
           let timestamp = recentLocalMutationByRecordName[recordName],
           now.timeIntervalSince(timestamp) <= selfNoiseWindow
        {
            return true
        }
        return false
    }

    private func handleDatabaseNotification(_: CKDatabaseNotification) {
        guard !isLikelySelfNoise(recordName: nil) else {
            print("[CloudKitSubscription] Dropping database notification as likely self-noise.")
            return
        }
        print(
            "[CloudKitSubscription] Database notification accepted. Waiting for hydrated refresh summary."
        )
    }

    private func handleRecordZoneNotification(_: CKRecordZoneNotification) {
        guard !isLikelySelfNoise(recordName: nil) else {
            print("[CloudKitSubscription] Dropping record-zone notification as likely self-noise.")
            return
        }
        print(
            "[CloudKitSubscription] Record-zone notification accepted. Waiting for hydrated refresh summary."
        )
    }

    private func handleQueryNotification(_ notification: CKQueryNotification) {
        let recordType = (notification.recordFields?["recordType"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let recordName = notification.recordID?.recordName
        guard !isLikelySelfNoise(recordName: recordName) else {
            print("[CloudKitSubscription] Dropping query notification as likely self-noise for recordName=\(recordName ?? "unknown").")
            return
        }

        guard let recordType, !recordType.isEmpty, recordType != "Unknown" else {
            return
        }

        if recordType == "Household" || recordType == "Member" {
            return
        }
        print(
            "[CloudKitSubscription] Query notification accepted for recordType=\(recordType). Waiting for hydrated refresh summary."
        )
    }

    // MARK: - Presentation State

    func updateActiveTab(_ tab: AppTab) {
        activeTab = tab
        if tab == .shopping {
            dismissBanner()
        }
    }

    func publishRemoteSyncPresentation(
        _ presentation: RemoteSyncPresentation,
        applicationState: UIApplication.State? = nil
    ) {
        let resolvedApplicationState = applicationState ?? UIApplication.shared.applicationState
        guard resolvedApplicationState == .active else { return }

        switch presentation.domain {
        case .shopping:
            publishShoppingPresentation(presentation)
        case .tasks:
            publishTasksPresentation(presentation)
        case .ideas:
            publishIdeasPresentation(presentation)
        }
    }

    func consumeSyncBatch(
        _ batch: HouseholdSyncBatch,
        applicationState: UIApplication.State? = nil
    ) {
        guard batch.classification == .steadyStateRemote else { return }
        let resolvedApplicationState = applicationState ?? UIApplication.shared.applicationState

        for event in batch.events {
            guard event.source == .remote else { continue }
            guard let presentation = presentation(for: event) else { continue }
            publishRemoteSyncPresentation(
                presentation,
                applicationState: resolvedApplicationState
            )
        }
    }

    private func presentation(for event: HouseholdSyncEvent) -> RemoteSyncPresentation? {
        switch event.kind {
        case let .shoppingAdded(ids, titles):
            guard let additionPayload = filteredShoppingAdditionPayload(
                ids: ids,
                titles: titles
            ) else {
                return nil
            }
            return RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: additionPayload.ids.count,
                titles: additionPayload.titles
            )
        case let .shoppingUpdated(itemIDs, bundleIDs),
             let .shoppingRemoved(itemIDs, bundleIDs):
            return shoppingMutationPresentation(itemIDs: itemIDs, bundleIDs: bundleIDs)
        case let .tasksChanged(addedIDs, changedIDs, removedIDs):
            return boardPresentation(
                domain: .tasks,
                addedIDs: addedIDs,
                changedIDs: changedIDs,
                removedIDs: removedIDs
            )
        case let .ideasChanged(addedIDs, changedIDs, removedIDs):
            return boardPresentation(
                domain: .ideas,
                addedIDs: addedIDs,
                changedIDs: changedIDs,
                removedIDs: removedIDs
            )
        case let .backlogCategoriesChanged(addedIDs, changedIDs, removedIDs):
            let changeCount =
                filteredNonLocalIDs(addedIDs).count +
                filteredNonLocalIDs(changedIDs).count +
                filteredNonLocalIDs(removedIDs).count
            guard changeCount > 0 else { return nil }
            return RemoteSyncPresentation(
                domain: .ideas,
                kind: .updates,
                changeCount: changeCount,
                titles: []
            )
        default:
            return nil
        }
    }

    private func shoppingMutationPresentation(
        itemIDs: Set<UUID>,
        bundleIDs: Set<UUID>
    ) -> RemoteSyncPresentation? {
        guard !shouldSuppressShoppingMutationPresentation(
            itemIDs: itemIDs,
            bundleIDs: bundleIDs
        ) else {
            return nil
        }

        let changeCount = itemIDs.count + bundleIDs.count
        guard changeCount > 0 else { return nil }

        return RemoteSyncPresentation(
            domain: .shopping,
            kind: .updates,
            changeCount: changeCount,
            titles: []
        )
    }

    private func boardPresentation(
        domain: RemoteSyncPresentationDomain,
        addedIDs: Set<UUID>,
        changedIDs: Set<UUID>,
        removedIDs: Set<UUID>
    ) -> RemoteSyncPresentation? {
        let nonLocalAddedIDs = filteredNonLocalIDs(addedIDs)
        let nonLocalChangedIDs = filteredNonLocalIDs(changedIDs)
        let nonLocalRemovedIDs = filteredNonLocalIDs(removedIDs)
        let updateCount = nonLocalChangedIDs.count + nonLocalRemovedIDs.count

        if !nonLocalAddedIDs.isEmpty {
            return RemoteSyncPresentation(
                domain: domain,
                kind: .additions,
                changeCount: nonLocalAddedIDs.count,
                titles: []
            )
        }

        guard updateCount > 0 else { return nil }
        return RemoteSyncPresentation(
            domain: domain,
            kind: .updates,
            changeCount: updateCount,
            titles: []
        )
    }

    func shouldSuppressSharedShoppingAlert(
        applicationState: UIApplication.State? = nil
    ) -> Bool {
        shouldSuppressPassiveSharedActivityAlert(applicationState: applicationState)
    }

    func shouldSuppressPassiveSharedActivityAlert(
        applicationState: UIApplication.State? = nil
    ) -> Bool {
        let resolvedApplicationState = applicationState ?? UIApplication.shared.applicationState
        return resolvedApplicationState == .active
    }

    func shouldSuppressHouseholdCelebrationAlert(
        applicationState: UIApplication.State? = nil
    ) -> Bool {
        let resolvedApplicationState = applicationState ?? UIApplication.shared.applicationState
        return resolvedApplicationState == .active
    }

    func dismissBanner() {
        withAnimation(WowAnimation.easeOut) {
            showNewItemsBanner = false
        }
        pendingShoppingChanges.removeAll()
        pendingTaskChanges.removeAll()
        newItemsCount = 0
    }

    func resetTransientPresentationState() {
        dismissBanner()
        shoppingInlineDismissTask?.cancel()
        shoppingInlineDismissTask = nil
        shoppingInlineFeedback = nil
        shoppingInlineIndicator = nil
        tasksInlineDismissTask?.cancel()
        tasksInlineDismissTask = nil
        tasksInlineIndicator = nil
        tasksInlineFeedback = nil
        ideasInlineDismissTask?.cancel()
        ideasInlineDismissTask = nil
        ideasInlineIndicator = nil
    }

    private func publishShoppingPresentation(_ presentation: RemoteSyncPresentation) {
        switch presentation.kind {
        case .additions:
            guard presentation.changeCount > 0 else { return }
            if activeTab == .shopping {
                publishShoppingInlineIndicator()
                dismissBanner()
            } else {
                let shouldAnimateBanner = !showNewItemsBanner
                newItemsCount += presentation.changeCount
                if shouldAnimateBanner {
                    HapticManager.selection()
                    withAnimation(WowAnimation.spring) {
                        showNewItemsBanner = true
                    }
                }
            }
        case .updates:
            guard activeTab == .shopping else { return }
            publishShoppingInlineIndicator()
        }
    }

    private func publishTasksPresentation(_: RemoteSyncPresentation) {
        guard activeTab == .tasks else { return }
        publishInlineIndicator(for: .tasks)
    }

    private func publishIdeasPresentation(_: RemoteSyncPresentation) {
        guard activeTab == .backlog else { return }
        publishInlineIndicator(for: .ideas)
    }

    private func publishInlineIndicator(for domain: RemoteSyncPresentationDomain) {
        let indicator = InlineRemoteSyncIndicator()

        switch domain {
        case .shopping:
            shoppingInlineDismissTask?.cancel()
            withAnimation(WowAnimation.spring) {
                shoppingInlineIndicator = indicator
                shoppingInlineFeedback = nil
            }
            shoppingInlineDismissTask = scheduleInlineDismiss(
                for: .shopping,
                feedbackId: indicator.id
            )
        case .tasks:
            tasksInlineDismissTask?.cancel()
            withAnimation(WowAnimation.spring) {
                tasksInlineIndicator = indicator
                tasksInlineFeedback = nil
            }
            tasksInlineDismissTask = scheduleInlineDismiss(
                for: .tasks,
                feedbackId: indicator.id
            )
        case .ideas:
            ideasInlineDismissTask?.cancel()
            withAnimation(WowAnimation.spring) {
                ideasInlineIndicator = indicator
            }
            ideasInlineDismissTask = scheduleInlineDismiss(
                for: .ideas,
                feedbackId: indicator.id
            )
        }
    }

    private func publishShoppingInlineIndicator() {
        publishInlineIndicator(for: .shopping)
    }

    private func scheduleInlineDismiss(
        for domain: RemoteSyncPresentationDomain,
        feedbackId: UUID
    ) -> _Concurrency.Task<Void, Never> {
        _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            try? await _Concurrency.Task.sleep(nanoseconds: inlineFeedbackDurationNanoseconds)
            guard !_Concurrency.Task.isCancelled else { return }

            switch domain {
            case .shopping:
                guard shoppingInlineIndicator?.id == feedbackId else { return }
                withAnimation(WowAnimation.easeOut) {
                    self.shoppingInlineIndicator = nil
                    self.shoppingInlineFeedback = nil
                }
                shoppingInlineDismissTask = nil
            case .tasks:
                guard tasksInlineIndicator?.id == feedbackId else { return }
                withAnimation(WowAnimation.easeOut) {
                    self.tasksInlineIndicator = nil
                    self.tasksInlineFeedback = nil
                }
                tasksInlineDismissTask = nil
            case .ideas:
                guard ideasInlineIndicator?.id == feedbackId else { return }
                withAnimation(WowAnimation.easeOut) {
                    self.ideasInlineIndicator = nil
                }
                ideasInlineDismissTask = nil
            }
        }
    }

    func filteredShoppingAdditionPayload(
        ids: Set<UUID>,
        titles: [String]
    ) -> (ids: Set<UUID>, titles: [String])? {
        guard !ids.isEmpty else { return nil }
        let nonLocalIDs = filteredNonLocalIDs(ids)
        guard !nonLocalIDs.isEmpty else { return nil }
        return (Set(nonLocalIDs), titles)
    }

    func filteredNonLocalIDs(_ ids: Set<UUID>) -> Set<UUID> {
        ids.filter { !isLikelySelfNoise(recordName: $0.uuidString) }
    }

    func shouldSuppressShoppingMutationPresentation(
        itemIDs: Set<UUID>,
        bundleIDs: Set<UUID>
    ) -> Bool {
        let recordNames = itemIDs.map(\.uuidString) + bundleIDs.map(\.uuidString)
        guard !recordNames.isEmpty else { return true }
        return recordNames.allSatisfy { isLikelySelfNoise(recordName: $0) }
    }

    private func reportSubscriptionFailure(_ error: Error, context: String) {
        print("[CloudKitSubscription] \(context) failed: \(error.localizedDescription)")
        CloudKitDiagnosticsState.shared.record(error: error, operation: context)
    }

    private func recordSubscriptionProgress(_ operation: String) {
        CloudKitDiagnosticsState.shared.recordProgress(operation: operation)
    }

    private func scopeLabel(_ scope: CloudKitManager.HouseholdDatabaseScope?) -> String {
        guard let scope else { return "nil" }
        return switch scope {
        case .ownerPrivate:
            "ownerPrivate"
        case .participantShared:
            "participantShared"
        }
    }

    // MARK: - Cleanup

    func removeSubscriptions() async {
        let container = await cloudKit.getContainer()
        let databases = [
            container.sharedCloudDatabase,
            container.privateCloudDatabase,
        ]

        for subscriptionId in databaseSubscriptionIds.union(householdZoneSubscriptionIds) {
            await deleteSubscriptionIfPresent(subscriptionId: subscriptionId, databases: databases)
        }
        databaseSubscriptionIds.removeAll()
        householdZoneSubscriptionIds.removeAll()
        configuredUserId = nil
        configuredHouseholdId = nil
        configuredScope = nil
        resetTransientPresentationState()
    }
}
