import AppKit
import SwiftUI

/// A borderless panel that floats above the menu bar without ever taking focus.
final class NotchPanel: NSPanel {

    init(size: CGSize, interactive: Bool) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // SwiftUI draws the shadow so it follows the concave fillet
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Without this, a panel that never becomes key receives no mouseMoved events.
        acceptsMouseMovedEvents = interactive
        ignoresMouseEvents = !interactive
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the SwiftUI view and handles hover, clicks and dragging itself: a
/// tracking area with `.activeAlways` keeps working while the app sits in the
/// background, which is where this app spends its whole life.
final class TrackingHostView: NSView {

    /// Hit-testable region, in SwiftUI coordinates (origin top-left).
    var interactiveRect: () -> CGRect = { .zero }
    var rowIndex: (CGPoint) -> Int? = { _ in nil }
    var onHover: (Int?) -> Void = { _ in }
    var onClick: () -> Void = {}
    var onDragBegan: () -> Void = {}
    var onDrag: (NSPoint) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    private var tracking: NSTrackingArea?
    private var isDragging = false
    /// Where the press started. A click always jitters by a pixel or two, and
    /// treating that as a drag would nudge the rail every time it is clicked.
    private var pressOrigin: NSPoint?
    private let dragThreshold: CGFloat = 3

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved,
                                            .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    /// Points outside the rail aren't ours, so clicks meant for whatever is
    /// underneath pass straight through instead of being swallowed.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return interactiveRect().contains(flip(local)) ? self : nil
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isDragging else { return }
        onHover(rowIndex(flip(convert(event.locationInWindow, from: nil))))
    }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        onHover(nil)
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        pressOrigin = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        if !isDragging {
            guard let origin = pressOrigin else { return }
            let dx = location.x - origin.x, dy = location.y - origin.y
            guard (dx * dx + dy * dy).squareRoot() > dragThreshold else { return }
            isDragging = true
            onHover(nil)
            onDragBegan()
        }
        onDrag(location)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            onDragEnded()
        } else {
            onClick()
        }
    }

    /// AppKit puts the origin bottom-left, SwiftUI top-left.
    private func flip(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: bounds.height - point.y)
    }
}

/// Hosts the bubble content. The bubble accepts hover — resting the pointer on
/// it keeps it open — but only inside the bubble's body: everywhere else in the
/// inflated shadow panel, clicks and hover fall through to what's underneath.
final class BubbleHostView: NSView {

    /// The bubble body, in AppKit view coordinates (origin bottom-left).
    var bodyRect: () -> CGRect = { .zero }
    /// The minimize control, also in AppKit view coordinates.
    var buttonRect: () -> CGRect = { .zero }
    var onHoverChange: (Bool) -> Void = { _ in }
    var onButtonClick: () -> Void = {}

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved,
                                            .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bodyRect().contains(local) ? self : nil
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverChange(bodyRect().contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { onHoverChange(false) }

    override func mouseDown(with event: NSEvent) {
        if buttonRect().contains(convert(event.locationInWindow, from: nil)) {
            onButtonClick()
        }
    }
}
