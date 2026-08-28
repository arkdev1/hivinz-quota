import SwiftUI
import AppKit

enum Theme {

    // MARK: - Rail geometry

    static let railWidth: CGFloat = 54
    /// Reach of the concave fillets that melt the rail into the screen edge.
    /// Generous on purpose: in the reference design the flares are wide, slow
    /// curves — small radii read as a chip in the corner rather than a melt.
    static let concaveRadius: CGFloat = 20
    static let convexRadius: CGFloat = 26
    /// The notch-hanging flares are their own size: the edge fillets' 20pt on
    /// both sides of a 54pt body reads as a funnel, not a melt. Slightly taller
    /// than wide, like the notch's own corners.
    static let notchFlareWidth: CGFloat = 11
    static let notchFlareHeight: CGFloat = 16
    static let ringSize: CGFloat = 34
    static let ringLineWidth: CGFloat = 3.5
    static let ringToLabel: CGFloat = 5
    static let itemSpacing: CGFloat = 16
    static let railTopInset: CGFloat = 10
    static let railBottomInset: CGFloat = 22

    // MARK: - Bubble

    static let bubbleWidth: CGFloat = 268
    static let bubbleRadius: CGFloat = 16
    static let bubbleTailWidth: CGFloat = 12
    static let bubbleTailHeight: CGFloat = 18
    /// Gap between the tip of the tail and the edge of the rail. Enough air for
    /// the tail to read as pointing at the ring rather than touching it; the
    /// safe-triangle monitor keeps the crossing safe.
    static let bubbleGap: CGFloat = 8
    /// Slack the bubble panel keeps around its shape. A window clips whatever it
    /// draws, so without this margin the drop shadow gets sliced off square at
    /// the panel edge instead of fading out.
    static let bubbleShadowPad: CGFloat = 24
    static let shadowRadius: CGFloat = 14

    // MARK: - Colours
    //
    // Computed, not stored: they follow the theme preference, and — on the
    // "system" setting — the system appearance. Reading them inside a SwiftUI
    // body registers the observation, so views repaint when either changes.

    /// Whether the widget currently renders dark.
    static var isDark: Bool {
        switch Preferences.shared.theme {
        case "light": return false
        case "dark": return true
        default:
            _ = Preferences.shared.appearanceTick // subscribe to system flips
            return NSApp.effectiveAppearance
                .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    static var surface: Color {
        isDark ? .black : .white
    }
    static var track: Color {
        isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.13)
    }
    static var primaryText: Color {
        isDark ? .white : Color.black.opacity(0.88)
    }
    static var secondaryText: Color {
        isDark ? Color.white.opacity(0.62) : Color.black.opacity(0.5)
    }
    static var shadowColor: Color {
        Color.black.opacity(isDark ? 0.5 : 0.28)
    }

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
