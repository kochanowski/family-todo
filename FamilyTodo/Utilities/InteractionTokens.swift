import Foundation
import SwiftUI

// MARK: - Animation Tokens

/// Centralized animation constants for consistent UX polish
enum WowAnimation {
    /// Standard duration for micro-interactions (200ms)
    static let duration: Double = 0.2

    /// Quick duration for immediate feedback (150ms)
    static let quick: Double = 0.15

    /// Standard easeOut animation
    static let easeOut = Animation.easeOut(duration: duration)

    /// Subtle spring animation for natural feel
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Quick spring for immediate feedback
    static let quickSpring = Animation.spring(response: 0.25, dampingFraction: 0.8)

    /// Staggered animation delay for list items
    static func staggerDelay(index: Int) -> Double {
        Double(index) * 0.05
    }

    static let remoteSyncHighlightDurationNanoseconds: UInt64 = 1_800_000_000
    static let remoteSyncStructureResetNanoseconds: UInt64 = 420_000_000
}

// MARK: - View Modifiers for Common Animations

struct RemoteSyncVisibleDelta: Equatable {
    let insertedIDs: Set<UUID>
    let updatedIDs: Set<UUID>
    let removedIDs: Set<UUID>

    var highlightedIDs: Set<UUID> {
        insertedIDs.union(updatedIDs)
    }
}

enum RemoteSyncVisibleDeltaResolver {
    static func resolve<Location: Equatable>(
        beforeLocations: [UUID: Location],
        afterLocations: [UUID: Location],
        changedIDs: Set<UUID>
    ) -> RemoteSyncVisibleDelta {
        let beforeIDs = Set(beforeLocations.keys)
        let afterIDs = Set(afterLocations.keys)
        let sharedIDs = beforeIDs.intersection(afterIDs)

        let movedIDs = Set(sharedIDs.filter { beforeLocations[$0] != afterLocations[$0] })
        let insertedIDs = afterIDs.subtracting(beforeIDs).union(movedIDs)
        let removedIDs = beforeIDs.subtracting(afterIDs).union(movedIDs)
        let updatedIDs = Set(sharedIDs.filter {
            beforeLocations[$0] == afterLocations[$0] && changedIDs.contains($0)
        })

        return RemoteSyncVisibleDelta(
            insertedIDs: insertedIDs,
            updatedIDs: updatedIDs,
            removedIDs: removedIDs
        )
    }
}

enum RemoteSyncNotificationPayloadKey {
    static let batchToken = "remoteSync.batchToken"
    static let shoppingChangedItemIDs = "remoteSync.shopping.changedItemIDs"
    static let workItemChangedIDs = "remoteSync.workItem.changedIDs"
    static let backlogChangedCategoryIDs = "remoteSync.backlog.changedCategoryIDs"
    static let direction = "remoteSync.direction"
    static let pushReceivedAt = "remoteSync.pushReceivedAt"
    static let cacheUpdatedAt = "remoteSync.cacheUpdatedAt"
}

struct RemoteSyncAnimationPayload: Equatable {
    let batchToken: UUID
    let shoppingChangedItemIDs: Set<UUID>
    let workItemChangedIDs: Set<UUID>
    let backlogChangedCategoryIDs: Set<UUID>
    let direction: String?
    let pushReceivedAt: Date?
    let cacheUpdatedAt: Date?
}

@MainActor
struct RemoteVisibleRefreshTask<Location: Equatable> {
    let changedIDs: Set<UUID>
    let captureVisibleLocations: () -> [UUID: Location]
    let rehydratePrimaryStore: () -> Void
    let refreshDependentStores: () async -> Void

    init(
        changedIDs: Set<UUID>,
        captureVisibleLocations: @escaping () -> [UUID: Location],
        rehydratePrimaryStore: @escaping () -> Void,
        refreshDependentStores: @escaping () async -> Void = {}
    ) {
        self.changedIDs = changedIDs
        self.captureVisibleLocations = captureVisibleLocations
        self.rehydratePrimaryStore = rehydratePrimaryStore
        self.refreshDependentStores = refreshDependentStores
    }

    func run() async -> RemoteSyncVisibleDelta {
        let beforeLocations = captureVisibleLocations()
        rehydratePrimaryStore()
        await refreshDependentStores()
        let afterLocations = captureVisibleLocations()

        return RemoteSyncVisibleDeltaResolver.resolve(
            beforeLocations: beforeLocations,
            afterLocations: afterLocations,
            changedIDs: changedIDs
        )
    }
}

