import Foundation

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
    let kind: Kind
    let timestampISO8601: String
    let operation: String
    let payload: String

    init(
        id: UUID = UUID(),
        kind: Kind,
        timestampISO8601: String,
        operation: String,
        payload: String
    ) {
        self.id = id
        self.kind = kind
        self.timestampISO8601 = timestampISO8601
        self.operation = operation
        self.payload = payload
    }

    var reportSection: String {
        [
            "timestamp=\(timestampISO8601)",
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
        let nsError = error as NSError
        let timestamp = ISO8601DateFormatter().string(from: Date())

        let payload = [
            "operation=\(operation)",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(error.localizedDescription)",
            "reflecting=\(String(reflecting: error))",
        ].joined(separator: "\n")

        lastCloudKitOperation = operation
        lastCloudKitErrorTimestampISO8601 = timestamp
        lastCloudKitError = payload
        appendEntry(
            CloudKitDiagnosticsEntry(
                kind: .error,
                timestampISO8601: timestamp,
                operation: operation,
                payload: payload
            )
        )
    }

    func recordProgress(operation: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        lastCloudKitProgressOperation = operation
        lastCloudKitProgressTimestampISO8601 = timestamp
        appendEntry(
            CloudKitDiagnosticsEntry(
                kind: .progress,
                timestampISO8601: timestamp,
                operation: operation,
                payload: operation
            )
        )
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

    var diagnosticsReport: String {
        guard !entries.isEmpty else {
            return "No CloudKit diagnostics recorded."
        }

        return entries
            .map(\.reportSection)
            .joined(separator: "\n\n---\n\n")
    }

    private func appendEntry(_ entry: CloudKitDiagnosticsEntry) {
        entries.append(entry)
        if entries.count > maxEntryCount {
            entries.removeFirst(entries.count - maxEntryCount)
        }
        updateTriggerSummary(with: entry)
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

        if let lastErrorEntry = entries.last(where: { $0.kind == .error }) {
            lastCloudKitOperation = lastErrorEntry.operation
            lastCloudKitErrorTimestampISO8601 = lastErrorEntry.timestampISO8601
            lastCloudKitError = lastErrorEntry.payload
        }

        if let lastProgressEntry = entries.last(where: { $0.kind == .progress }) {
            lastCloudKitProgressOperation = lastProgressEntry.operation
            lastCloudKitProgressTimestampISO8601 = lastProgressEntry.timestampISO8601
        }

        for entry in entries {
            updateTriggerSummary(with: entry)
        }
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
                guard let separator = token.firstIndex(of: "=") else { return }
                let key = String(token[..<separator])
                let valueStart = token.index(separator, offsetBy: 1)
                let value = String(token[valueStart...])
                result[key] = value
            }
    }
}
