import QuartzCore
import SwiftUI
import UIKit

/// Overlay view that shows celebration toasts and high-performance confetti.
struct CelebrationOverlay: View {
    @ObservedObject var manager: CelebrationManager
    let messageFont: Font
    let accentPalette: [Color]?

    init(
        manager: CelebrationManager,
        messageFont: Font = .system(size: 15, weight: .semibold),
        accentPalette: [Color]? = nil
    ) {
        self.manager = manager
        self.messageFont = messageFont
        self.accentPalette = accentPalette
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let celebration = manager.activeCelebration {
                    VStack {
                        Spacer()

                        ToastView(
                            message: celebration.message,
                            messageFont: messageFont,
                            leadingText: celebration.emoji
                        )
                        .padding(.horizontal, ToastView.Metrics.horizontalInset)
                        .padding(.bottom, toastBottomInset(for: proxy))
                        .transition(ToastView.AnimationTokens.transition)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .celebrate(trigger: manager.confettiTrigger, accentColor: resolvedAccentColor)
        .allowsHitTesting(false)
        .animation(ToastView.AnimationTokens.curve, value: manager.activeCelebration?.id)
    }

    private var resolvedAccentColor: Color {
        if let accentPalette, let first = accentPalette.first {
            return first
        }
        return .yellow
    }

    private func toastBottomInset(for proxy: GeometryProxy) -> CGFloat {
        let safeAreaBottom = proxy.safeAreaInsets.bottom
        let minimumFloatingClearance: CGFloat = 90
        let chromeAwareInset = AppChromeMetrics.compactCTAHeight + safeAreaBottom + 46
        return max(minimumFloatingClearance, chromeAwareInset)
    }
}

struct ConfettiCannon: UIViewRepresentable {
    let trigger: Int
    let accentColor: UIColor

    final class Coordinator {
        var lastTrigger = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ConfettiEmitterView {
        ConfettiEmitterView()
    }

    func updateUIView(_ uiView: ConfettiEmitterView, context: Context) {
        uiView.setAccentColor(accentColor)

        if trigger > context.coordinator.lastTrigger {
            context.coordinator.lastTrigger = trigger
            uiView.fireBurst()
        }
    }

    static func dismantleUIView(_ uiView: ConfettiEmitterView, coordinator: Coordinator) {
        uiView.stopBurst()
    }
}

final class ConfettiEmitterView: UIView {
    private let leftEmitter = CAEmitterLayer()
    private let rightEmitter = CAEmitterLayer()

    private var accentColor = UIColor.systemGreen
    private var burstTask: _Concurrency.Task<Void, Never>?

    private static let rectangleImage = ConfettiShapeRenderer.rectangleImage()
    private static let circleImage = ConfettiShapeRenderer.circleImage()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        configureEmitter(leftEmitter)
        configureEmitter(rightEmitter)

        layer.addSublayer(leftEmitter)
        layer.addSublayer(rightEmitter)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Position emitters at the bottom-center of the view
        leftEmitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY)
        rightEmitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY)
    }

    func setAccentColor(_ color: UIColor) {
        accentColor = color
    }

    func fireBurst() {
        let palette: [UIColor] = [
            accentColor,
            UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1.0),  // Gold
            UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0),  // Silver/White
            accentColor.withAlphaComponent(0.8),
        ]

        burstTask?.cancel()

        leftEmitter.emitterCells = makeCells(colors: palette, isLeftCannon: true)
        rightEmitter.emitterCells = makeCells(colors: palette, isLeftCannon: false)

        leftEmitter.birthRate = 200
        rightEmitter.birthRate = 200

        // Explicitly restart the animation by resetting beginTime if the layer already exists
        let currentTime = CACurrentMediaTime()
        leftEmitter.beginTime = currentTime
        rightEmitter.beginTime = currentTime

        burstTask = _Concurrency.Task { @MainActor [weak self] in
            // Emit particles for exactly 300ms then shut off birth rate
            try? await _Concurrency.Task.sleep(for: .milliseconds(300))
            guard !_Concurrency.Task.isCancelled else { return }
            self?.stopBurst()
        }
    }

    func stopBurst() {
        burstTask?.cancel()
        burstTask = nil
        leftEmitter.birthRate = 0
        rightEmitter.birthRate = 0
    }

    private func configureEmitter(_ emitter: CAEmitterLayer) {
        emitter.emitterShape = .point
        emitter.emitterMode = .points
        emitter.renderMode = .unordered
        emitter.birthRate = 0
        emitter.emitterSize = .zero
    }

    private func makeCells(colors: [UIColor], isLeftCannon: Bool) -> [CAEmitterCell] {
        // Left Cannon shoots up and left (-135 degrees)
        // Right Cannon shoots up and right (-45 degrees)
        let baseAngle = isLeftCannon ? (-3.0 * CGFloat.pi / 4.0) : (-CGFloat.pi / 4.0)

        return colors.flatMap { color in
            [
                makeCell(
                    image: Self.rectangleImage,
                    color: color,
                    baseAngle: baseAngle,
                    xAcceleration: isLeftCannon ? -50 : 50,
                    scale: 0.15
                ),
                makeCell(
                    image: Self.circleImage,
                    color: color,
                    baseAngle: baseAngle,
                    xAcceleration: isLeftCannon ? -50 : 50,
                    scale: 0.15
                ),
            ]
        }
    }

    private func makeCell(
        image: CGImage?,
        color: UIColor,
        baseAngle: CGFloat,
        xAcceleration: CGFloat,
        scale: CGFloat
    ) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = image
        cell.color = color.cgColor

        cell.birthRate = 85
        cell.lifetime = 4.0
        cell.lifetimeRange = 0.9

        cell.velocity = 600
        cell.velocityRange = 200
        cell.yAcceleration = 800
        cell.xAcceleration = xAcceleration

        cell.emissionLongitude = baseAngle
        cell.emissionRange = .pi / 8

        cell.spin = 7.0
        cell.spinRange = 8.0

        cell.scale = scale
        cell.scaleRange = 0.05
        cell.scaleSpeed = -0.08

        cell.alphaRange = 0.3
        cell.alphaSpeed = -0.28
        return cell
    }
}

private enum ConfettiShapeRenderer {
    static func rectangleImage() -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 7))
        return renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 12, height: 7))
        }.cgImage
    }

    static func circleImage() -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 10, height: 10))
        }.cgImage
    }
}

private struct CelebrationModifier: ViewModifier {
    let trigger: Int
    let accentColor: Color

    func body(content: Content) -> some View {
        content.overlay {
            ConfettiCannon(
                trigger: trigger,
                accentColor: UIColor(accentColor)
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func celebrate(trigger: Int, accentColor: Color) -> some View {
        modifier(CelebrationModifier(trigger: trigger, accentColor: accentColor))
    }
}
