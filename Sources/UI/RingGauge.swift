import SwiftUI

struct RingGauge: View {
    let fraction: Double
    let glyph: GlyphKind
    var size: CGFloat = Theme.ringSize
    var lineWidth: CGFloat = Theme.ringLineWidth
    var dimmed: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(min(fraction, 1), 0.001))
                .stroke(dimmed ? Theme.track : Theme.severity(fraction),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // The arc starts at twelve o'clock, not at three.
                .rotationEffect(.degrees(-90))
            ProviderGlyph(kind: glyph, size: size * 0.44)
                .opacity(dimmed ? 0.4 : 1)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.45), value: fraction)
    }
}

/// The horizontal bar inside the bubble.
struct LinearMeter: View {
    let fraction: Double
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(Theme.severity(fraction))
                    .frame(width: max(geo.size.width * min(max(fraction, 0), 1), height))
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.45), value: fraction)
    }
}
