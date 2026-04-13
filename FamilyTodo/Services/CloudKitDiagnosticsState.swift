import Foundation

enum DiagnosticsSource: String, CaseIterable, Codable, Identifiable {
    case cloudKit
    case tabBar
    case revenueCat

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .cloudKit:
            "CloudKit"
        case .tabBar:
            "Tab Bar"
        case .revenueCat:
            "RevenueCat"
        }
    }
}

enum DiagnosticsFilter: String, CaseIterable, Identifiable {
    case all
    case tabBar
    case cloudKit
    case notifications
    case errors

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            "All"
        case .tabBar:
            "Tab Bar"
        case .cloudKit:
            "CloudKit"
        case .notifications:
            "Notifications"
        case .errors:
            "Errors"
        }
    }

    func includes(_ entry: CloudKitDiagnosticsEntry) -> Bool {
        switch self {
        case .all:
            true
        case .tabBar:
            entry.source == .tabBar
        case .cloudKit:
            entry.source == .cloudKit
        case .notifications:
            CloudKitDiagnosticsState.isNotificationOperation(entry.operation)
        case .errors:
            entry.kind == .error
        }
    }

    var showsTriggerSummary: Bool {
        self == .all || self == .cloudKit
    }

    var emptyStateMessage: String {
        switch self {
        case .all:
            "No diagnostics recorded."
        case .tabBar:
            "No tab bar diagnostics recorded."
        case .cloudKit:
            "No CloudKit diagnostics recorded."
        case .notifications:
            "No notification diagnostics recorded."
        case .errors:
            "No diagnostics errors recorded."
        }
    }
}

struct CloudKitTriggerSummary: Equatable, Codable {
    var syncRole: String?
    var syncScope: String?
    var subscriptionRequestSource: String?
    var subscriptionConfigurationStatus: String?
    var subscriptionPlanDatabaseIDs: [String] = []
    var subscriptionPlanZoneID: String?
    var pushRegistrationStatus: String?
    var pushRegistrationTimestampISO8601: String?
    var pushReceivedCount = 0
    var remotePushCount = 0
    var remoteHandlerInvocationCount = 0
    var lastPushReceivedTimestampISO8601: String?
    var lastRemotePushTimestampISO8601: String?
    var lastOwnerFallbackTimestampISO8601: String?
    var lastOwnerFallbackReason: String?
    var lastSchedulerReason: String?
    var lastFetchResult: String?

    var hasAnyValue: Bool {
        syncRole != nil ||
            syncScope != nil ||
            subscriptionRequestSource != nil ||
            subscriptionConfigurationStatus != nil ||
            !subscriptionPlanDatabaseIDs.isEmpty ||
            subscriptionPlanZoneID != nil ||
            pushRegistrationStatus != nil ||
            pushReceivedCount > 0 ||
            remotePushCount > 0 ||
            remoteHandlerInvocationCount > 0 ||
            lastOwnerFallbackTimestampISO8601 != nil ||
            lastSchedulerReason != nil ||
            lastFetchResult != nil
    }

    var subscriptionPlanDescription: String {
        let databaseDescription = subscriptionPlanDatabaseIDs.isEmpty
            ? "none"
            : subscriptionPlanDatabaseIDs.joined(separator: ",")
        let zoneDescription = subscriptionPlanZoneID ?? "none"
        return "db=\(databaseDescription) zone=\(zoneDescription)"
    }
}

struct CloudKitDiagnosticsEntry: Identifiable, Equatable, Codable {
    enum Kind: String, Equatable, Codable {
        case progress
        case error
    }

    let id: UUID
    let source: DiagnosticsSource
    let kind: Kind
    let timestampISO8601: String
    let operation: String
    let payload: String

