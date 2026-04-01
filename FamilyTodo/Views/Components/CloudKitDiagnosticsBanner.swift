import SwiftUI
import UIKit

struct CloudKitDiagnosticsBanner: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var diagnostics: CloudKitDiagnosticsState
    @State private var showDiagnosticsSheet = false

    private var latestProgressText: String? {
        diagnostics.lastCloudKitProgressOperation
    }

    private var latestProgressTimestamp: String? {
        diagnostics.lastCloudKitProgressTimestampISO8601
    }

    private var latestErrorText: String? {
        diagnostics.lastCloudKitError
    }

    private var latestErrorTimestamp: String? {
        diagnostics.lastCloudKitErrorTimestampISO8601
    }

    var body: some View {
        if diagnostics.hasVisibleDiagnostics {
            VStack(alignment: .leading, spacing: 10) {
                Label("CloudKit Diagnostics (Debug)", systemImage: "ladybug.fill")
                    .font(themeStore.font(for: .bodyStrong))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                if let latestProgressText {
                    diagnosticsRow(
                        title: "Latest event",
                        timestamp: latestProgressTimestamp,
                        value: latestProgressText,
                        tint: themeStore.accentTabColor
                    )
                }

                if let latestErrorText {
                    diagnosticsRow(
                        title: "Latest error",
                        timestamp: latestErrorTimestamp,
                        value: latestErrorText,
                        tint: .red
                    )
                }

                HStack(spacing: 12) {
                    Button("Open log") {
                        showDiagnosticsSheet = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Copy log") {
                        UIPasteboard.general.string = diagnostics.diagnosticsReport
                    }
                    .buttonStyle(.bordered)

                    Button("Clear") {
                        diagnostics.clear()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(themeStore.cardBackgroundColor.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeStore.dividerColor.opacity(0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("cloudKitDiagnosticsBanner")
            .sheet(isPresented: $showDiagnosticsSheet) {
                CloudKitDiagnosticsSheet()
                    .environmentObject(themeStore)
                    .environmentObject(diagnostics)
            }
        }
    }

    private func diagnosticsRow(
        title: String,
        timestamp: String?,
        value: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(themeStore.font(for: .bodyStrong))
                    .foregroundStyle(tint)

                if let timestamp {
                    Text(timestamp)
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }
            }

            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(themeStore.contentPrimaryColor)
                .textSelection(.enabled)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CloudKitDiagnosticsSheet: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var diagnostics: CloudKitDiagnosticsState
    @Environment(\.dismiss) private var dismiss

    @State private var showShareSheet = false
    @State private var copied = false
    @State private var cleared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(diagnostics.entries.reversed())) { entry in
                        diagnosticsEntryCard(entry)
                    }

                    if diagnostics.entries.isEmpty {
                        Text("No CloudKit diagnostics recorded.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                    }

                    if copied {
                        Text("Diagnostics copied to clipboard.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                    }

                    if cleared {
                        Text("Diagnostics history cleared.")
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .navigationTitle("CloudKit Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button("Copy diagnostics") {
                        UIPasteboard.general.string = diagnostics.diagnosticsReport
                        copied = true
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .buttonStyle(.bordered)

                    Button("Share diagnostics") {
                        showShareSheet = true
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .buttonStyle(.borderedProminent)

                    Button("Clear diagnostics") {
                        diagnostics.clear()
                        cleared = true
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            CloudKitDiagnosticsActivityView(activityItems: [diagnostics.diagnosticsReport])
        }
    }

    private func diagnosticsEntryCard(_ entry: CloudKitDiagnosticsEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.kind == .error ? "Error" : "Event")
                    .font(themeStore.font(for: .bodyStrong))
                    .foregroundStyle(entry.kind == .error ? Color.red : themeStore.accentTabColor)

                Spacer()

                Text(entry.timestampISO8601)
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(themeStore.contentSecondaryColor)
            }

            Text(entry.payload)
                .font(.footnote.monospaced())
                .foregroundStyle(themeStore.contentPrimaryColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(themeStore.cardBackgroundColor.opacity(0.9))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeStore.dividerColor.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct CloudKitDiagnosticsActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
