import SwiftUI

/// Provider marks are trademarked, so none are imported here: these are our own
/// vector glyphs — recognisable in spirit, original in execution.
struct ProviderGlyph: View {
    let kind: GlyphKind
    var size: CGFloat = 15

    var body: some View {
        Group {
            switch kind {
            case .anthropic: BurstGlyph(spokes: 12).fill(Theme.primaryText)
            case .openai:    KnotGlyph().stroke(Theme.primaryText,
                                 style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            case .gemini:    SparkGlyph().fill(Theme.primaryText)
            case .terminal:  Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: size * 0.72, weight: .semibold))
                                .foregroundStyle(Theme.primaryText)
            case .sparkle:   Image(systemName: "sparkles")
                                .font(.system(size: size * 0.8, weight: .semibold))
                                .foregroundStyle(Theme.primaryText)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A rosette of tapered blades: the radial-asterisk shape.
struct BurstGlyph: Shape {
    var spokes: Int = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.10
        let halfAngle: CGFloat = (.pi / CGFloat(spokes)) * 0.30

        for i in 0..<spokes {
            let angle: CGFloat = (CGFloat(i) / CGFloat(spokes)) * 2 * .pi - .pi / 2
            let tip = CGPoint(x: center.x + cos(angle) * outer,
                              y: center.y + sin(angle) * outer)
            let a = CGPoint(x: center.x + cos(angle - halfAngle) * inner,
                            y: center.y + sin(angle - halfAngle) * inner)
            let b = CGPoint(x: center.x + cos(angle + halfAngle) * inner,
                            y: center.y + sin(angle + halfAngle) * inner)
            path.move(to: a)
            path.addQuadCurve(to: tip, control: CGPoint(x: center.x + cos(angle - halfAngle * 0.4) * outer * 0.62,
                                                        y: center.y + sin(angle - halfAngle * 0.4) * outer * 0.62))
            path.addQuadCurve(to: b, control: CGPoint(x: center.x + cos(angle + halfAngle * 0.4) * outer * 0.62,
                                                      y: center.y + sin(angle + halfAngle * 0.4) * outer * 0.62))
            path.closeSubpath()
        }
        path.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner,
                                   width: inner * 2, height: inner * 2))
        return path
    }
}

/// Rotated ellipses: the interlaced-knot silhouette. Petal proportions are
/// tuned for legibility at ring size — narrower petals and one extra rotation
/// turn into lace at 15pt, so three wide ellipses it is.
struct KnotGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let petal = CGRect(x: -r * 0.42, y: -r, width: r * 0.84, height: r * 2)

        for i in 0..<3 {
            let angle: CGFloat = CGFloat(i) * .pi / 3
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle)
            path.addPath(Path(ellipseIn: petal), transform: transform)
        }
        return path
    }
}

/// A four-pointed star with concave sides.
struct SparkGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let waist = r * 0.26

        let tips = [
            CGPoint(x: center.x, y: center.y - r),
            CGPoint(x: center.x + r, y: center.y),
            CGPoint(x: center.x, y: center.y + r),
            CGPoint(x: center.x - r, y: center.y)
        ]
        path.move(to: tips[0])
        for i in 0..<4 {
            let next = tips[(i + 1) % 4]
            let angle: CGFloat = (CGFloat(i) + 0.5) * .pi / 2 - .pi / 2
            let control = CGPoint(x: center.x + cos(angle) * waist,
                                  y: center.y + sin(angle) * waist)
            path.addQuadCurve(to: next, control: control)
        }
        path.closeSubpath()
        return path
    }
}
