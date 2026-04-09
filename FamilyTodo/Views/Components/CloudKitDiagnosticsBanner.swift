import SwiftUI
import UIKit

struct CloudKitDiagnosticsBanner: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var diagnostics: CloudKitDiagnosticsState
    @State private var showDiagnosticsSheet = false

    private var latestProgressEntry: CloudKitDiagnosticsEntry? {
        diagnostics.latestEntry(matching: .all, kind: .progress)
    }

    private var latestErrorEntry: CloudKitDiagnosticsEntry? {
        diagnostics.latestEntry(matching: .errors, kind: .error)
    }

    private var triggerSummary: CloudKitTriggerSummary {
        diagnostics.triggerSummary
    }

    var body: some View {
        if diagnostics.hasVisibleDiagnostics {
            VStack(alignment: .leading, spacing: 10) {
                Label("Diagnostics", systemImage: "ladybug.fill")
                    .font(themeStore.font(for: .bodyStrong))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                if triggerSummary.hasAnyValue {
                    triggerSummaryCard(triggerSummary)
                }

                if let latestProgressEntry {
                    diagnosticsRow(
                        title: "Latest event",
                        timestamp: latestProgressEntry.timestampISO8601,
                        value: latestProgressEntry.payload,
                        source: latestProgressEntry.source,
                        tint: themeStore.accentTabColor
                    )
                }

                if let latestErrorEntry {
                    diagnosticsRow(
                        title: "Latest error",
                        timestamp: latestErrorEntry.timestampISO8601,
                        value: latestErrorEntry.payload,
                        source: latestErrorEntry.source,
                        tint: .red
                    )
                }

                HStack(spacing: 12) {
                    Button("Open log") {
                        showDiagnosticsSheet = true
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .buttonStyle(.borderedProminent)

                    Button("Copy log") {
                        UIPasteboard.general.string = diagnostics.diagnosticsReport
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .buttonStyle(.bordered)

                    Button("Clear") {
                        diagnostics.clear()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(themeStore.surfaceElevatedColor.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeStore.contentSecondaryColor.opacity(0.4), lineWidth: 1)
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

    private func triggerSummaryCard(_ summary: CloudKitTriggerSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trigger Summary")
                .font(themeStore.font(for: .bodyStrong))
                .foregroundStyle(themeStore.accentTabColor)

            triggerSummaryRow(
                title: "Context",
                value: "\(summary.syncRole ?? "nil") / \(summary.syncScope ?? "nil")"
            )
            triggerSummaryRow(
                title: "Subscriptions",
                value: "\(summary.subscriptionConfigurationStatus ?? "unknown") via \(summary.subscriptionRequestSource ?? "unknown")"
            )
            triggerSummaryRow(
                title: "Plan",
                value: summary.subscriptionPlanDescription
            )
            triggerSummaryRow(
                title: "Push",
                value: "\(summary.pushRegistrationStatus ?? "unknown"), received=\(summary.pushReceivedCount), remote=\(summary.remotePushCount), handler=\(summary.remoteHandlerInvocationCount)"
            )
            triggerSummaryRow(
                title: "Last triggers",
                value: "push=\(summary.lastPushReceivedTimestampISO8601 ?? "never"), fallback=\(summary.lastOwnerFallbackTimestampISO8601 ?? "never")"
            )
            triggerSummaryRow(
                title: "Last sync",
                value: "\(summary.lastSchedulerReason ?? "unknown") / \(summary.lastFetchResult ?? "unknown")"
            )
        }
        .padding(10)
        .background(themeStore.surfaceColor.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func diagnosticsRow(
        title: String,
        timestamp: String?,
        value: String,
        source: DiagnosticsSource,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(themeStore.font(for: .bodyStrong))
                    .foregroundStyle(tint)

                sourceBadge(source)

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

    private func sourceBadge(_ source: DiagnosticsSource) -> some View {
        Text(source.displayName)
            .font(themeStore.font(for: .bodySmall))
            .foregroundStyle(themeStore.contentPrimaryColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(themeStore.surfaceColor.opacity(0.65))
            .clipShape(Capsule())
    }

    private func triggerSummaryRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(themeStore.font(for: .bodySmall))
                .foregroundStyle(themeStore.contentSecondaryColor)
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(themeStore.contentPrimaryColor)
                .textSelection(.enabled)
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
    @State private var filter: DiagnosticsFilter = .all

    private var filteredEntries: [CloudKitDiagnosticsEntry] {
        Array(diagnostics.entries(matching: filter).reversed())
    }

    private var filteredReport: String {
        diagnostics.diagnosticsReport(filter: filter)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if filter.showsTriggerSummary, diagnostics.triggerSummary.hasAnyValue {
                        triggerSummarySection(diagnostics.triggerSummary)
                    }

                    filterMenu

                    ForEach(filteredEntries) { entry in
                        diagnosticsEntryCard(entry)
                    }

                    if filteredEntries.isEmpty {
                        Text(filter.emptyStateMessage)
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
            .navigationTitle("Diagnostics")
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
                        UIPasteboard.general.string = filteredReport
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
            CloudKitDiagnosticsActivityView(activityItems: [filteredReport])
        }
    }

    private var filterMenu: some View {
        HStack {
            Menu {
                Picker("Filter", selection: $filter) {
                    ForEach(DiagnosticsFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            } label: {
                Label("Filter: \(filter.title)", systemImage: "line.3.horizontal.decrease.circle")
                    .font(themeStore.font(for: .buttonLabel))
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    private func diagnosticsEntryCard(_ entry: CloudKitDiagnosticsEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.kind == .error ? "Error" : "Event")
                    .font(themeStore.font(for: .bodyStrong))
                    .foregroundStyle(entry.kind == .error ? Color.red : themeStore.accentTabColor)

                Text(entry.source.displayName)
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(themeStore.surfaceColor.opacity(0.65))
                    .clipShape(Capsule())

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
        .background(themeStore.surfaceElevatedColor.opacity(0.9))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeStore.contentSecondaryColor.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func triggerSummarySection(_ summary: CloudKitTriggerSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trigger Summary")
                .font(themeStore.font(for: .bodyStrong))
                .foregroundStyle(themeStore.accentTabColor)

            triggerSummarySheetRow("Context", "\(summary.syncRole ?? "nil") / \(summary.syncScope ?? "nil")")
            triggerSummarySheetRow(
                "Subscriptions",
                "\(summary.subscriptionConfigurationStatus ?? "unknown") via \(summary.subscriptionRequestSource ?? "unknown")"
            )
            triggerSummarySheetRow("Plan", summary.subscriptionPlanDescription)
            triggerSummarySheetRow(
                "Push registration",
                "\(summary.pushRegistrationStatus ?? "unknown") @ \(summary.pushRegistrationTimestampISO8601 ?? "never")"
            )
            triggerSummarySheetRow(
                "Push counts",
                "received=\(summary.pushReceivedCount), remote=\(summary.remotePushCount), handler=\(summary.remoteHandlerInvocationCount)"
            )
            triggerSummarySheetRow(
                "Last triggers",
                "push=\(summary.lastPushReceivedTimestampISO8601 ?? "never"), remote=\(summary.lastRemotePushTimestampISO8601 ?? "never"), fallback=\(summary.lastOwnerFallbackTimestampISO8601 ?? "never")"
            )
            triggerSummarySheetRow(
                "Last sync",
                "\(summary.lastSchedulerReason ?? "unknown") / \(summary.lastFetchResult ?? "unknown")"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(themeStore.surfaceElevatedColor.opacity(0.9))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeStore.contentSecondaryColor.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func triggerSummarySheetRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(themeStore.font(for: .bodySmall))
                .foregroundStyle(themeStore.contentSecondaryColor)
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(themeStore.contentPrimaryColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CloudKitDiagnosticsActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
