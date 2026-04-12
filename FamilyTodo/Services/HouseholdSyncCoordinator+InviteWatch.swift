import Foundation

struct InviteAcceptanceWatchConfiguration: Equatable {
    let isEnabled: Bool
    let burstIntervalNanoseconds: UInt64
    let burstMaxPassCount: Int
    let steadyIntervalNanoseconds: UInt64
    let steadyMaxPassCount: Int

    static let `default` = InviteAcceptanceWatchConfiguration(
        isEnabled: true,
        burstIntervalNanoseconds: 15_000_000_000,
        burstMaxPassCount: 10,
        steadyIntervalNanoseconds: 30_000_000_000,
        steadyMaxPassCount: 4
    )
}

@MainActor
extension HouseholdSyncCoordinator {
    func startInviteAcceptanceWatch(for householdId: UUID) {
        guard inviteAcceptanceWatchConfiguration.isEnabled else { return }
        guard applicationStateProvider() == .active else {
            recordSchedulerProgress(
                "sync.scheduler.inviteWatch.skipped householdId=\(householdId.uuidString) reason=appNotActive"
            )
            return
        }
        if let currentHouseholdID = currentHouseholdIDProvider(),
           currentHouseholdID != householdId
        {
            recordSchedulerProgress(
                "sync.scheduler.inviteWatch.skipped householdId=\(householdId.uuidString) reason=householdMismatch currentHouseholdId=\(currentHouseholdID.uuidString)"
            )
            return
        }

        cancelInviteAcceptanceWatch(reason: "restart")
        inviteAcceptanceWatchedHouseholdID = householdId
        let configuration = inviteAcceptanceWatchConfiguration
        recordSchedulerProgress(
            "sync.scheduler.inviteWatch.started householdId=\(householdId.uuidString) burstIntervalNs=\(configuration.burstIntervalNanoseconds) burstPasses=\(configuration.burstMaxPassCount) steadyIntervalNs=\(configuration.steadyIntervalNanoseconds) steadyPasses=\(configuration.steadyMaxPassCount)"
        )

        inviteAcceptanceWatchTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                clearInviteAcceptanceWatchState(for: householdId)
            }

            await runInviteAcceptanceWatch(
                for: householdId,
                configuration: configuration
            )
        }
    }

    func stopInviteAcceptanceWatch(reason: String = "stopped") {
        cancelInviteAcceptanceWatch(reason: reason)
    }

    func stopInviteAcceptanceWatchIfSatisfied(after batch: HouseholdSyncBatch) {
        guard inviteAcceptanceWatchedHouseholdID != nil else { return }
        guard batch.diagnostics.syncRole == .owner,
              (batch.diagnostics.activeMemberCount ?? 0) > 1
        else {
            return
        }

        cancelInviteAcceptanceWatch(reason: "memberCountSatisfied")
    }

    private func runInviteAcceptanceWatch(
        for householdId: UUID,
        configuration: InviteAcceptanceWatchConfiguration
    ) async {
        guard shouldContinueInviteAcceptanceWatch(for: householdId) else { return }

        recordSchedulerProgress(
            "sync.scheduler.inviteWatch.fired householdId=\(householdId.uuidString) phase=initial"
        )
        _ = await performSync(reason: .localMutationFollowUp)

        guard shouldContinueInviteAcceptanceWatch(for: householdId) else { return }

        for passIndex in 1 ... configuration.burstMaxPassCount {
            let shouldContinue = await performInviteAcceptanceWatchPass(
                for: householdId,
                phase: "burst",
                passIndex: passIndex,
                intervalNanoseconds: configuration.burstIntervalNanoseconds
            )
            guard shouldContinue else { return }
        }

        for passIndex in 1 ... configuration.steadyMaxPassCount {
            let shouldContinue = await performInviteAcceptanceWatchPass(
                for: householdId,
                phase: "steady",
                passIndex: passIndex,
                intervalNanoseconds: configuration.steadyIntervalNanoseconds
            )
            guard shouldContinue else { return }
        }

        recordSchedulerProgress(
            "sync.scheduler.inviteWatch.completed householdId=\(householdId.uuidString)"
        )
    }

    private func performInviteAcceptanceWatchPass(
        for householdId: UUID,
        phase: String,
        passIndex: Int,
        intervalNanoseconds: UInt64
    ) async -> Bool {
        guard shouldContinueInviteAcceptanceWatch(for: householdId) else { return false }

        recordSchedulerProgress(
            "sync.scheduler.inviteWatch.scheduled householdId=\(householdId.uuidString) phase=\(phase) passIndex=\(passIndex) intervalNs=\(intervalNanoseconds)"
        )

        if intervalNanoseconds > 0 {
            try? await _Concurrency.Task.sleep(nanoseconds: intervalNanoseconds)
        }

        guard !_Concurrency.Task.isCancelled else { return false }
        guard shouldContinueInviteAcceptanceWatch(for: householdId) else { return false }

        recordSchedulerProgress(
            "sync.scheduler.inviteWatch.fired householdId=\(householdId.uuidString) phase=\(phase) passIndex=\(passIndex)"
        )
        _ = await performSync(reason: .localMutationFollowUp)
        return shouldContinueInviteAcceptanceWatch(for: householdId)
    }

    private func shouldContinueInviteAcceptanceWatch(for householdId: UUID) -> Bool {
        guard inviteAcceptanceWatchConfiguration.isEnabled else { return false }
        guard inviteAcceptanceWatchedHouseholdID == householdId else { return false }
        guard !_Concurrency.Task.isCancelled else { return false }

        guard applicationStateProvider() == .active else {
            cancelInviteAcceptanceWatch(reason: "appNotActive")
            return false
        }

        if let currentHouseholdID = currentHouseholdIDProvider(),
           currentHouseholdID != householdId
        {
            cancelInviteAcceptanceWatch(reason: "householdChanged")
            return false
        }

        if let lastDiagnostics,
           lastDiagnostics.syncRole == .owner,
           (lastDiagnostics.activeMemberCount ?? 0) > 1
        {
            cancelInviteAcceptanceWatch(reason: "memberCountSatisfied")
            return false
        }

        return true
    }

    private func cancelInviteAcceptanceWatch(reason: String) {
        let hadActiveWatch =
            inviteAcceptanceWatchTask != nil ||
            inviteAcceptanceWatchedHouseholdID != nil
        inviteAcceptanceWatchTask?.cancel()
        inviteAcceptanceWatchTask = nil
        inviteAcceptanceWatchedHouseholdID = nil

        guard hadActiveWatch else { return }
        recordSchedulerProgress(
            "sync.scheduler.inviteWatch.cancelled reason=\(reason)"
        )
    }

    private func clearInviteAcceptanceWatchState(for householdId: UUID) {
        guard inviteAcceptanceWatchedHouseholdID == householdId else { return }
        inviteAcceptanceWatchTask = nil
        inviteAcceptanceWatchedHouseholdID = nil
    }
}
