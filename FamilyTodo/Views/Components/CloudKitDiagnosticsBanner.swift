import SwiftUI
import UIKit

struct CloudKitDiagnosticsBanner: View {
    @EnvironmentObject private var diagnostics: CloudKitDiagnosticsState

    var body: some View {
        if let errorText = diagnostics.lastCloudKitError {
            VStack(alignment: .leading, spacing: 10) {
                Label("CloudKit Error (Debug)", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)

                Text(errorText)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button("Copy") {
                        UIPasteboard.general.string = errorText
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button("Clear") {
                        diagnostics.clear()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(Color.red.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("cloudKitDiagnosticsBanner")
        }
    }
}
