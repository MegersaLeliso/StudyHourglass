import AppKit
import SwiftUI
import Observation

/// Borderless, transparent, always-on-top panel that never steals app activation.
final class FloatingPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false   // the pill draws its own edge; the rest of the window is clear
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true   // only becomes key for the custom-minutes text field
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Layout (size)

/// The widget's scale and every size derived from it. The window is `baseSize * scale`:
/// the timer pill sits at the top, and the hover controls attach directly beneath it.
/// Everything outside the pill/controls is fully transparent, so clicks pass through.
@Observable
final class WidgetLayout {
    static let baseSize = NSSize(width: 168, height: 92)
    static let scaleRange: ClosedRange<CGFloat> = 0.6...2.5
    static let defaultScale: CGFloat = 1.0
    static let presets: [(name: String, scale: CGFloat)] = [("Compact", 0.8), ("Normal", 1.0), ("Large", 1.6)]

    // New key: the numbers-only pill has different proportions from the old hourglass.
    private static let scaleKey = "widgetScale.v3"

    private(set) var scale: CGFloat

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.scaleKey)
        scale = saved > 0 ? Self.clamp(CGFloat(saved)) : Self.defaultScale
    }

    var size: NSSize { NSSize(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale) }

    // Pill
    var digitFont: CGFloat { max(10, 24 * scale) }
    var pillTop: CGFloat { 4 * scale }              // room for the alarm glow
    var pillCorner: CGFloat { 14 * scale }
    var pillHeight: CGFloat { (digitFont * 1.2 + 14 * scale).rounded(.up) }
    /// Fits MM:SS or HH:MM:SS in the monospaced font (~0.62 em per character) plus padding.
    func pillWidth(hours: Bool) -> CGFloat {
        (CGFloat(hours ? 8 : 5) * 0.62 * digitFont + 28 * scale).rounded(.up)
    }
    /// Pill frame in top-left-origin window coordinates.
    func pillRect(hours: Bool) -> CGRect {
        let w = pillWidth(hours: hours)
        return CGRect(x: (size.width - w) / 2, y: pillTop, width: w, height: pillHeight)
    }

    // Controls
    var controlsGap: CGFloat { 4 * scale }
    var buttonSide: CGFloat { max(18, 26 * scale) }

    // Resize grip: the pill's bottom-right corner.
    var gripSide: CGFloat { max(12, 18 * scale) }
    func gripRect(hours: Bool) -> CGRect {
        let pill = pillRect(hours: hours)
        return CGRect(x: pill.maxX - gripSide, y: pill.maxY - gripSide, width: gripSide, height: gripSide)
    }

    /// Clamps, stores and persists a new scale; returns the value actually applied.
    @discardableResult
    func update(_ newScale: CGFloat) -> CGFloat {
        let value = Self.clamp(newScale)
        if abs(value - scale) > 0.0005 {
            scale = value
            UserDefaults.standard.set(Double(value), forKey: Self.scaleKey)
        }
        return value
    }

    static func clamp(_ s: CGFloat) -> CGFloat { min(max(s, scaleRange.lowerBound), scaleRange.upperBound) }
}

// MARK: - Hosting view

/// Lets the user drag the widget from anywhere that isn't a control, resize it from
/// the bottom-right grip, and zoom it with a pinch or scroll wheel.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    weak var controller: FloatingPanelController?

    /// A mouse-down in the grip must reach `mouseDown(with:)` instead of moving the window.
    override var mouseDownCanMoveWindow: Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown else { return true }
        return !isInResizeGrip(event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isInResizeGrip(event), let controller {
            controller.trackResize()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        guard let controller else { return super.magnify(with: event) }
        controller.setScale(controller.layout.scale * (1 + event.magnification), anchor: .center)
    }

    /// Mouse wheels zoom directly; trackpad scrolling zooms only with ⌘ held, so ordinary
    /// two-finger scrolling over the widget doesn't resize it by accident.
    override func scrollWheel(with event: NSEvent) {
        guard let controller,
              !event.hasPreciseScrollingDeltas || event.modifierFlags.contains(.command) else {
            return super.scrollWheel(with: event)
        }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.004 : event.scrollingDeltaY * 0.04
        guard delta != 0 else { return }
        controller.setScale(controller.layout.scale * (1 + delta), anchor: .center)
    }

    private func isInResizeGrip(_ event: NSEvent) -> Bool {
        guard let controller else { return false }
        let p = convert(event.locationInWindow, from: nil)
        let topLeft = CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y)
        return controller.layout.gripRect(hours: controller.model.showsHours).contains(topLeft)
    }
}