    init(
        id: UUID = UUID(),
        source: DiagnosticsSource = .cloudKit,
        kind: Kind,
        timestampISO8601: String,
        operation: String,
        payload: String
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.timestampISO8601 = timestampISO8601
        self.operation = operation
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case kind
        case timestampISO8601
        case operation
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        source = try container.decodeIfPresent(DiagnosticsSource.self, forKey: .source) ?? .cloudKit
        kind = try container.decode(Kind.self, forKey: .kind)
        timestampISO8601 = try container.decode(String.self, forKey: .timestampISO8601)
        operation = try container.decode(String.self, forKey: .operation)
        payload = try container.decode(String.self, forKey: .payload)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encode(kind, forKey: .kind)
        try container.encode(timestampISO8601, forKey: .timestampISO8601)
        try container.encode(operation, forKey: .operation)
        try container.encode(payload, forKey: .payload)
    }

    var reportSection: String {
        [
            "timestamp=\(timestampISO8601)",
            "source=\(source.rawValue)",
            "kind=\(kind.rawValue)",
            "operation=\(operation)",
            payload,
        ].joined(separator: "\n")
    }
}

@MainActor
final class CloudKitDiagnosticsState: ObservableObject {
    static let shared = CloudKitDiagnosticsState()

    @Published var lastCloudKitError: String?
    @Published var lastCloudKitOperation: String?
    @Published var lastCloudKitErrorTimestampISO8601: String?
    @Published var lastCloudKitProgressOperation: String?
    @Published var lastCloudKitProgressTimestampISO8601: String?
    @Published private(set) var entries: [CloudKitDiagnosticsEntry] = []
    @Published private(set) var triggerSummary = CloudKitTriggerSummary()

