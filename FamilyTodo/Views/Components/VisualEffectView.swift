import SwiftUI
import UIKit

/// UIKit `UIVisualEffectView` bridge for reliable frosted-glass blur in SwiftUI.
///
/// SwiftUI `.material` modifiers can appear flat when the layer beneath them is
/// solid or when compositing order prevents the blur from sampling real content.
/// Wrapping UIKit's blur directly avoids those issues.
struct VisualEffectView: UIViewRepresentable {
    let effect: UIVisualEffect

    func makeUIView(context _: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: effect)
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context _: Context) {
        uiView.effect = effect
    }
}