// MARK: - Controller

final class FloatingPanelController {
    enum Anchor { case topLeft, center }

    private static let edgeMargin: CGFloat = 14
    private static let originXKey = "widgetOriginX"
    private static let topYKey = "widgetTopY"

    let layout = WidgetLayout()
    let model: TimerModel
    private let panel: FloatingPanel
    private var observers: [NSObjectProtocol] = []

    init(model: TimerModel) {
        self.model = model
        panel = FloatingPanel(size: layout.size)
        let host = DraggableHostingView(rootView: ContentView().environment(model).environment(layout))
        host.frame = NSRect(origin: .zero, size: layout.size)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        host.controller = self

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePosition() }
        })
        // Displays changed: only rescue the widget if it ended up off every screen.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.ensureOnScreen() }
        })
    }

    /// Shows the widget at its saved position (or docked right the very first time).
    func show() {
        if !restorePosition() { dock() }
        ensureOnScreen()
        panel.orderFrontRegardless()
    }

    func toggle() {
        panel.isVisible ? panel.orderOut(nil) : show()
    }

    /// Manual "Dock Right": against the right edge, vertically centered. Never automatic.
    func dock() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - Self.edgeMargin,
                                     y: visible.midY - size.height / 2))
        panel.orderFrontRegardless()
    }

    // MARK: Size

    /// Applies a new scale and resizes the panel, keeping the given anchor fixed on screen.
    func setScale(_ scale: CGFloat, anchor: Anchor) {
        let old = panel.frame
        layout.update(scale)
        let size = layout.size
        guard abs(size.width - old.width) > 0.01 || abs(size.height - old.height) > 0.01 else { return }

        let origin: NSPoint
        switch anchor {
        case .topLeft: origin = NSPoint(x: old.minX, y: old.maxY - size.height)
        case .center:  origin = NSPoint(x: old.midX - size.width / 2, y: old.midY - size.height / 2)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Drag-to-resize from the pill's bottom-right corner. The pointer's movement is projected
    /// onto the widget's diagonal so the aspect ratio is always preserved.
    func trackResize() {
        let start = NSEvent.mouseLocation
        let startScale = layout.scale
        let base = WidgetLayout.baseSize
        let norm = base.width * base.width + base.height * base.height

        panel.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity,
                          mode: .eventTracking) { event, stop in
            guard let event else { return }
            if event.type == .leftMouseUp { stop.pointee = true; return }
            let now = NSEvent.mouseLocation
            let dx = now.x - start.x
            let dy = start.y - now.y   // dragging down grows the widget
            setScale(startScale + (dx * base.width + dy * base.height) / norm, anchor: .topLeft)
        }
        savePosition()
    }

    // MARK: Position

    /// Remembers the top-left corner so a different size later still opens in the same spot.
    private func savePosition() {
        let frame = panel.frame
        UserDefaults.standard.set(Double(frame.minX), forKey: Self.originXKey)
        UserDefaults.standard.set(Double(frame.maxY), forKey: Self.topYKey)
    }

    private func restorePosition() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.originXKey) != nil,
              defaults.object(forKey: Self.topYKey) != nil else { return false }
        let x = defaults.double(forKey: Self.originXKey)
        let top = defaults.double(forKey: Self.topYKey)
        panel.setFrameOrigin(NSPoint(x: x, y: top - panel.frame.height))
        return true
    }

    /// If the widget isn't visible on any screen (e.g. a display was unplugged), dock it.
    private func ensureOnScreen() {
        let frame = panel.frame
        let visible = NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width >= min(40, frame.width) && overlap.height >= min(40, frame.height)
        }
        if !visible { dock() }
    }
}

// MARK: - Time's Up alert window

/// Centered, screen-interrupting "Time's Up!" card shown above other apps until the user
/// dismisses or restarts.
final class AlarmWindowController {
    private let model: TimerModel
    private var panel: NSPanel?

    init(model: TimerModel) {
        self.model = model
    }

    func present() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Center on the screen the user is working on (where the pointer is).
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        }

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 380, height: 250)
        let panel = AlarmPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let host = NSHostingView(rootView: AlarmView().environment(model))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }
}

private final class AlarmPanel: NSPanel {
    override var canBecomeKey: Bool { true }   // so Return / Esc reach the buttons
    override var canBecomeMain: Bool { false }
}