    private let maxEntryCount = 200
    private let entriesStorageKey = "CloudKitDiagnosticsState.entries"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        entries = loadPersistedEntries()
        restoreTransientStateFromEntries()
    }

    func record(error: Error, operation: String) {
        record(error: error, operation: operation, source: .cloudKit)
    }

    func record(error: Error, operation: String, source: DiagnosticsSource) {
        let nsError = error as NSError
        let timestamp = ISO8601DateFormatter().string(from: Date())

        let payload = [
            "operation=\(operation)",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(error.localizedDescription)",
            "reflecting=\(String(reflecting: error))",
        ].joined(separator: "\n")

        if source == .cloudKit {
            lastCloudKitOperation = operation
            lastCloudKitErrorTimestampISO8601 = timestamp
            lastCloudKitError = payload
        }
        appendEntry(
            CloudKitDiagnosticsEntry(
                source: source,
                kind: .error,
                timestampISO8601: timestamp,
                operation: operation,
                payload: payload
            )
        )
    }

    func recordProgress(operation: String) {
        recordProgress(operation: operation, source: .cloudKit)
    }

    func recordProgress(
        operation: String,
        source: DiagnosticsSource,
        payload: String? = nil
    ) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        if source == .cloudKit {
            lastCloudKitProgressOperation = operation
            lastCloudKitProgressTimestampISO8601 = timestamp
        }
        appendEntry(
            CloudKitDiagnosticsEntry(
                source: source,
                kind: .progress,
                timestampISO8601: timestamp,
                operation: operation,
                payload: payload ?? operation
            )
        )
    }

    func recordTabBarEvent(operation: String, payload: String) {
        recordProgress(operation: operation, source: .tabBar, payload: payload)
    }

    func recordMessage(
        operation: String,
        payload: String,
        source: DiagnosticsSource,
        kind: CloudKitDiagnosticsEntry.Kind = .progress
    ) {
        switch kind {
        case .progress:
            recordProgress(operation: operation, source: source, payload: payload)
        case .error:
            let timestamp = ISO8601DateFormatter().string(from: Date())
            appendEntry(
                CloudKitDiagnosticsEntry(
                    source: source,
                    kind: .error,
                    timestampISO8601: timestamp,
                    operation: operation,
                    payload: payload
                )
            )
        }
    }

    func clear() {
        lastCloudKitError = nil
        lastCloudKitOperation = nil
        lastCloudKitErrorTimestampISO8601 = nil
        lastCloudKitProgressOperation = nil
        lastCloudKitProgressTimestampISO8601 = nil
        entries = []
        triggerSummary = CloudKitTriggerSummary()
        userDefaults.removeObject(forKey: entriesStorageKey)
    }

    func clearLastError() {
        lastCloudKitError = nil
        lastCloudKitOperation = nil
        lastCloudKitErrorTimestampISO8601 = nil
    }

    var hasVisibleDiagnostics: Bool {
        !entries.isEmpty || lastCloudKitError != nil || lastCloudKitProgressOperation != nil
    }

    var hasNotificationDiagnostics: Bool {
        !notificationEntries.isEmpty
    }

    var notificationEntries: [CloudKitDiagnosticsEntry] {
        entries.filter { Self.isNotificationOperation($0.operation) }
    }

    var diagnosticsReport: String {
        diagnosticsReport(filter: .all)
    }

    var notificationDiagnosticsReport: String {
        diagnosticsReport(filter: .notifications)
    }

    func diagnosticsReport(filter: DiagnosticsFilter) -> String {
        let filteredEntries = entries(matching: filter)
        guard !filteredEntries.isEmpty else {
            return filter.emptyStateMessage
        }

        return filteredEntries
            .map(\.reportSection)
            .joined(separator: "\n\n---\n\n")
    }

    func entries(matching filter: DiagnosticsFilter) -> [CloudKitDiagnosticsEntry] {
        entries.filter(filter.includes)
    }

    func latestEntry(
        matching filter: DiagnosticsFilter = .all,
        kind: CloudKitDiagnosticsEntry.Kind? = nil
    ) -> CloudKitDiagnosticsEntry? {
        entries.last { entry in
            filter.includes(entry) && (kind == nil || entry.kind == kind)
        }
    }

    private func appendEntry(_ entry: CloudKitDiagnosticsEntry) {
        entries.append(entry)
        if entries.count > maxEntryCount {
            entries.removeFirst(entries.count - maxEntryCount)
        }
        if entry.source == .cloudKit {
            updateTriggerSummary(with: entry)
        }
        persistEntries()
    }

    private func persistEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(data, forKey: entriesStorageKey)
    }

    private func loadPersistedEntries() -> [CloudKitDiagnosticsEntry] {
        guard let data = userDefaults.data(forKey: entriesStorageKey),
              let persistedEntries = try? JSONDecoder().decode(
                  [CloudKitDiagnosticsEntry].self,
                  from: data
              )
        else {
            return []
        }

        if persistedEntries.count > maxEntryCount {
            return Array(persistedEntries.suffix(maxEntryCount))
        }
        return persistedEntries
    }

    private func restoreTransientStateFromEntries() {
        triggerSummary = CloudKitTriggerSummary()

        if let lastErrorEntry = entries.last(where: { $0.kind == .error && $0.source == .cloudKit }) {
            lastCloudKitOperation = lastErrorEntry.operation
            lastCloudKitErrorTimestampISO8601 = lastErrorEntry.timestampISO8601
            lastCloudKitError = lastErrorEntry.payload
        }

        if let lastProgressEntry = entries.last(where: { $0.kind == .progress && $0.source == .cloudKit }) {
            lastCloudKitProgressOperation = lastProgressEntry.operation
            lastCloudKitProgressTimestampISO8601 = lastProgressEntry.timestampISO8601
        }

        for entry in entries {
            if entry.source == .cloudKit {
                updateTriggerSummary(with: entry)
            }
        }
    }

    nonisolated static func isNotificationOperation(_ operation: String) -> Bool {
        operation.hasPrefix("notification.")
    }

    private func updateTriggerSummary(with entry: CloudKitDiagnosticsEntry) {
        let values = parseKeyValuePairs(from: entry.operation)

        switch entry.operation {
        case let operation where operation.hasPrefix("subscription.configure.request"):
            triggerSummary.subscriptionRequestSource = values["source"]
            triggerSummary.syncRole = values["role"] ?? triggerSummary.syncRole
            triggerSummary.syncScope = values["scope"] ?? triggerSummary.syncScope
            triggerSummary.subscriptionConfigurationStatus = "requested"
        case let operation where operation.hasPrefix("subscription.configure.skipped"):
            triggerSummary.subscriptionRequestSource = values["source"] ?? triggerSummary.subscriptionRequestSource
            triggerSummary.subscriptionConfigurationStatus = "skipped:\(values["reason"] ?? "unknown")"
        case let operation where operation.hasPrefix("subscription.configure.completed"),
             let operation where operation.hasPrefix("subscription.configure userId="):
            triggerSummary.syncRole = values["role"] ?? triggerSummary.syncRole
            triggerSummary.syncScope = values["scope"] ?? triggerSummary.syncScope
            triggerSummary.subscriptionConfigurationStatus = "configured"
        case let operation where operation.hasPrefix("subscription.plan"):
            if let databaseIDs = values["databaseIds"], !databaseIDs.isEmpty {
                triggerSummary.subscriptionPlanDatabaseIDs = databaseIDs
                    .split(separator: ",")
                    .map(String.init)
            }
            if let zoneID = values["zoneId"], zoneID != "none" {
                triggerSummary.subscriptionPlanZoneID = zoneID
            } else {
                triggerSummary.subscriptionPlanZoneID = nil
            }
            triggerSummary.syncScope = values["scope"] ?? triggerSummary.syncScope
        case let operation where operation.hasPrefix("push.registration.requested"):
            triggerSummary.pushRegistrationStatus = "requested"
            triggerSummary.pushRegistrationTimestampISO8601 = entry.timestampISO8601
        case let operation where operation.hasPrefix("push.registration.succeeded"):
            triggerSummary.pushRegistrationStatus = "succeeded"
            triggerSummary.pushRegistrationTimestampISO8601 = entry.timestampISO8601
        case let operation where operation.hasPrefix("push.registration.failed"):
            triggerSummary.pushRegistrationStatus = "failed"
            triggerSummary.pushRegistrationTimestampISO8601 = entry.timestampISO8601
        case let operation where operation.hasPrefix("push.received"):
            triggerSummary.pushReceivedCount += 1
            triggerSummary.lastPushReceivedTimestampISO8601 = entry.timestampISO8601
        case let operation where operation.hasPrefix("remotePush"):
            triggerSummary.remotePushCount += 1
            triggerSummary.lastRemotePushTimestampISO8601 = entry.timestampISO8601
            if values["willInvokeHandler"] == "true" {
                triggerSummary.remoteHandlerInvocationCount += 1
            }
            triggerSummary.syncRole = values["role"] ?? triggerSummary.syncRole
        case let operation where operation.hasPrefix("sync.scheduler.started"):
            triggerSummary.lastSchedulerReason = values["reason"] ?? triggerSummary.lastSchedulerReason
            if values["ownerFallback"] == "true" {
                triggerSummary.lastOwnerFallbackReason = values["reason"]
                triggerSummary.lastOwnerFallbackTimestampISO8601 = entry.timestampISO8601
            }
        case let operation where operation.hasPrefix("sync.scheduler.fired"):
            if values["kind"] == "ownerFallback" {
                triggerSummary.lastOwnerFallbackTimestampISO8601 = entry.timestampISO8601
            }
        case let operation where operation.hasPrefix("sync.pass.completed"):
            triggerSummary.lastSchedulerReason = values["reason"] ?? triggerSummary.lastSchedulerReason
            triggerSummary.lastFetchResult = values["fetchResult"] ?? triggerSummary.lastFetchResult
        default:
            if entry.kind == .error, entry.operation == "registerForRemoteNotifications" {
                triggerSummary.pushRegistrationStatus = "failed"
                triggerSummary.pushRegistrationTimestampISO8601 = entry.timestampISO8601
            }
        }
    }

    private func parseKeyValuePairs(from operation: String) -> [String: String] {
        operation
            .split(separator: " ")
            .reduce(into: [String: String]()) { result, token in
                let components = token.split(
                    separator: "=",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                )
                guard let keyComponent = components.first, components.count == 2 else { return }
                let key = String(keyComponent)
                let value = String(components[1])
                result[key] = value
            }
    }
}
