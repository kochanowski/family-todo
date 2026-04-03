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

    private var triggerSummary: CloudKitTriggerSummary {
        diagnostics.triggerSummary
    }

    var body: some View {
        if diagnostics.hasVisibleDiagnostics {
            VStack(alignment: .leading, spacing: 10) {
                Label("CloudKit Diagnostics (Debug)", systemImage: "ladybug.fill")
                    .font(themeStore.font(for: .bodyStrong))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                if triggerSummary.hasAnyValue {
                    triggerSummaryCard(triggerSummary)
                }

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

                    Button("Copy all") {
                        UIPasteboard.general.string = diagnostics.diagnosticsReport
                    }
                    .buttonStyle(.bordered)

                    if diagnostics.hasNotificationDiagnostics {
                        Button("Copy notifications") {
                            UIPasteboard.general.string = diagnostics.notificationDiagnosticsReport
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Clear") {
                        diagnostics.clear()
                    }
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
    @State private var selectedFilter: CloudKitDiagnosticsFilter = .all

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if diagnostics.hasNotificationDiagnostics {
                        Picker("Log filter", selection: $selectedFilter) {
                            ForEach(CloudKitDiagnosticsFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if diagnostics.triggerSummary.hasAnyValue {
                        triggerSummarySection(diagnostics.triggerSummary)
                    }

                    ForEach(Array(displayedEntries.reversed())) { entry in
                        diagnosticsEntryCard(entry)
                    }

                    if displayedEntries.isEmpty {
                        Text(selectedFilter.emptyMessage)
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
                    Button(copyButtonTitle) {
                        UIPasteboard.general.string = diagnostics.diagnosticsReport(for: selectedFilter)
                        copied = true
                    }
                    .font(themeStore.font(for: .buttonLabel))
                    .buttonStyle(.bordered)

                    Button(shareButtonTitle) {
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
        .onAppear {
            if diagnostics.hasNotificationDiagnostics {
                selectedFilter = .notifications
            }
        }
        .sheet(isPresented: $showShareSheet) {
            CloudKitDiagnosticsActivityView(
                activityItems: [diagnostics.diagnosticsReport(for: selectedFilter)]
            )
        }
    }

    private var displayedEntries: [CloudKitDiagnosticsEntry] {
        switch selectedFilter {
        case .all:
            diagnostics.entries
        case .notifications:
            diagnostics.notificationEntries
        }
    }

    private var copyButtonTitle: String {
        switch selectedFilter {
        case .all:
            "Copy diagnostics"
        case .notifications:
            "Copy notifications"
        }
    }

    private var shareButtonTitle: String {
        switch selectedFilter {
        case .all:
            "Share diagnostics"
        case .notifications:
            "Share notifications"
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
