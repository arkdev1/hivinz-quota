import SwiftUI

struct UsageBubbleView: View {
    let provider: Provider
    let state: ProviderState
    /// Position of the tail tip along its edge: y for side tails, x for top.
    let tailPosition: CGFloat
    let height: CGFloat
    var tailEdge: TailEdge = .right
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ProviderGlyph(kind: provider.glyph, size: 17)
                Text(provider.displayName)
                    .font(Theme.rounded(16, .semibold))
                    .foregroundStyle(Theme.primaryText)
            }

            switch state {
            case .ready(let snapshot):
                ForEach(snapshot.windows) { window in
                    windowBlock(window)
                }
            case .loading:
                message("Reading logs…")
            case .unavailable(let reason):
                message(reason)
            case .failed(let reason):
                message(reason, tint: Color(nsColor: .systemRed))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: Theme.bubbleWidth, height: height, alignment: .topLeading)
        .background(
            // The shape spans the body plus the tail, which juts out of one edge.
            BubbleShape(tailPosition: tailPosition, tailEdge: tailEdge)
                .fill(Theme.surface)
                .shadow(color: Theme.shadowColor, radius: Theme.shadowRadius,
                        y: tailEdge == .top ? 8 : 6)
                .frame(width: tailEdge == .top ? Theme.bubbleWidth
                        : Theme.bubbleWidth + Theme.bubbleTailWidth,
                       height: tailEdge == .top ? height + Theme.bubbleTailWidth : height)
                .offset(x: tailEdge == .right ? Theme.bubbleTailWidth / 2
                            : tailEdge == .left ? -Theme.bubbleTailWidth / 2 : 0,
                        y: tailEdge == .top ? -Theme.bubbleTailWidth / 2 : 0)
        )
    }

    private func windowBlock(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(window.label)
                .font(Theme.rounded(13))
                .foregroundStyle(Theme.primaryText)
            LinearMeter(fraction: window.clampedFraction)
            HStack {
                Text("\(window.percentText) Used")
                Spacer(minLength: 8)
                Text(window.resetText(now: now))
            }
            .font(Theme.rounded(12))
            .foregroundStyle(Theme.secondaryText)
        }
    }

    private func message(_ text: String, tint: Color = Theme.secondaryText) -> some View {
        Text(text)
            .font(Theme.rounded(12.5))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}
