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
        ZStack {
            if let celebration = manager.activeCelebration {
                VStack {
                    Spacer()

                    HStack(spacing: 10) {
                        Text(celebration.emoji)
                            .font(.system(size: 24))

                        Text(celebration.message)
                            .font(messageFont)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))

                    Spacer().frame(height: 100) // Keep above tab bar area
                }
                .animation(WowAnimation.spring, value: manager.activeCelebration)
            }
        }
        .celebrate(trigger: $showConfetti, accentColor: resolvedAccentColor)
        .allowsHitTesting(false)
        .onChange(of: manager.activeCelebration) { _, newValue in
            guard newValue != nil else { return }
            showConfetti = true
        }
    }

    private var resolvedAccentColor: Color {
        if let accentPalette, let first = accentPalette.first {
            return first
        }
        return .yellow
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
                uiView.stopBurst()
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
        let palette: [UIColor] = [accentColor, .systemYellow, .white]

        leftEmitter.emitterCells = makeCells(colors: palette, isLeftCannon: true)
        rightEmitter.emitterCells = makeCells(colors: palette, isLeftCannon: false)

        leftEmitter.birthRate = 1
        rightEmitter.birthRate = 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.leftEmitter.birthRate = 0
            self?.rightEmitter.birthRate = 0
        }
    }

    func stopBurst() {
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
                    xAcceleration: isLeftCannon ? 18 : -18,
                    scale: 0.76
                ),
                makeCell(
                    image: Self.circleImage,
                    color: color,
                    baseAngle: baseAngle,
                    xAcceleration: isLeftCannon ? 18 : -18,
                    scale: 0.62
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

        cell.birthRate = 34
        cell.lifetime = 3.2
        cell.lifetimeRange = 0.9

        cell.velocity = 420
        cell.velocityRange = 130
        cell.yAcceleration = 330
        cell.xAcceleration = xAcceleration

        cell.emissionLongitude = baseAngle
        cell.emissionRange = .pi / 8

        cell.spin = 3.2
        cell.spinRange = 4.8

        cell.scale = scale
        cell.scaleRange = 0.35
        cell.scaleSpeed = -0.08

        cell.alphaRange = 0.18
        cell.alphaSpeed = -0.24
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
