import AppKit
import SwiftUI

final class SelectionOverlayWindow: NSWindow {
    private var startPoint: CGPoint?
    private var currentRect: CGRect = .zero
    private let onSelection: (CGRect) -> Void
    private let onCancel: () -> Void
    private var overlayView: SelectionOverlayView?

    init(screen: NSScreen, onSelection: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onSelection = onSelection
        self.onCancel = onCancel

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false

        let view = SelectionOverlayView(frame: screen.frame)
        self.overlayView = view
        self.contentView = view

        NSCursor.crosshair.set()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            onCancel()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = event.locationInWindow
        startPoint = point
        currentRect = CGRect(origin: point, size: .zero)
        overlayView?.selectionRect = currentRect
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = event.locationInWindow

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)

        currentRect = CGRect(x: x, y: y, width: width, height: height)
        overlayView?.selectionRect = currentRect
    }

    override func mouseUp(with event: NSEvent) {
        print("[SelectionOverlay] mouseUp - currentRect: \(currentRect)")
        guard currentRect.width > 5 && currentRect.height > 5 else {
            print("[SelectionOverlay] Selection too small, resetting")
            startPoint = nil
            currentRect = .zero
            overlayView?.selectionRect = .zero
            return
        }

        let screenFrame = frame
        let flippedRect = CGRect(
            x: currentRect.origin.x,
            y: screenFrame.height - currentRect.origin.y - currentRect.height,
            width: currentRect.width,
            height: currentRect.height
        )

        print("[SelectionOverlay] Calling onSelection with rect: \(flippedRect)")
        NSCursor.arrow.set()
        onSelection(flippedRect)
    }
}

final class SelectionOverlayView: NSView {
    var selectionRect: CGRect = .zero {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

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
}
