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
                Spacer(minLength: 8)
                minimizeButton
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
        .padding(.horizontal, Theme.bubbleHPadding)
        .padding(.vertical, Theme.bubbleVPadding)
        .frame(width: Theme.bubbleWidth, height: height, alignment: .topLeading)
        // The shape is wider or taller than the content by the tail's reach.
        // Aligning here — rather than letting the content centre itself inside
        // the panel — is what keeps the tail tip where the controller aimed it.
        .frame(width: Self.shapeWidth(tailEdge),
               height: Self.shapeHeight(tailEdge, contentHeight: height),
               alignment: contentAlignment)
        .background(
            BubbleShape(tailPosition: tailPosition, tailEdge: tailEdge)
                .fill(Theme.surface)
                .shadow(color: Theme.shadowColor, radius: Theme.shadowRadius,
                        y: tailEdge == .top ? 8 : 6)
        )
    }

    /// Purely visual: the click is caught by the AppKit host, which owns hit
    /// testing for the whole bubble.
    private var minimizeButton: some View {
        ZStack {
            Circle().fill(Theme.track)
            Image(systemName: "minus")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(width: Theme.minimizeButtonSize, height: Theme.minimizeButtonSize)
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

    private var contentAlignment: Alignment {
        switch tailEdge {
        case .right: return .leading    // tail juts out to the right
        case .left: return .trailing
        case .top: return .bottom
        }
    }

    // MARK: - Extents, shared with the controller's geometry

    static func shapeWidth(_ edge: TailEdge) -> CGFloat {
        edge == .top ? Theme.bubbleWidth : Theme.bubbleWidth + Theme.bubbleTailWidth
    }

    static func shapeHeight(_ edge: TailEdge, contentHeight: CGFloat) -> CGFloat {
        edge == .top ? contentHeight + Theme.bubbleTailWidth : contentHeight
    }

    /// Top-left of the content box inside the shape.
    static func contentOrigin(_ edge: TailEdge) -> CGPoint {
        switch edge {
        case .right: return .zero
        case .left: return CGPoint(x: Theme.bubbleTailWidth, y: 0)
        case .top: return CGPoint(x: 0, y: Theme.bubbleTailWidth)
        }
    }

    /// The minimize button, in the shape's own coordinates (origin top-left).
    static func minimizeButtonRect(_ edge: TailEdge) -> CGRect {
        let origin = contentOrigin(edge)
        let size = Theme.minimizeButtonSize
        return CGRect(x: origin.x + Theme.bubbleWidth - Theme.bubbleHPadding - size,
                      y: origin.y + Theme.bubbleVPadding,
                      width: size, height: size)
    }
}
