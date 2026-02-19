import AppKit
import SwiftUI

struct WindowInfo {
    let id: CGWindowID
    let frame: CGRect
    let name: String?
    let ownerName: String?
}

final class SelectionOverlayWindow: NSWindow {
    private var startPoint: CGPoint?
    private var currentRect: CGRect = .zero
    private var isDragging = false
    private var onSelection: ((CGRect) -> Void)?
    private var onCancel: (() -> Void)?
    private var overlayView: SelectionOverlayView?
    private var windowsUnderCursor: [WindowInfo] = []
    private var highlightedWindowRect: CGRect?
    private let screenFrame: CGRect
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var notificationObserver: Any?
    private var isCleaned = false
    private(set) var isCountdownMode = false
    var onCountdownCancel: (() -> Void)?
    private(set) var finalLocalSelectionRect: CGRect = .zero

    init(screen: NSScreen, onSelection: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.screenFrame = screen.frame

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.onSelection = onSelection
        self.onCancel = onCancel

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false  // Keep under ARC to prevent manual release

        let view = SelectionOverlayView(frame: screen.frame)
        self.overlayView = view
        self.contentView = view

        // Load window list
        loadWindowList()

        // Local event monitor for Escape key
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.handleCancel()
                return nil
            }
            return event
        }

        // Global event monitor (captures even when app is inactive)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.handleCancel()
            }
        }

        // Reactivate when it is no longer key window
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, !self.isCleaned, self.isVisible else { return }
                self.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        NSCursor.crosshair.set()
    }

    private func handleCancel() {
        guard !isCleaned else { return }
        if isCountdownMode {
            onCountdownCancel?()
            return
        }
        guard let cancel = onCancel else { return }
        cancel()
    }

    private func handleSelection(_ rect: CGRect) {
        guard !isCleaned, let selection = onSelection else { return }
        selection(rect)
    }

    func cleanup() {
        guard !isCleaned else { return }  // Prevent double cleanup
        isCleaned = true
        onSelection = nil
        onCancel = nil
        onCountdownCancel = nil

        // Remove NotificationCenter observer
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }

        // Remove event monitors
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }

        // Hide the window immediately so it no longer intercepts mouse events
        orderOut(nil)

        // Clean up the view
        overlayView = nil
        contentView = nil
    }

    deinit {
        // Safety net: if cleanup() was never called, ensure the window is hidden.
        // isCleaned may be false here if something went wrong upstream.
        if !isCleaned {
            NSLog("[SelectionOverlayWindow] WARNING: deinit called without cleanup - forcing orderOut")
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func loadWindowList() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        // Get full screen size (exclude windows larger than this)
        let mainScreenFrame = NSScreen.main?.frame ?? screenFrame
        let selfWindowID = CGWindowID(windowNumber)

        // Build list of capture-worthy windows (layer 0 only, front-to-back order).
        // CGWindowListCopyWindowInfo returns windows front-to-back, so the first
        // match in this list is always the frontmost normal window at a given point.
        // Floating panels/toolbars (layer > 0) are intentionally excluded: if the
        // cursor is over a floating window, we fall through to the normal window below.
        windowsUnderCursor = windowList.compactMap { info -> WindowInfo? in
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"],
                  width > 50, height > 50 else {
                return nil
            }

            // Exclude the overlay window itself
            if windowID == selfWindowID {
                return nil
            }

            // Only capture normal windows (layer == 0).
            // Floating panels, toolbars, etc. (layer > 0) are excluded so they
            // don't get highlighted instead of the regular app window behind them.
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 {
                return nil
            }

            let frame = CGRect(x: x, y: y, width: width, height: height)

            // Exclude windows roughly the size of the screen (desktop, Dock, etc.)
            if width >= mainScreenFrame.width * 0.95 && height >= mainScreenFrame.height * 0.9 {
                return nil
            }

            let name = info[kCGWindowName as String] as? String
            let ownerName = info[kCGWindowOwnerName as String] as? String

            // Exclude Dock, WindowServer, and Finder desktop windows
            if ownerName == "Dock" || ownerName == "WindowServer" {
                return nil
            }
            if ownerName == "Finder" && (name == nil || name == "") {
                return nil
            }

            return WindowInfo(id: windowID, frame: frame, name: name, ownerName: ownerName)
        }
    }

    private func findWindowAt(screenPoint: CGPoint) -> WindowInfo? {
        // windowsUnderCursor is in front-to-back z-order (layer 0 only).
        // The first frame match is the frontmost normal window at this point.
        // Floating windows (Aqua Voice, etc.) are not in the list, so the cursor
        // naturally falls through to the normal window behind them.
        return windowsUnderCursor.first(where: { $0.frame.contains(screenPoint) })
    }

    private func convertToScreenCoordinates(_ windowPoint: CGPoint) -> CGPoint {
        // Convert window coordinates (bottom-left origin) to screen coordinates (top-left origin)
        let screenY = screenFrame.height - windowPoint.y + screenFrame.origin.y
        let screenX = windowPoint.x + screenFrame.origin.x
        return CGPoint(x: screenX, y: screenY)
    }

    private func convertWindowFrameToLocal(_ windowFrame: CGRect) -> CGRect {
        // Convert CGWindow coordinates (screen top-left origin) to NSView coordinates (bottom-left origin)
        let localX = windowFrame.origin.x - screenFrame.origin.x
        let localY = screenFrame.height - (windowFrame.origin.y - screenFrame.origin.y) - windowFrame.height
        return CGRect(x: localX, y: localY, width: windowFrame.width, height: windowFrame.height)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            handleCancel()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isDragging, !isCleaned, !isCountdownMode else { return }

        let windowPoint = event.locationInWindow
        let screenPoint = convertToScreenCoordinates(windowPoint)

        let found = findWindowAt(screenPoint: screenPoint)

        // Log only when the highlighted window changes
        let newID = found?.id
        let prevID = highlightedWindowRect == nil ? nil : windowsUnderCursor.first(where: {
            convertWindowFrameToLocal($0.frame) == highlightedWindowRect
        })?.id
        if newID != prevID {
            if let w = found {
                NSLog("[SelectionOverlay] highlight -> id=%u owner=%@ name=%@ frame=%@",
                      w.id,
                      w.ownerName ?? "(nil)",
                      w.name ?? "(nil)",
                      "\(w.frame)")
            } else {
                NSLog("[SelectionOverlay] highlight -> nil")
            }
        }

        if let window = found {
            let localRect = convertWindowFrameToLocal(window.frame)
            highlightedWindowRect = localRect
            overlayView?.highlightRect = localRect
        } else {
            highlightedWindowRect = nil
            overlayView?.highlightRect = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isCleaned, !isCountdownMode else { return }
        NSLog("[SelectionOverlay] mouseDown at %@", "\(event.locationInWindow)")
        let point = event.locationInWindow
        startPoint = point
        currentRect = CGRect(origin: point, size: .zero)
        isDragging = false
        overlayView?.selectionRect = currentRect
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isCleaned, !isCountdownMode else { return }
        guard let start = startPoint else { return }
        let current = event.locationInWindow

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)

        // Threshold to treat as drag start
        if width > 5 || height > 5 {
            isDragging = true
            overlayView?.highlightRect = nil
        }

        currentRect = CGRect(x: x, y: y, width: width, height: height)
        overlayView?.selectionRect = currentRect
    }

    override func mouseUp(with event: NSEvent) {
        guard !isCleaned, !isCountdownMode else { return }
        NSLog("[SelectionOverlay] mouseUp - currentRect: %@, isDragging: %d", "\(currentRect)", isDragging ? 1 : 0)

        // Selection by dragging
        if isDragging && currentRect.width > 5 && currentRect.height > 5 {
            finalLocalSelectionRect = currentRect
            let flippedRect = CGRect(
                x: currentRect.origin.x,
                y: screenFrame.height - currentRect.origin.y - currentRect.height,
                width: currentRect.width,
                height: currentRect.height
            )
            NSLog("[SelectionOverlay] Drag selection: %@", "\(flippedRect)")
            NSCursor.arrow.set()
            handleSelection(flippedRect)
            return
        }

        // Selection by clicking a window
        if let windowRect = highlightedWindowRect {
            finalLocalSelectionRect = windowRect
            let flippedRect = CGRect(
                x: windowRect.origin.x,
                y: screenFrame.height - windowRect.origin.y - windowRect.height,
                width: windowRect.width,
                height: windowRect.height
            )
            NSLog("[SelectionOverlay] Window selection: %@", "\(flippedRect)")
            NSCursor.arrow.set()
            handleSelection(flippedRect)
            return
        }

        // Reset when nothing is selected
        NSLog("[SelectionOverlay] No selection, resetting")
        startPoint = nil
        currentRect = .zero
        isDragging = false
        overlayView?.selectionRect = .zero
    }

    func enterCountdownMode() {
        isCountdownMode = true
        // Remove dark overlay and make background transparent
        backgroundColor = .clear
        // Disable mouse events
        ignoresMouseEvents = true
        // Put the view into countdown mode
        overlayView?.enterCountdownMode(selectionRect: finalLocalSelectionRect)
        NSCursor.arrow.set()
    }

    func updateCountdown(_ number: Int) {
        overlayView?.countdownNumber = number
    }
}

