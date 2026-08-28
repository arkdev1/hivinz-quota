import AppKit

/// The notch is measured, not guessed: `auxiliaryTopLeftArea` and
/// `auxiliaryTopRightArea` are the two slices of menu bar either side of the
/// cutout, so whatever is left over across the screen width is the notch.
struct NotchGeometry {

    let screen: NSScreen
    /// `nil` on displays without a notch (external monitors).
    let notchRect: CGRect?

    init(screen: NSScreen) {
        self.screen = screen
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            let width = screen.frame.width - left.width - right.width
            if width > 40 {
                self.notchRect = CGRect(x: screen.frame.minX + left.width,
                                        y: screen.frame.maxY - screen.safeAreaInsets.top,
                                        width: width,
                                        height: screen.safeAreaInsets.top)
                return
            }
        }
        self.notchRect = nil
    }

    var hasNotch: Bool { notchRect != nil }

    /// The edge the rail hangs from: the bottom of the notch, or — without one —
    /// the bottom of the menu bar.
    var topEdge: CGFloat {
        notchRect?.minY ?? (screen.frame.maxY - max(screen.safeAreaInsets.top, 24))
    }

    /// How far down the rail may be dragged before it would fall off screen.
    func maxVerticalOffset(railHeight: CGFloat) -> CGFloat {
        max(topEdge - screen.visibleFrame.minY - railHeight, 0)
    }

    /// Panel origin in screen coordinates (y pointing up).
    ///
    /// Anchored flush to the screen edge: the concave fillet at the top then
    /// reads as the rail flowing out of the menu bar, the way the notch corners
    /// do. Insetting it by a few points would make it look like an ordinary
    /// window parked near the corner instead.
    func panelOrigin(panelSize: CGSize, railTotalWidth: CGFloat,
                     anchorOnRight: Bool, useNotchAnchor: Bool,
                     verticalOffset: CGFloat) -> CGPoint {
        let y = topEdge - verticalOffset - panelSize.height

        if useNotchAnchor, let notch = notchRect {
            let x = anchorOnRight
                ? notch.maxX - panelSize.width
                : notch.minX
            return CGPoint(x: x, y: y)
        }

        let x = anchorOnRight
            ? screen.frame.maxX - panelSize.width
            : screen.frame.minX
        return CGPoint(x: x, y: y)
    }
}
