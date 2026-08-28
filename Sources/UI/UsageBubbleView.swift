import SwiftUI

struct UsageBubbleView: View {
    let provider: Provider
    let state: ProviderState
    let tailCenterY: CGFloat
    let height: CGFloat
    var tailOnRight: Bool = true
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
            BubbleShape(tailCenterY: tailCenterY, tailOnRight: tailOnRight)
                .fill(Theme.surface)
                .shadow(color: Theme.shadowColor, radius: Theme.shadowRadius, y: 6)
                // The bubble spans the body plus the tail, which juts out to the side.
                .frame(width: Theme.bubbleWidth + Theme.bubbleTailWidth)
                .offset(x: tailOnRight ? Theme.bubbleTailWidth / 2 : -Theme.bubbleTailWidth / 2)
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