final class SelectionOverlayView: NSView {
    var selectionRect: CGRect = .zero {
        didSet {
            needsDisplay = true
        }
    }

    var highlightRect: CGRect? {
        didSet {
            needsDisplay = true
        }
    }

    private var isCountdownMode = false
    private var countdownSelectionRect: CGRect = .zero
    var countdownNumber: Int = 0 {
        didSet {
            needsDisplay = true
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func enterCountdownMode(selectionRect: CGRect) {
        isCountdownMode = true
        countdownSelectionRect = selectionRect
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isCountdownMode {
            drawCountdownMode()
            return
        }

        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        // Window highlight display
        if let highlight = highlightRect, selectionRect.width <= 5 && selectionRect.height <= 5 {
            NSGraphicsContext.current?.compositingOperation = .clear
            NSColor.clear.setFill()
            highlight.fill()

            NSGraphicsContext.current?.compositingOperation = .sourceOver

            NSColor.systemBlue.setStroke()
            let borderPath = NSBezierPath(rect: highlight)
            borderPath.lineWidth = 3.0
            borderPath.stroke()
        }

        // Drag selection display
        if selectionRect.width > 0 && selectionRect.height > 0 {
            NSGraphicsContext.current?.compositingOperation = .clear
            NSColor.clear.setFill()
            selectionRect.fill()

            NSGraphicsContext.current?.compositingOperation = .sourceOver

            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: selectionRect)
            borderPath.lineWidth = 1.0
            borderPath.stroke()

            let sizeText = "\(Int(selectionRect.width)) x \(Int(selectionRect.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.7)
            ]
            let textSize = sizeText.size(withAttributes: attributes)
            let textRect = CGRect(
                x: selectionRect.maxX - textSize.width - 5,
                y: selectionRect.minY - textSize.height - 5,
                width: textSize.width + 4,
                height: textSize.height + 2
            )
            sizeText.draw(in: textRect, withAttributes: attributes)
        }
    }

