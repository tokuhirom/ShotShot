import AppKit
import Foundation

/// Overlay window displayed during scroll capture
@MainActor
final class ScrollCaptureOverlayWindow {
    let window: NSWindow
    private let indicatorView: ScrollCaptureIndicatorView
    private var keyMonitor: Any?

    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    init(selectionRect: CGRect) {
        let padding: CGFloat = 4
        let badgeHeight: CGFloat = 32
        let badgeGap: CGFloat = 8
        let minBadgeWidth: CGFloat = 200

        let frameWidth = max(selectionRect.width + padding * 2, minBadgeWidth)
        let frameRect = NSRect(
            x: selectionRect.origin.x - padding,
            y: selectionRect.origin.y - padding - badgeHeight - badgeGap,
            width: frameWidth,
            height: selectionRect.height + padding * 2 + badgeHeight + badgeGap
        )

        indicatorView = ScrollCaptureIndicatorView(
            selectionRect: selectionRect,
            frameRect: frameRect,
            badgeHeight: badgeHeight,
            badgeGap: badgeGap,
            padding: padding
        )

        window = NSWindow(
            contentRect: frameRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.contentView = indicatorView

        indicatorView.onDone = { [weak self] in
            self?.onDone?()
        }

        // Handle keyboard events
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // Escape
                self?.onCancel?()
                return nil
            } else if event.keyCode == 36 {  // Enter
                self?.onDone?()
                return nil
            }
            return event
        }
    }

    func makeKeyAndOrderFront() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        window.orderOut(nil)
        window.close()
    }

    func updateCaptureCount(_ count: Int) {
        indicatorView.updateCaptureCount(count)
    }

    /// Shows a brief flash effect to indicate capture
    func showCaptureFlash() {
        indicatorView.showFlash()
    }
}

@MainActor
final class ScrollCaptureIndicatorView: NSView {
    private let selectionRect: CGRect
    private let badgeHeight: CGFloat
    private let badgeGap: CGFloat
    private let padding: CGFloat
    private var captureCount: Int = 0

    private let countLabel: NSTextField
    private let doneButton: NSButton
    private let hintLabel: NSTextField
    private var flashLayer: CALayer?

    var onDone: (() -> Void)?

    init(selectionRect: CGRect, frameRect: NSRect, badgeHeight: CGFloat, badgeGap: CGFloat, padding: CGFloat) {
        self.selectionRect = selectionRect
        self.badgeHeight = badgeHeight
        self.badgeGap = badgeGap
        self.padding = padding

        // Capture count label
        countLabel = NSTextField(labelWithString: "Captures: 0")
        countLabel.font = NSFont.boldSystemFont(ofSize: 13)
        countLabel.textColor = .white
        countLabel.backgroundColor = .clear
        countLabel.isBezeled = false
        countLabel.isEditable = false

        // Done button
        doneButton = NSButton(frame: .zero)
        doneButton.title = "Done"
        doneButton.bezelStyle = .rounded
        doneButton.setButtonType(.momentaryPushIn)
        doneButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        // Hint label
        hintLabel = NSTextField(labelWithString: "Scroll to capture more")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        hintLabel.backgroundColor = .clear
        hintLabel.isBezeled = false
        hintLabel.isEditable = false

        super.init(frame: frameRect)

        wantsLayer = true

        addSubview(countLabel)
        addSubview(doneButton)
        addSubview(hintLabel)

        doneButton.target = self
        doneButton.action = #selector(doneClicked)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let badgeY = bounds.height - badgeHeight
        let badgeX: CGFloat = padding

        countLabel.sizeToFit()
        countLabel.frame.origin = CGPoint(x: badgeX + 10, y: badgeY + (badgeHeight - countLabel.frame.height) / 2)

        doneButton.sizeToFit()
        let buttonFrame = NSRect(
            x: countLabel.frame.maxX + 12,
            y: badgeY + (badgeHeight - doneButton.frame.height) / 2,
            width: doneButton.frame.width + 16,
            height: doneButton.frame.height
        )
        doneButton.frame = buttonFrame

        hintLabel.sizeToFit()
        hintLabel.frame.origin = CGPoint(x: doneButton.frame.maxX + 12, y: badgeY + (badgeHeight - hintLabel.frame.height) / 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Blue dashed border (around selection area)
        let borderRect = NSRect(
            x: padding - 2,
            y: 0,
            width: bounds.width - padding * 2 + 4,
            height: bounds.height - badgeHeight - badgeGap + padding + 2
        )

        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(3.0)
        context.setLineDash(phase: 0, lengths: [8, 4])
        context.stroke(borderRect)

        // Badge background with shadow and border
        let badgeY = bounds.height - badgeHeight
        let badgeWidth = (hintLabel.frame.maxX - padding) + 14
        let badgeBgRect = NSRect(x: padding, y: badgeY, width: badgeWidth, height: badgeHeight)
        let badgePath = NSBezierPath(roundedRect: badgeBgRect, xRadius: 8, yRadius: 8)

        // Draw shadow
        context.saveGState()
        let shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: shadowColor)

        // Fill with gradient-like dark background
        NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.18, alpha: 0.95).setFill()
        badgePath.fill()
        context.restoreGState()

        // Draw white border around badge
        NSColor.white.withAlphaComponent(0.3).setStroke()
        badgePath.lineWidth = 1.0
        badgePath.stroke()
    }

    func updateCaptureCount(_ count: Int) {
        captureCount = count
        countLabel.stringValue = "Captures: \(count)"
        countLabel.sizeToFit()
        needsLayout = true
        needsDisplay = true
    }

    func showFlash() {
        // Create flash overlay
        let flashView = NSView(frame: NSRect(
            x: padding - 2,
            y: 0,
            width: bounds.width - padding * 2 + 4,
            height: bounds.height - badgeHeight - badgeGap + padding + 2
        ))
        flashView.wantsLayer = true
        flashView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        addSubview(flashView)

        // Animate flash
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            flashView.animator().alphaValue = 0
        } completionHandler: {
            flashView.removeFromSuperview()
        }
    }

    @objc private func doneClicked() {
        onDone?()
    }
}
