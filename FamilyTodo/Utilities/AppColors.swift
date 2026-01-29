import SwiftUI

enum AppColors {
    // Warm, paper-like background used across the app to match the reference UI.
    static let canvas = Color(hex: "F6F1EC")
    static let surface = Color(hex: "FFFFFF")
    static let surfaceElevated = Color(hex: "FFF7EE")

    static let ink = Color(hex: "1F1B17")
    static let inkMuted = Color(hex: "8C8378")
    static let borderLight = Color(hex: "E8DFD6")

    static let accent = Color(hex: "F7B21A")
    static let accentSoft = Color(hex: "FDE5A6")

    static let tabBarBackground = Color(hex: "F3EDE6")
    static let tabBarActivePill = Color(hex: "E9E1D8")
    static let tabBarShadow = Color.black.opacity(0.1)
    static let cardShadow = Color.black.opacity(0.06)
}