extension Notification {
    var remoteSyncAnimationPayload: RemoteSyncAnimationPayload? {
        guard (object as? String) == "remotePush",
              let userInfo,
              let batchTokenString = userInfo[RemoteSyncNotificationPayloadKey.batchToken] as? String,
              let batchToken = UUID(uuidString: batchTokenString)
        else {
            return nil
        }

        return RemoteSyncAnimationPayload(
            batchToken: batchToken,
            shoppingChangedItemIDs: remoteSyncUUIDSet(for: RemoteSyncNotificationPayloadKey.shoppingChangedItemIDs),
            workItemChangedIDs: remoteSyncUUIDSet(for: RemoteSyncNotificationPayloadKey.workItemChangedIDs),
            backlogChangedCategoryIDs: remoteSyncUUIDSet(
                for: RemoteSyncNotificationPayloadKey.backlogChangedCategoryIDs
            ),
            direction: userInfo[RemoteSyncNotificationPayloadKey.direction] as? String,
            pushReceivedAt: remoteSyncDate(for: RemoteSyncNotificationPayloadKey.pushReceivedAt),
            cacheUpdatedAt: remoteSyncDate(for: RemoteSyncNotificationPayloadKey.cacheUpdatedAt)
        )
    }

    private func remoteSyncUUIDSet(for key: String) -> Set<UUID> {
        guard let rawValues = userInfo?[key] as? [String] else { return [] }
        return Set(rawValues.compactMap(UUID.init(uuidString:)))
    }

    private func remoteSyncDate(for key: String) -> Date? {
        guard let rawValue = userInfo?[key] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: rawValue)
    }
}

func logRemoteSyncVisibleRefreshLatency(
    screen: String,
    payload: RemoteSyncAnimationPayload?
) {
    guard let payload, let cacheUpdatedAt = payload.cacheUpdatedAt else { return }

    let now = Date()
    let cacheToVisibleMilliseconds = Int(now.timeIntervalSince(cacheUpdatedAt) * 1000)
    let totalMilliseconds = payload.pushReceivedAt.map {
        Int(now.timeIntervalSince($0) * 1000)
    }
    let totalLabel = totalMilliseconds.map(String.init) ?? "n/a"
    let direction = payload.direction ?? "unknown"

    print(
        "[RemoteSync] ViewApplied screen=\(screen) direction=\(direction) cacheToVisibleMs=\(cacheToVisibleMilliseconds) totalMs=\(totalLabel)"
    )
}

extension View {
    /// Apply standard row insertion animation
    func rowInsertAnimation() -> some View {
        transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)).animation(WowAnimation.spring),
            removal: .opacity.combined(with: .scale(scale: 0.98)).animation(WowAnimation.easeOut)
        ))
    }

    /// Apply move-to-restock animation (shrink + fade + slide)
    func restockRemovalAnimation() -> some View {
        transition(.asymmetric(
            insertion: .opacity,
            removal: .opacity
                .combined(with: .scale(scale: 0.98))
                .combined(with: .move(edge: .bottom))
                .animation(WowAnimation.easeOut)
        ))
    }

    /// Pulse animation for icons (scale 1.0 -> 1.08 -> 1.0) that retriggers on every token change.
    func pulseAnimation(trigger: Int) -> some View {
        modifier(PulseAnimationModifier(trigger: trigger))
    }

    /// Crossfade transition for appearance changes
    func crossfadeTransition() -> some View {
        transition(.opacity.animation(.easeInOut(duration: WowAnimation.duration)))
    }

    func remoteSyncStructuralTransition(enabled: Bool) -> some View {
        modifier(RemoteSyncStructuralTransitionModifier(enabled: enabled))
    }

    func remoteSyncHighlight(isActive: Bool, cornerRadius: CGFloat) -> some View {
        modifier(
            RemoteSyncHighlightModifier(
                isActive: isActive,
                cornerRadius: cornerRadius
            )
        )
    }
}

// MARK: - Reusable Animation States

/// Observable state for restock icon pulse
@MainActor
final class RestockPulseState: ObservableObject {
    @Published private(set) var pulseToken = 0

    func pulse() {
        pulseToken += 1
    }
}

private struct PulseAnimationModifier: ViewModifier {
    let trigger: Int

    @State private var isPulsing = false
    @State private var pulseGeneration = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.08 : 1.0)
            .onChange(of: trigger) { _, _ in
                pulseGeneration += 1
                let currentGeneration = pulseGeneration
                isPulsing = true

                DispatchQueue.main.asyncAfter(deadline: .now() + WowAnimation.quick) {
                    guard pulseGeneration == currentGeneration else { return }
                    isPulsing = false
                }
            }
            .animation(WowAnimation.quickSpring, value: isPulsing)
    }
}

private struct RemoteSyncStructuralTransitionModifier: ViewModifier {
    let enabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(enabled ? activeTransition : .identity)
    }

    private var activeTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.985))
                .combined(with: .offset(y: 6)),
            removal: .opacity
                .combined(with: .scale(scale: 0.985))
                .combined(with: .offset(y: -6))
        )
    }
}

private struct RemoteSyncHighlightModifier: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
    }
}
