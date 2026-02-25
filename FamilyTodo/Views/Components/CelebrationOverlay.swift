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

        // Raise emitters above tab bar chrome to avoid clipping.
        leftEmitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY - 90)
        rightEmitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY - 90)
    }

    func setAccentColor(_ color: UIColor) {
        accentColor = color
    }

    func fireBurst() {
        let palette: [UIColor] = [accentColor, .systemYellow, .systemPink, .white]

        burstTask?.cancel()

        leftEmitter.emitterCells = makeCells(colors: palette, isLeftCannon: true)
        rightEmitter.emitterCells = makeCells(colors: palette, isLeftCannon: false)

        leftEmitter.birthRate = 1
        rightEmitter.birthRate = 1

        // Explicitly restart the animation by resetting beginTime if the layer already exists
        let currentTime = CACurrentMediaTime()
        leftEmitter.beginTime = currentTime
        rightEmitter.beginTime = currentTime

        burstTask = _Concurrency.Task { @MainActor [weak self] in
            // Emit particles for exactly 50ms then shut off birth rate
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
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
        // Dual cannon burst from a shared center source:
        // left cannon shoots up-left, right cannon shoots up-right.
        let baseAngle = isLeftCannon ? (-3.0 * CGFloat.pi / 4.0) : (-CGFloat.pi / 4.0)

        return colors.flatMap { color in
            [
                makeCell(
                    image: Self.rectangleImage,
                    color: color,
                    baseAngle: baseAngle,
                    xAcceleration: isLeftCannon ? -50 : 50,
                    scale: 0.26
                ),
                makeCell(
                    image: Self.circleImage,
                    color: color,
                    baseAngle: baseAngle,
                    xAcceleration: isLeftCannon ? -50 : 50,
                    scale: 0.22
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

        cell.birthRate = 120
        cell.lifetime = 4.0
        cell.lifetimeRange = 0.9

        cell.velocity = 1000
        cell.velocityRange = 300
        cell.yAcceleration = 900
        cell.xAcceleration = xAcceleration

        cell.emissionLongitude = baseAngle
        cell.emissionRange = .pi / 6

        cell.spin = 2.0
        cell.spinRange = 4.0

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
