import SwiftUI

/// The vertical tab that hangs off the menu bar.
///
/// Exactly one fillet is **concave**: the top one on the inner side, where the
/// shape widens towards the menu bar instead of rounding inwards. That is what
/// makes the tab look poured out of the screen edge, the way the notch corners
/// do. The outer side sits flush against the edge, so its top corner is left
/// square — it merges into the menu bar. At the bottom, where the shape ends
/// free over the wallpaper, the corners are rounded normally.
struct NotchRailShape: Shape {

    var concave: CGFloat = Theme.concaveRadius
    var convex: CGFloat = Theme.convexRadius
    /// With `false` the shape is mirrored: the tab hangs off the left edge.
    var flaresLeft: Bool = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = min(concave, rect.width / 3)
        let v = min(convex, rect.width / 2, rect.height / 3)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // The concave fillet: the shape widens towards the menu bar.
        path.addQuadCurve(to: CGPoint(x: rect.minX + c, y: rect.minY + c),
                          control: CGPoint(x: rect.minX + c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY - v))
        path.addQuadCurve(to: CGPoint(x: rect.minX + c + v, y: rect.maxY),
                          control: CGPoint(x: rect.minX + c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - v, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - v),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        // The outer side runs straight up to the top, where it meets the menu bar.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()

        guard !flaresLeft else { return path }
        return path.applying(
            CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width, y: 0)
        )
    }
}

/// A bubble whose tail lines up with the ring under the cursor.
struct BubbleShape: Shape {

    /// Vertical position of the tip, in the bubble's own coordinates.
    var tailCenterY: CGFloat
    var tailOnRight: Bool = true
    var radius: CGFloat = Theme.bubbleRadius
    var tailWidth: CGFloat = Theme.bubbleTailWidth
    var tailHeight: CGFloat = Theme.bubbleTailHeight

    var animatableData: CGFloat {
        get { tailCenterY }
        set { tailCenterY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let body = tailOnRight
            ? CGRect(x: rect.minX, y: rect.minY, width: rect.width - tailWidth, height: rect.height)
            : CGRect(x: rect.minX + tailWidth, y: rect.minY, width: rect.width - tailWidth, height: rect.height)

        path.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius),
                            style: .continuous)

        // The tail stays within the body's straight run, so it never detaches
        // when the active ring is the first or the last of the column.
        let half = tailHeight / 2
        let y = min(max(tailCenterY, body.minY + radius + half), body.maxY - radius - half)
        let baseX = tailOnRight ? body.maxX : body.minX
        let tipX = tailOnRight ? rect.maxX : rect.minX

        var tail = Path()
        tail.move(to: CGPoint(x: baseX, y: y - half))
        // The two quads give the tip the same soft radius as the body, instead
        // of a sharp triangle.
        tail.addQuadCurve(to: CGPoint(x: tipX, y: y),
                          control: CGPoint(x: baseX + (tipX - baseX) * 0.72, y: y - half * 0.42))
        tail.addQuadCurve(to: CGPoint(x: baseX, y: y + half),
                          control: CGPoint(x: baseX + (tipX - baseX) * 0.72, y: y + half * 0.42))
        tail.closeSubpath()

        path.addPath(tail)
        return path
    }
}
