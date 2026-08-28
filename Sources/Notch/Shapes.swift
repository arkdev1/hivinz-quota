import SwiftUI

/// The vertical tab that leans against a screen edge.
///
/// The attachment is to the *side* edge, not to the menu bar: the menu bar is
/// light, so a black shape flaring into it reads as a hook into nothing. Against
/// the side edge the geometry works at any height — the two **concave** fillets
/// sit at the top and bottom of the outer side, melting the tab into the edge
/// the way the notch corners melt into the display, while the inner corners are
/// rounded normally. One shape, wherever the rail is dragged.
struct NotchRailShape: Shape {

    var concave: CGFloat = Theme.concaveRadius
    var convex: CGFloat = Theme.convexRadius
    /// `true` when the rail leans on the right edge; mirrored for the left.
    var attachedRight: Bool = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = min(concave, rect.height / 4)
        let v = min(convex, rect.width / 2, (rect.height - 2 * c) / 2)

        // Drawn right-attached: the outer side (maxX) is dead straight and flush
        // with the screen edge; each end melts into it through a concave fillet.
        //
        // The fillet's control points hug the *inner* corner — (maxX, minY+c) at
        // the top — which is what makes the black flare outward along the edge,
        // exactly like the underside of the notch. Put them on the outer corner
        // and the same curve turns convex: a rounded shoulder, the opposite look.
        // The inner corners are drawn as cubics with the ~0.45 handle spread of
        // a continuous rounded rect, so they read as one family of curves.
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX - c, y: rect.minY + c),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + c * 0.55),
                      control2: CGPoint(x: rect.maxX - c * 0.45, y: rect.minY + c))
        path.addLine(to: CGPoint(x: rect.minX + v, y: rect.minY + c))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + c + v),
                      control1: CGPoint(x: rect.minX + v * 0.45, y: rect.minY + c),
                      control2: CGPoint(x: rect.minX, y: rect.minY + c + v * 0.45))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c - v))
        path.addCurve(to: CGPoint(x: rect.minX + v, y: rect.maxY - c),
                      control1: CGPoint(x: rect.minX, y: rect.maxY - c - v * 0.45),
                      control2: CGPoint(x: rect.minX + v * 0.45, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY - c))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX - c * 0.45, y: rect.maxY - c),
                      control2: CGPoint(x: rect.maxX, y: rect.maxY - c * 0.55))
        path.closeSubpath() // straight run back up the screen edge

        guard attachedRight else {
            return path.applying(
                CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width, y: 0)
            )
        }
        return path
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
