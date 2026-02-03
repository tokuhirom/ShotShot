import AppKit
import Foundation

@MainActor
final class RecordingIndicatorWindow {
    let window: NSWindow
    private let indicatorView: RecordingIndicatorView
    private var elapsedSeconds: Int = 0
    private var timer: Timer?
    private var keyMonitor: Any?
    var onStop: (() -> Void)?

    init(selectionRect: CGRect) {
        let padding: CGFloat = 4
        let badgeHeight: CGFloat = 32
        let badgeGap: CGFloat = 8
        let minBadgeWidth: CGFloat = 150  // Minimum width for badge (REC + time + stop button)

        // Ensure window is wide enough for the badge
        let frameWidth = max(selectionRect.width + padding * 2, minBadgeWidth)
        let frameRect = NSRect(
            x: selectionRect.origin.x - padding,
            y: selectionRect.origin.y - padding - badgeHeight - badgeGap,
            width: frameWidth,
            height: selectionRect.height + padding * 2 + badgeHeight + badgeGap
        )

        indicatorView = RecordingIndicatorView(
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
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.contentView = indicatorView

        indicatorView.onStop = { [weak self] in
            self?.onStop?()
        }

        // Stop with Escape key
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.onStop?()
                return nil
            }
            return event
        }

        startTimer()
    }

    func makeKeyAndOrderFront() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        stopTimer()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        window.orderOut(nil)
        window.close()
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        elapsedSeconds = 0
        indicatorView.updateTime(formatTime(0))
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.elapsedSeconds += 1
                self.indicatorView.updateTime(self.formatTime(self.elapsedSeconds))
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

@MainActor
final class RecordingIndicatorView: NSView {
    private let selectionRect: CGRect
    private let badgeHeight: CGFloat
    private let badgeGap: CGFloat
    private let padding: CGFloat
    private var timeString: String = "0:00"
    private let stopButton: NSButton
    private let timeLabel: NSTextField
    private let recLabel: NSTextField
    var onStop: (() -> Void)?

    init(selectionRect: CGRect, frameRect: NSRect, badgeHeight: CGFloat, badgeGap: CGFloat, padding: CGFloat) {
        self.selectionRect = selectionRect
        self.badgeHeight = badgeHeight
        self.badgeGap = badgeGap
        self.padding = padding

        // REC label
        recLabel = NSTextField(labelWithString: "● REC")
        recLabel.font = NSFont.boldSystemFont(ofSize: 13)
        recLabel.textColor = .white
        recLabel.backgroundColor = .clear
        recLabel.isBezeled = false
        recLabel.isEditable = false

        // Time label
        timeLabel = NSTextField(labelWithString: "0:00")
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        timeLabel.textColor = .white
        timeLabel.backgroundColor = .clear
        timeLabel.isBezeled = false
        timeLabel.isEditable = false

        // Stop button
        stopButton = NSButton(frame: .zero)
        stopButton.bezelStyle = .circular
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "録画を停止")
        stopButton.imagePosition = .imageOnly
        stopButton.isBordered = false
        stopButton.contentTintColor = .white

        super.init(frame: frameRect)

        addSubview(recLabel)
        addSubview(timeLabel)
        addSubview(stopButton)

        stopButton.target = self
        stopButton.action = #selector(stopClicked)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let badgeY = bounds.height - badgeHeight
        let badgeX: CGFloat = padding

        recLabel.sizeToFit()
        recLabel.frame.origin = CGPoint(x: badgeX + 8, y: badgeY + (badgeHeight - recLabel.frame.height) / 2)

        timeLabel.sizeToFit()
        timeLabel.frame.origin = CGPoint(x: recLabel.frame.maxX + 8, y: badgeY + (badgeHeight - timeLabel.frame.height) / 2)

        let btnSize: CGFloat = 22
        stopButton.frame = NSRect(
            x: timeLabel.frame.maxX + 10,
            y: badgeY + (badgeHeight - btnSize) / 2,
            width: btnSize,
            height: btnSize
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Red border (around selection area)
        let borderRect = NSRect(
            x: padding - 2,
            y: 0,
            width: bounds.width - padding * 2 + 4,
            height: bounds.height - badgeHeight - badgeGap + padding + 2
        )
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(3.0)
        context.stroke(borderRect)

        // Badge background (red rounded rectangle)
        let badgeY = bounds.height - badgeHeight
        let badgeWidth = (stopButton.frame.maxX - padding) + 8
        let badgeBgRect = NSRect(x: padding, y: badgeY, width: badgeWidth, height: badgeHeight)
        let badgePath = NSBezierPath(roundedRect: badgeBgRect, xRadius: 6, yRadius: 6)
        NSColor.systemRed.setFill()
        badgePath.fill()
    }

    func updateTime(_ time: String) {
        timeString = time
        timeLabel.stringValue = time
        timeLabel.sizeToFit()
        needsLayout = true
    }

    @objc private func stopClicked() {
        onStop?()
    }
}
