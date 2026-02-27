import Foundation

@MainActor
final class CloudKitDiagnosticsState: ObservableObject {
    static let shared = CloudKitDiagnosticsState()

    @Published var lastCloudKitError: String?
    @Published var lastCloudKitOperation: String?
    @Published var lastCloudKitErrorTimestampISO8601: String?

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
    }

    func clear() {
        lastCloudKitError = nil
        lastCloudKitOperation = nil
        lastCloudKitErrorTimestampISO8601 = nil
    }
}
