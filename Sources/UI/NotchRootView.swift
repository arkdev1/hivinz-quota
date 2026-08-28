import SwiftUI
import Observation

/// Hover does not come from SwiftUI but from an `NSTrackingArea` with
/// `.activeAlways`: `.onHover` only answers while the app is frontmost, and this
/// app is never frontmost.
@Observable
@MainActor
final class HoverModel {
    var hoveredIndex: Int?
}

/// The contents of the edge-anchored panel: the rail and nothing else. The
/// bubble lives in a separate panel that ignores the mouse — otherwise its large
/// transparent area would swallow clicks meant for whatever is underneath.
struct NotchRailView: View {

    var store = UsageStore.shared
    var prefs = Preferences.shared
    var hover: HoverModel

    var body: some View {
        let providers = prefs.enabledProviders
        let metrics = RailMetrics(itemCount: providers.count,
                                  notchMode: prefs.notchModeActive)

        Group {
            if prefs.notchModeActive {
                // Hanging from the notch the rail runs horizontally: rings in a
                // row, the way the notch itself widens.
                HStack(spacing: metrics.hItemSpacing) {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { pair in
                        item(pair.1, index: pair.0, metrics: metrics)
                            .frame(width: metrics.itemWidth)
                    }
                }
                .padding(.top, metrics.notchTopInset)
            } else {
                VStack(spacing: Theme.itemSpacing) {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { pair in
                        item(pair.1, index: pair.0, metrics: metrics)
                    }
                }
                .padding(.top, metrics.contentTop)
            }
        }
        .frame(width: metrics.railTotalWidth, height: metrics.railHeight, alignment: .top)
        .background(
            NotchRailShape(attachment: prefs.notchModeActive ? .notch
                            : (prefs.anchorOnRight ? .rightEdge : .leftEdge))
                .fill(Theme.surface)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hover.hoveredIndex)
        .allowsHitTesting(false) // hover and clicks are handled by the AppKit tracking area
    }

    private func item(_ provider: Provider, index: Int, metrics: RailMetrics) -> some View {
        let window = store.state(for: provider.id).snapshot?.headline
        return VStack(spacing: Theme.ringToLabel) {
            RingGauge(fraction: window?.clampedFraction ?? 0,
                      glyph: provider.glyph,
                      dimmed: window == nil)
            Text(window?.percentText ?? "—")
                .font(Theme.rounded(13, .semibold))
                .foregroundStyle(window == nil ? Theme.secondaryText : Theme.primaryText)
                .frame(height: metrics.labelHeight)
        }
        .opacity(hover.hoveredIndex == nil || hover.hoveredIndex == index ? 1 : 0.4)
        .scaleEffect(hover.hoveredIndex == index ? 1.06 : 1)
    }
}
