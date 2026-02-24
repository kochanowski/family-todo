import QuartzCore
import SwiftUI
import UIKit

/// Overlay view that shows celebration toasts and high-performance confetti.
struct CelebrationOverlay: View {
    @ObservedObject var manager: CelebrationManager
    let messageFont: Font
    let accentPalette: [Color]?

    @State private var showConfetti = false

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
        .celebrate(trigger: $showConfetti, accentColor: resolvedAccentColor)
        .allowsHitTesting(false)
        .animation(ToastView.AnimationTokens.curve, value: manager.activeCelebration?.id)
        .onChange(of: manager.activeCelebration) { _, newValue in
            guard let newValue, newValue.style == .milestone else { return }
            showConfetti = true
        }
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
    @Binding var isActive: Bool
    let accentColor: UIColor

    final class Coordinator {
        var isRunning = false
        var stopWorkItem: DispatchWorkItem?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ConfettiEmitterView {
        ConfettiEmitterView()
    }

    func updateUIView(_ uiView: ConfettiEmitterView, context: Context) {
        uiView.setAccentColor(accentColor)

        if isActive, !context.coordinator.isRunning {
            context.coordinator.stopWorkItem?.cancel()
            context.coordinator.isRunning = true
            uiView.fireBurst()

            let binding = $isActive
            let workItem = DispatchWorkItem {
                context.coordinator.isRunning = false
                if binding.wrappedValue {
                    binding.wrappedValue = false
                }
            }

            context.coordinator.stopWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
        }

        if !isActive, !context.coordinator.isRunning {
            uiView.stopBurst()
        }
    }

    static func dismantleUIView(_ uiView: ConfettiEmitterView, coordinator: Coordinator) {
        coordinator.stopWorkItem?.cancel()
        uiView.stopBurst()
    }
}

final class ConfettiEmitterView: UIView {
    private let leftEmitter = CAEmitterLayer()
    private let rightEmitter = CAEmitterLayer()

    private var accentColor = UIColor.systemGreen
    private var burstStopWorkItem: DispatchWorkItem?

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

        leftEmitter.emitterPosition = CGPoint(x: 18, y: bounds.maxY - 8)
        rightEmitter.emitterPosition = CGPoint(x: bounds.maxX - 18, y: bounds.maxY - 8)
    }

    func setAccentColor(_ color: UIColor) {
        accentColor = color
    }

    func fireBurst() {
        let palette: [UIColor] = [accentColor, .systemYellow, .systemPink, .white]
        burstStopWorkItem?.cancel()

        leftEmitter.emitterCells = makeCells(colors: palette, isLeftCannon: true)
        rightEmitter.emitterCells = makeCells(colors: palette, isLeftCannon: false)

        leftEmitter.birthRate = 1
        rightEmitter.birthRate = 1

        let stopWorkItem = DispatchWorkItem { [weak self] in
            self?.stopBurst()
        }
        burstStopWorkItem = stopWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: stopWorkItem)
    }

    func stopBurst() {
        burstStopWorkItem?.cancel()
        burstStopWorkItem = nil
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
        let baseAngle = isLeftCannon ? (-CGFloat.pi / 3.0) : (-2.0 * CGFloat.pi / 3.0)

        return colors.flatMap { color in
            [
                makeCell(
                    image: Self.rectangleImage,
                    color: color,
                    baseAngle: baseAngle,
                    xAcceleration: isLeftCannon ? 32 : -32,
                    scale: 0.3
                ),
                makeCell(
                    image: Self.circleImage,
                    color: color,
                    baseAngle: baseAngle,
                    xAcceleration: isLeftCannon ? 32 : -32,
                    scale: 0.34
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
        cell.lifetime = 3.0
        cell.lifetimeRange = 0.9

        cell.velocity = 720
        cell.velocityRange = 170
        cell.yAcceleration = 900
        cell.xAcceleration = xAcceleration

        cell.emissionLongitude = baseAngle
        cell.emissionRange = .pi / 8

        cell.spin = 7.0
        cell.spinRange = 8.0

        cell.scale = scale
        cell.scaleRange = 0.2
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
    @Binding var trigger: Bool
    let accentColor: Color

    func body(content: Content) -> some View {
        content.overlay {
            ConfettiCannon(
                isActive: $trigger,
                accentColor: UIColor(accentColor)
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func celebrate(trigger: Binding<Bool>, accentColor: Color) -> some View {
        modifier(CelebrationModifier(trigger: trigger, accentColor: accentColor))
    }
}
