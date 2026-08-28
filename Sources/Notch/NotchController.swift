import AppKit
import SwiftUI
import Observation

/// Owns the two panels and keeps them pinned to the screen edge.
@MainActor
final class NotchController {

    private var railPanel: NotchPanel?
    private var bubblePanel: NotchPanel?
    private let hover = HoverModel()
    private let prefs = Preferences.shared
    private let store = UsageStore.shared

    private var hideWorkItem: DispatchWorkItem?
    private var metrics = RailMetrics(itemCount: 0)

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        trackPreferences()
    }

    /// `withObservationTracking` fires exactly once, so it has to be re-armed
    /// every time — otherwise the rail stops following preferences after the
    /// first change.
    private func trackPreferences() {
        withObservationTracking {
            _ = prefs.enabledProviders.map(\.id)
            _ = prefs.anchorOnRight
            _ = prefs.useNotchAnchor
            _ = prefs.verticalOffset
            _ = prefs.showNotchWidget
        } onChange: {
            Task { @MainActor [weak self] in self?.rebuild() }
        }
    }

    private func rebuild() {
        defer { trackPreferences() }

        let providers = prefs.enabledProviders
        guard prefs.showNotchWidget, !providers.isEmpty, targetScreen() != nil else {
            teardown()
            return
        }

        metrics = RailMetrics(itemCount: providers.count)
        let panel = railPanel ?? makeRailPanel()
        railPanel = panel
        panel.setContentSize(CGSize(width: metrics.railTotalWidth, height: metrics.railHeight))

        if let tracking = panel.contentView as? TrackingHostView {
            configure(tracking)
        }
        reposition()
        panel.orderFrontRegardless()
    }

    /// Moves the rail without rebuilding it: this runs on every drag event.
    private func reposition() {
        guard let panel = railPanel, let screen = targetScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        let size = CGSize(width: metrics.railTotalWidth, height: metrics.railHeight)
        panel.setFrameOrigin(
            geometry.panelOrigin(panelSize: size,
                                 railTotalWidth: metrics.railTotalWidth,
                                 anchorOnRight: prefs.anchorOnRight,
                                 useNotchAnchor: prefs.useNotchAnchor,
                                 verticalOffset: prefs.verticalOffset)
        )
    }

    private func teardown() {
        hideBubble()
        railPanel?.orderOut(nil)
        railPanel = nil
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { NotchGeometry(screen: $0).hasNotch }) ?? NSScreen.main
    }

    // MARK: - Rail

    private func makeRailPanel() -> NotchPanel {
        let panel = NotchPanel(
            size: CGSize(width: metrics.railTotalWidth, height: metrics.railHeight),
            interactive: true
        )
        let host = TrackingHostView()
        let hosting = NSHostingView(rootView: NotchRailView(hover: hover))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: host.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        panel.contentView = host
        return panel
    }

    private func configure(_ host: TrackingHostView) {
        host.interactiveRect = { [weak self] in
            guard let self else { return .zero }
            return CGRect(x: 0, y: 0,
                          width: self.metrics.railTotalWidth,
                          height: self.metrics.railHeight)
        }
        host.rowIndex = { [weak self] point in self?.metrics.rowIndex(atY: point.y) }
        host.onHover = { [weak self] index in self?.handleHover(index) }
        host.onClick = { [weak self] in self?.openSettings() }
        host.onDragBegan = { [weak self] in self?.beginDrag() }
        host.onDrag = { [weak self] location in self?.drag(to: location) }
        host.onDragEnded = { [weak self] in self?.dragGrabOffset = nil }
        host.updateTrackingAreas()
    }

    private func handleHover(_ index: Int?) {
        hideWorkItem?.cancel()
        guard let index, index < prefs.enabledProviders.count else {
            // A short delay on the way out: crossing the edge shouldn't make the
            // bubble flicker.
            let work = DispatchWorkItem { [weak self] in
                self?.hover.hoveredIndex = nil
                self?.hideBubble()
            }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            return
        }
        hover.hoveredIndex = index
        showBubble(for: index)
    }

    // MARK: - Dragging

    /// Where along the rail the pointer grabbed it, so the rail doesn't jump
    /// under the cursor on the first drag event.
    private var dragGrabOffset: CGFloat?

    private func beginDrag() {
        hideBubble()
        hover.hoveredIndex = nil
        guard let panel = railPanel else { return }
        dragGrabOffset = panel.frame.maxY - NSEvent.mouseLocation.y
    }

    private func drag(to location: NSPoint) {
        guard let screen = targetScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        let grab = dragGrabOffset ?? metrics.railHeight / 2

        let offset = geometry.topEdge - (location.y + grab)
        prefs.verticalOffset = min(max(offset, 0),
                                   geometry.maxVerticalOffset(railHeight: metrics.railHeight))

        // Dragging past the middle of the screen flips the rail to the other edge.
        prefs.anchorOnRight = location.x > screen.frame.midX

        reposition()
    }

    // MARK: - Bubble

    private func showBubble(for index: Int) {
        let providers = prefs.enabledProviders
        guard index < providers.count, let rail = railPanel,
              let screen = rail.screen ?? NSScreen.main else { return }

        let provider = providers[index]
        let windowCount = store.state(for: provider.id).snapshot?.windows.count ?? 1
        let height = metrics.bubbleHeight(windowCount: windowCount)
        let width = Theme.bubbleWidth + Theme.bubbleTailWidth
        let pad = Theme.bubbleShadowPad

        // Ring centre in screen coordinates.
        let railTop = rail.frame.maxY
        let ringCenterY = railTop - metrics.ringCenterY(index)

        let tipX = prefs.anchorOnRight
            ? rail.frame.minX + Theme.concaveRadius - Theme.bubbleGap
            : rail.frame.maxX - Theme.concaveRadius + Theme.bubbleGap
        let originX = prefs.anchorOnRight ? tipX - width : tipX

        // The bubble centres on its ring, but never rides up over the menu bar
        // and never falls off the bottom. Clamping to the rail's own top instead
        // would shove it downwards whenever the rail has been dragged away.
        let lowest = screen.visibleFrame.minY + 8
        let ceiling = NotchGeometry(screen: screen).topEdge
        let highest = max(ceiling - height, lowest)
        let originY = min(max(ringCenterY - height / 2, lowest), highest)
        let tailCenterY = (originY + height) - ringCenterY

        let content = NotchBubbleView(provider: provider,
                                      tailCenterY: tailCenterY,
                                      height: height,
                                      tailOnRight: prefs.anchorOnRight)

        let panel = bubblePanel ?? NotchPanel(
            size: CGSize(width: width + pad * 2, height: height + pad * 2),
            interactive: false
        )
        bubblePanel = panel

        if let hosting = panel.contentView as? NSHostingView<NotchBubbleView> {
            hosting.rootView = content
        } else {
            panel.contentView = NSHostingView(rootView: content)
        }

        // The panel is inflated on every side so the shadow has somewhere to go;
        // the shape itself still lands exactly where the geometry above put it.
        panel.setFrame(CGRect(x: originX - pad, y: originY - pad,
                              width: width + pad * 2, height: height + pad * 2),
                       display: true)
        panel.orderFrontRegardless()
    }

    private func hideBubble() {
        bubblePanel?.orderOut(nil)
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

/// Contents of the bubble panel. The `TimelineView` keeps the "Resets in …"
/// countdown moving without waiting for the next data refresh.
struct NotchBubbleView: View {
    var store = UsageStore.shared
    let provider: Provider
    let tailCenterY: CGFloat
    let height: CGFloat
    let tailOnRight: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            UsageBubbleView(provider: provider,
                            state: store.state(for: provider.id),
                            tailCenterY: tailCenterY,
                            height: height,
                            tailOnRight: tailOnRight,
                            now: context.date)
        }
        .padding(Theme.bubbleShadowPad)   // room for the shadow to fade out
        .allowsHitTesting(false)
    }
}
