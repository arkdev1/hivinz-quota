import SwiftUI

enum Theme {

    // MARK: - Rail geometry

    static let railWidth: CGFloat = 54
    /// Reach of the concave fillets that melt the rail into the screen edge.
    /// Generous on purpose: in the reference design the flares are wide, slow
    /// curves — small radii read as a chip in the corner rather than a melt.
    static let concaveRadius: CGFloat = 20
    static let convexRadius: CGFloat = 26
    static let ringSize: CGFloat = 34
    static let ringLineWidth: CGFloat = 3.5
    static let ringToLabel: CGFloat = 5
    static let itemSpacing: CGFloat = 16
    static let railTopInset: CGFloat = 10
    static let railBottomInset: CGFloat = 22

    // MARK: - Bubble

    static let bubbleWidth: CGFloat = 268
    static let bubbleRadius: CGFloat = 16
    static let bubbleTailWidth: CGFloat = 11
    static let bubbleTailHeight: CGFloat = 20
    /// Gap between the tip of the tail and the edge of the rail.
    static let bubbleGap: CGFloat = 2
    /// Slack the bubble panel keeps around its shape. A window clips whatever it
    /// draws, so without this margin the drop shadow gets sliced off square at
    /// the panel edge instead of fading out.
    static let bubbleShadowPad: CGFloat = 24
    static let shadowRadius: CGFloat = 14

    // MARK: - Colours

    static let surface = Color.black
    static let track = Color.white.opacity(0.16)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)

    /// In the reference design 21% is green, 52% yellow, 73% red: the colour
    /// reports the state, not the provider's brand.
    static func severity(_ fraction: Double,
                         warning: Double = Preferences.shared.warningThreshold,
                         critical: Double = Preferences.shared.criticalThreshold) -> Color {
        if fraction >= critical { return Color(nsColor: .systemRed) }
        if fraction >= warning { return Color(nsColor: .systemYellow) }
        return Color(nsColor: .systemGreen)
    }

    // MARK: - Typography

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
