import SwiftUI

/// The vertical tab that leans against a screen edge.
///
/// The attachment is to the *side* edge, not to the menu bar: the menu bar is
/// light, so a black shape flaring into it reads as a hook into nothing. Against
/// the side edge the geometry works at any height — the two **concave** fillets
/// sit at the top and bottom of the outer side, melting the tab into the edge
/// the way the notch corners melt into the display, while the inner corners are
/// rounded normally. One shape, wherever the rail is dragged.
enum RailAttachment {
    case rightEdge
    case leftEdge
    /// Hanging from the bottom of the notch, as in the reference design.
    case notch
}

struct NotchRailShape: Shape {

    var concave: CGFloat = Theme.concaveRadius
    var convex: CGFloat = Theme.convexRadius
    var attachment: RailAttachment = .rightEdge

    func path(in rect: CGRect) -> Path {
        if attachment == .notch { return notchPath(in: rect) }
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

        guard attachment == .rightEdge else {
            return path.applying(
                CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width, y: 0)
            )
        }
        return path
    }

    /// Hanging from the notch: the whole top edge merges into the notch bottom,
    /// with a concave flare climbing into it on *both* sides, and the free end
    /// rounded. The flares are taller than they are wide — the proportion of
    /// the notch's own corners — and deliberately small: this join reads as a
    /// melt only when it stays close to the body.
    private func notchPath(in rect: CGRect) -> Path {
        var path = Path()
        let fw = min(Theme.notchFlareWidth, rect.width / 5)
        let fh = min(Theme.notchFlareHeight, rect.height / 4)
        let v = min(convex, (rect.width - 2 * fw) / 2, (rect.height - fh) / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.minX + fw, y: rect.minY + fh),
                      control1: CGPoint(x: rect.minX + fw * 0.55, y: rect.minY),
                      control2: CGPoint(x: rect.minX + fw, y: rect.minY + fh * 0.45))
        path.addLine(to: CGPoint(x: rect.minX + fw, y: rect.maxY - v))
        path.addCurve(to: CGPoint(x: rect.minX + fw + v, y: rect.maxY),
                      control1: CGPoint(x: rect.minX + fw, y: rect.maxY - v * 0.45),
                      control2: CGPoint(x: rect.minX + fw + v * 0.45, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - fw - v, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX - fw, y: rect.maxY - v),
                      control1: CGPoint(x: rect.maxX - fw - v * 0.45, y: rect.maxY),
                      control2: CGPoint(x: rect.maxX - fw, y: rect.maxY - v * 0.45))
        path.addLine(to: CGPoint(x: rect.maxX - fw, y: rect.minY + fh))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                      control1: CGPoint(x: rect.maxX - fw, y: rect.minY + fh * 0.45),
                      control2: CGPoint(x: rect.maxX - fw * 0.55, y: rect.minY))
        path.closeSubpath() // straight run along the notch bottom
        return path
    }
}

/// Which side of the bubble carries the tail.
enum TailEdge {
    case left, right
    /// Pointing up at a ring in the horizontal, notch-hung rail.
    case top
}

/// A bubble whose tail lines up with the ring under the cursor.
struct BubbleShape: Shape {

    /// Position of the tip along the tail's edge, in the bubble's own
    /// coordinates: a y for .left/.right, an x for .top.
    var tailPosition: CGFloat
    var tailEdge: TailEdge = .right
    var radius: CGFloat = Theme.bubbleRadius
    var tailWidth: CGFloat = Theme.bubbleTailWidth
    var tailHeight: CGFloat = Theme.bubbleTailHeight

    var animatableData: CGFloat {
        get { tailPosition }
        set { tailPosition = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let body: CGRect
        switch tailEdge {
        case .right:
            body = CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width - tailWidth, height: rect.height)
        case .left:
            body = CGRect(x: rect.minX + tailWidth, y: rect.minY,
                          width: rect.width - tailWidth, height: rect.height)
        case .top:
            body = CGRect(x: rect.minX, y: rect.minY + tailWidth,
                          width: rect.width, height: rect.height - tailWidth)
        }

        path.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius),
                            style: .continuous)

        // The tail stays within the body's straight run, so it never detaches
        // when the active ring is the first or the last of the line.
        let half = tailHeight / 2
        var tail = Path()

        if tailEdge == .top {
            let x = min(max(tailPosition, body.minX + radius + half),
                        body.maxX - radius - half)
            let baseY = body.minY
            let tipY = rect.minY
            tail.move(to: CGPoint(x: x - half, y: baseY))
            tail.addQuadCurve(to: CGPoint(x: x, y: tipY),
                              control: CGPoint(x: x - half * 0.42,
                                               y: baseY + (tipY - baseY) * 0.72))
            tail.addQuadCurve(to: CGPoint(x: x + half, y: baseY),
                              control: CGPoint(x: x + half * 0.42,
                                               y: baseY + (tipY - baseY) * 0.72))
        } else {
            let y = min(max(tailPosition, body.minY + radius + half),
                        body.maxY - radius - half)
            let baseX = tailEdge == .right ? body.maxX : body.minX
            let tipX = tailEdge == .right ? rect.maxX : rect.minX
            tail.move(to: CGPoint(x: baseX, y: y - half))
            // The two quads give the tip the same soft radius as the body,
            // instead of a sharp triangle.
            tail.addQuadCurve(to: CGPoint(x: tipX, y: y),
                              control: CGPoint(x: baseX + (tipX - baseX) * 0.72,
                                               y: y - half * 0.42))
            tail.addQuadCurve(to: CGPoint(x: baseX, y: y + half),
                              control: CGPoint(x: baseX + (tipX - baseX) * 0.72,
                                               y: y + half * 0.42))
        }
        tail.closeSubpath()

        path.addPath(tail)
        return path
    }
}
