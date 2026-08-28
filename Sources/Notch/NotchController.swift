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
    private var showWorkItem: DispatchWorkItem?
    private var metrics = RailMetrics(itemCount: 0)
    /// The rail height the panel is currently laid out at, so a change of size
    /// can be recognised — and compensated — rather than silently shifting the
    /// rail up the screen.
    private var laidOutHeight: CGFloat = 0

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
            _ = prefs.isMinimized
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

        let geometry = targetScreen().map(NotchGeometry.init)
        prefs.notchModeActive = prefs.useNotchAnchor && (geometry?.hasNotch ?? false)
        let previousHeight = laidOutHeight
        metrics = RailMetrics(itemCount: providers.count,
                              notchMode: prefs.notchModeActive,
                              minimized: prefs.isMinimized)
        if prefs.isMinimized { hideBubble() }

        // Collapsing and expanding should look like the rail shrinking in
        // place. The panel hangs by its top edge, so without this the top would
        // stay put and the whole thing would appear to crawl up the screen.
        if previousHeight > 0, previousHeight != metrics.railHeight, !prefs.notchModeActive {
            prefs.verticalOffset += (previousHeight - metrics.railHeight) / 2
        }
        laidOutHeight = metrics.railHeight

        let panel = railPanel ?? makeRailPanel()
        railPanel = panel
        panel.setContentSize(CGSize(width: metrics.railTotalWidth, height: metrics.railHeight))

        if let tracking = panel.contentView as? TrackingHostView {
            configure(tracking)
        }
        reposition(animated: previousHeight > 0 && previousHeight != metrics.railHeight)
        panel.orderFrontRegardless()
    }

    /// Moves the rail without rebuilding it: this runs on every drag event.
    private func reposition(animated: Bool = false) {
        guard let panel = railPanel, let screen = targetScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        let size = CGSize(width: metrics.railTotalWidth, height: metrics.railHeight)

        // Re-clamp: a taller rail restored near the bottom of the screen would
        // otherwise hang off the edge.
        prefs.verticalOffset = min(max(prefs.verticalOffset, 0),
                                   geometry.maxVerticalOffset(railHeight: metrics.railHeight))

        let origin = geometry.panelOrigin(panelSize: size,
                                          railTotalWidth: metrics.railTotalWidth,
                                          anchorOnRight: prefs.anchorOnRight,
                                          useNotchAnchor: prefs.useNotchAnchor,
                                          verticalOffset: prefs.verticalOffset)
        let frame = CGRect(origin: origin, size: size)
        guard animated, panel.isVisible else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
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
        host.rowIndex = { [weak self] point in self?.metrics.itemIndex(at: point) }
        host.onHover = { [weak self] index in self?.handleHover(index) }
        host.onClick = { [weak self] in
            guard let self else { return }
            if self.prefs.isMinimized {
                self.prefs.isMinimized = false
            } else {
                self.openSettings()
            }
        }
        host.onDragBegan = { [weak self] in self?.beginDrag() }
        host.onDrag = { [weak self] location in self?.drag(to: location) }
        host.onDragEnded = { [weak self] in self?.dragGrabOffset = nil }
        host.updateTrackingAreas()
    }

    private func handleHover(_ index: Int?) {
        hideWorkItem?.cancel()
        guard let index, index < prefs.enabledProviders.count else {
            showWorkItem?.cancel()
            // Leaving the rail doesn't close the bubble by itself: the pointer
            // may be on its way over there. Remember where it left, and let the
            // safe-triangle monitor decide.
            triangleApex = NSEvent.mouseLocation
            scheduleHide(after: 0.5) // fallback if the monitor never fires
            return
        }
        hover.hoveredIndex = index

        // Already open: switching rings is instant. Opening fresh waits a beat,
        // so sweeping the pointer across the rail doesn't flash the bubble.
        if bubblePanel?.isVisible == true {
            showWorkItem?.cancel()
            showBubble(for: index)
        } else {
            showWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.showBubble(for: index) }
            showWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hover.hoveredIndex = nil
            self?.hideBubble()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Dragging

    /// Where along the rail the pointer grabbed it, so the rail doesn't jump
    /// under the cursor on the first drag event.
    private var dragGrabOffset: CGFloat?

    private func beginDrag() {
        showWorkItem?.cancel()
        hideBubble()
        hover.hoveredIndex = nil
        guard let panel = railPanel else { return }
        dragGrabOffset = panel.frame.maxY - NSEvent.mouseLocation.y
    }

    private func drag(to location: NSPoint) {
        guard let screen = targetScreen() else { return }
        // Dragging a notch-hung rail unhooks it: from there it behaves like an
        // edge-attached rail again. rebuild() follows via the preference change.
        if prefs.useNotchAnchor { prefs.useNotchAnchor = false }
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

    /// Where the pointer last left the rail: the apex of the safe triangle.
    private var triangleApex: NSPoint?
    /// The bubble body in screen coordinates, while visible.
    private var bubbleBodyFrame: CGRect = .zero
    private var mouseMonitor: Any?
    /// Set while the pointer travels the safe triangle without arriving: a
    /// pointer parked mid-flight shouldn't pin the bubble open forever.
    private var triangleDeadline: Date?
    private var bubbleGeneration = 0

    private func showBubble(for index: Int) {
        let providers = prefs.enabledProviders
        guard index < providers.count, let rail = railPanel,
              let screen = rail.screen ?? NSScreen.main else { return }

        let provider = providers[index]
        let windowCount = store.state(for: provider.id).snapshot?.windows.count ?? 1
        let height = metrics.bubbleHeight(windowCount: windowCount)
        let pad = Theme.bubbleShadowPad
        let tailEdge: TailEdge = prefs.notchModeActive ? .top
            : (prefs.anchorOnRight ? .right : .left)

        // Shape extent: side tails widen the shape, a top tail makes it taller.
        let width = tailEdge == .top ? Theme.bubbleWidth
            : Theme.bubbleWidth + Theme.bubbleTailWidth
        let shapeHeight = tailEdge == .top ? height + Theme.bubbleTailWidth : height

        let originX: CGFloat
        let originY: CGFloat
        let tailPosition: CGFloat

        if tailEdge == .top {
            // Below the horizontal rail, tail pointing up at the ring.
            let ringCenterX = rail.frame.minX + metrics.ringCenterX(index)
            let leftMost = screen.visibleFrame.minX + 8
            let rightMost = screen.visibleFrame.maxX - 8 - width
            originX = min(max(ringCenterX - width / 2, leftMost), rightMost)
            originY = rail.frame.minY - Theme.bubbleGap - shapeHeight
            tailPosition = ringCenterX - originX
        } else {
            // Ring centre in screen coordinates.
            let railTop = rail.frame.maxY
            let ringCenterY = railTop - metrics.ringCenterY(index)

            let tipX = prefs.anchorOnRight
                ? rail.frame.minX + metrics.sideInset - Theme.bubbleGap
                : rail.frame.maxX - metrics.sideInset + Theme.bubbleGap
            originX = prefs.anchorOnRight ? tipX - width : tipX

            // The bubble centres on its ring, but never rides up over the menu
            // bar and never falls off the bottom. Clamping to the rail's own top
            // instead would shove it downwards whenever the rail has been
            // dragged away.
            let lowest = screen.visibleFrame.minY + 8
            let ceiling = NotchGeometry(screen: screen).topEdge
            let highest = max(ceiling - height, lowest)
            originY = min(max(ringCenterY - height / 2, lowest), highest)
            tailPosition = (originY + height) - ringCenterY
        }

        let wasVisible = bubblePanel?.isVisible ?? false
        if !wasVisible { bubbleGeneration += 1 }
        let content = NotchBubbleView(provider: provider,
                                      tailPosition: tailPosition,
                                      height: height,
                                      tailEdge: tailEdge,
                                      generation: bubbleGeneration)
        let panel = bubblePanel ?? makeBubblePanel(
            size: CGSize(width: width + pad * 2, height: shapeHeight + pad * 2))
        bubblePanel = panel

        if let host = panel.contentView as? BubbleHostView {
            host.bodyRect = { CGRect(x: pad, y: pad, width: width, height: shapeHeight) }
            // The button rect arrives in the shape's top-left coordinates; the
            // panel is bottom-left and inflated by the shadow padding.
            let button = UsageBubbleView.minimizeButtonRect(tailEdge)
            host.buttonRect = {
                CGRect(x: pad + button.minX,
                       y: pad + shapeHeight - button.maxY,
                       width: button.width, height: button.height)
            }
            if let hosting = host.subviews.first as? NSHostingView<NotchBubbleView> {
                hosting.rootView = content
            }
            host.updateTrackingAreas()
        }

        // The panel is inflated on every side so the shadow has somewhere to go;
        // the shape itself still lands exactly where the geometry above put it.
        let frame = CGRect(x: originX - pad, y: originY - pad,
                           width: width + pad * 2, height: shapeHeight + pad * 2)
        bubbleBodyFrame = CGRect(x: originX, y: originY, width: width, height: shapeHeight)

        if wasVisible {
            // Sliding between rings: glide, don't teleport.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        }
        startMouseMonitor()
    }

    private func makeBubblePanel(size: CGSize) -> NotchPanel {
        let panel = NotchPanel(size: size, interactive: true)
        let host = BubbleHostView()
        host.onButtonClick = { [weak self] in
            Task { @MainActor in
                self?.hideBubble()
                self?.prefs.isMinimized = true
            }
        }
        host.onHoverChange = { [weak self] inside in
            Task { @MainActor in
                guard let self else { return }
                if inside {
                    self.hideWorkItem?.cancel()
                    self.triangleApex = nil
                } else {
                    self.scheduleHide(after: 0.3)
                }
            }
        }
        let hosting = NSHostingView(rootView: NotchBubbleView(
            provider: .claude, tailPosition: 0, height: 0, tailEdge: .right,
            generation: 0))
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

    private func hideBubble() {
        stopMouseMonitor()
        triangleApex = nil
        triangleDeadline = nil
        guard let panel = bubblePanel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    // MARK: - Safe triangle
    //
    // The classic submenu trick: when the pointer leaves the rail heading for
    // the bubble, the triangle between its exit point and the bubble's near
    // corners is safe ground — the bubble stays open while the pointer crosses
    // it. Without this, the gap between rail and bubble closes the bubble the
    // moment the pointer sets out.

    private func startMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.assessPointer(NSEvent.mouseLocation) }
        }
    }

    private func stopMouseMonitor() {
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
        mouseMonitor = nil
    }

    private func assessPointer(_ location: NSPoint) {
        guard let panel = bubblePanel, panel.isVisible else { return }

        // On home ground — rail or bubble — nothing to assess. (Their own
        // tracking areas already manage hover; the monitor only sees events
        // that miss our windows anyway.)
        if bubbleBodyFrame.contains(location) { return }
        if let rail = railPanel, rail.frame.contains(location) { return }

        if let apex = triangleApex,
           Self.point(location, inTriangleWith: apex,
                      corners: nearCorners(of: bubbleBodyFrame)) {
            // Crossing the safe triangle: keep the bubble open, but not forever.
            if let deadline = triangleDeadline {
                if Date() > deadline { scheduleHide(after: 0) }
            } else {
                triangleDeadline = Date().addingTimeInterval(1.2)
                hideWorkItem?.cancel()
            }
            return
        }
        scheduleHide(after: 0.15)
    }

    /// The two corners of the bubble on the side facing the rail.
    private func nearCorners(of body: CGRect) -> (NSPoint, NSPoint) {
        if prefs.notchModeActive {
            return (NSPoint(x: body.minX, y: body.maxY),
                    NSPoint(x: body.maxX, y: body.maxY))
        }
        let x = prefs.anchorOnRight ? body.maxX : body.minX
        return (NSPoint(x: x, y: body.minY), NSPoint(x: x, y: body.maxY))
    }

    private static func point(_ p: NSPoint, inTriangleWith apex: NSPoint,
                              corners: (NSPoint, NSPoint)) -> Bool {
        func cross(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        let d1 = cross(apex, corners.0, p)
        let d2 = cross(corners.0, corners.1, p)
        let d3 = cross(corners.1, apex, p)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
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
    let tailPosition: CGFloat
    let height: CGFloat
    let tailEdge: TailEdge

    /// Bumped by the controller on every fresh appearance. The hosting view
    /// stays mounted while the panel is hidden, so `onAppear` alone would only
    /// ever animate the first entrance.
    let generation: Int

    /// Drives the entrance: the bubble springs out of its tail rather than
    /// popping into place.
    @State private var appeared = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            UsageBubbleView(provider: provider,
                            state: store.state(for: provider.id),
                            tailPosition: tailPosition,
                            height: height,
                            tailEdge: tailEdge,
                            now: context.date)
        }
        .scaleEffect(appeared ? 1 : 0.92, anchor: anchor)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: appeared)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: tailPosition)
        .onAppear { appeared = true }
        .onChange(of: generation) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { appeared = false }
            DispatchQueue.main.async { appeared = true }
        }
        .padding(Theme.bubbleShadowPad)   // room for the shadow to fade out
        .allowsHitTesting(false)
    }

    /// The entrance springs out of the tail, wherever the tail is.
    private var anchor: UnitPoint {
        switch tailEdge {
        case .right: return UnitPoint(x: 1, y: 0.5)
        case .left: return UnitPoint(x: 0, y: 0.5)
        case .top: return UnitPoint(x: 0.5, y: 0)
        }
    }
}
