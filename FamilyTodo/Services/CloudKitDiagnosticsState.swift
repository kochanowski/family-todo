import Foundation

struct CloudKitDiagnosticsEntry: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case progress
        case error
    }

    let id = UUID()
    let kind: Kind
    let timestampISO8601: String
    let operation: String
    let payload: String

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

    private let maxEntryCount = 80

    private init() {}

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
    }
}
