import CoreGraphics

/// Geometry computed, not measured. The bubble has to point at the exact centre
/// of the ring under the cursor: doing that from asynchronous layout measurements
/// gives a visible jump on the first frame, doing it with arithmetic does not.
struct RailMetrics {

    let itemCount: Int
    /// Hanging from the notch: side flares add width instead of the top ones
    /// adding height at the outer edge.
    var notchMode: Bool = false

    var labelHeight: CGFloat { 16 }
    var itemHeight: CGFloat { Theme.ringSize + Theme.ringToLabel + labelHeight }

    /// The concave fillets take vertical room at both ends of the shape, so the
    /// content starts below the top one.
    var contentTop: CGFloat { Theme.concaveRadius + Theme.railTopInset }

    var railHeight: CGFloat {
        guard itemCount > 0 else { return contentTop + Theme.railBottomInset }
        return contentTop
            + CGFloat(itemCount) * itemHeight
            + CGFloat(itemCount - 1) * Theme.itemSpacing
            + Theme.railBottomInset
            + Theme.concaveRadius
    }

    var railTotalWidth: CGFloat {
        notchMode ? Theme.railWidth + 2 * Theme.notchFlareWidth : Theme.railWidth
    }

    /// Horizontal inset of the body inside the panel.
    var sideInset: CGFloat { notchMode ? Theme.notchFlareWidth : 0 }

    /// Vertical centre of ring i, measured from the top of the rail.
    func ringCenterY(_ index: Int) -> CGFloat {
        contentTop
            + CGFloat(index) * (itemHeight + Theme.itemSpacing)
            + Theme.ringSize / 2
    }

    /// The vertical band a row owns, including half the gap to its neighbours:
    /// running the cursor down the rail swaps the bubble's contents without it
    /// ever blinking out in between.
    func rowBand(_ index: Int) -> ClosedRange<CGFloat> {
        let top = contentTop + CGFloat(index) * (itemHeight + Theme.itemSpacing)
        let lower = index == 0 ? 0 : top - Theme.itemSpacing / 2
        let upper = index == itemCount - 1 ? railHeight : top + itemHeight + Theme.itemSpacing / 2
        return lower...upper
    }

    func rowIndex(atY y: CGFloat) -> Int? {
        (0..<itemCount).first { rowBand($0).contains(y) }
    }

    /// The bubble's fixed height, derived from the same values it is built from,
    /// so the tail can be placed before any layout has been measured.
    func bubbleHeight(windowCount: Int) -> CGFloat {
        let n = CGFloat(max(windowCount, 1))
        let verticalPadding: CGFloat = 28
        let header: CGFloat = 19
        let headerSpacing: CGFloat = 14
        let block: CGFloat = 50          // label + bar + percentage/reset row
        let blockSpacing: CGFloat = 14
        return verticalPadding + header + headerSpacing + n * block + (n - 1) * blockSpacing
    }

    var panelWidth: CGFloat {
        Theme.bubbleWidth + Theme.bubbleTailWidth + Theme.bubbleGap + railTotalWidth
    }

    /// The panel has to fit a bubble taller than the rail itself.
    func panelHeight(maxWindowCount: Int) -> CGFloat {
        max(railHeight, bubbleHeight(windowCount: maxWindowCount) + 24)
    }
}