    private func drawCountdownMode() {
        // Transparent background (no dark overlay)
        NSColor.clear.setFill()
        bounds.fill()

        guard countdownSelectionRect.width > 0, countdownSelectionRect.height > 0 else { return }

        // Blue dashed border
        NSColor.systemBlue.setStroke()
        let borderPath = NSBezierPath(rect: countdownSelectionRect)
        borderPath.lineWidth = 2.0
        let dashPattern: [CGFloat] = [6.0, 4.0]
        borderPath.setLineDash(dashPattern, count: 2, phase: 0)
        borderPath.stroke()

        // Countdown number
        guard countdownNumber > 0 else { return }

        let rect = countdownSelectionRect
        let fontSize = min(120, min(rect.width, rect.height) * 0.6)

        let text = "\(countdownNumber)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)

        // Semi-transparent black circular background
        let circleRadius = max(textSize.width, textSize.height) * 0.8
        let circleCenter = CGPoint(x: rect.midX, y: rect.midY)
        let circleRect = CGRect(
            x: circleCenter.x - circleRadius,
            y: circleCenter.y - circleRadius,
            width: circleRadius * 2,
            height: circleRadius * 2
        )
        NSColor.black.withAlphaComponent(0.5).setFill()
        let circlePath = NSBezierPath(ovalIn: circleRect)
        circlePath.fill()

        // White text with black shadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 4
        let shadowAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .shadow: shadow
        ]
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: shadowAttributes)
    }
}
