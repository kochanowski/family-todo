import SwiftUI
import UIKit

struct StartupRecoveryView: View {
    let message: String
    let diagnostics: BootstrapDiagnostics?

    @State private var diagnosticsCopied = false
    @State private var resetRequested = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(.orange)

            Text("Startup Recovery")
                .font(.title2.weight(.semibold))

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Copy diagnostics") {
                UIPasteboard.general.string = diagnosticsText
                diagnosticsCopied = true
            }
            .buttonStyle(.bordered)

            Button("Request local reset") {
                SwiftDataContainerFactory.requestStoreReset(reason: .startupRecoveryManual)
                resetRequested = true
            }
            .buttonStyle(.borderedProminent)

            if diagnosticsCopied {
                Text("Diagnostics copied to clipboard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if resetRequested {
                Text("Close and reopen the app to apply local reset.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }

    private var diagnosticsText: String {
        guard let diagnostics else {
            return "No diagnostics available."
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(diagnostics),
              let json = String(data: data, encoding: .utf8)
        else {
            return "Diagnostics encoding failed."
        }

        return json
    }
}
