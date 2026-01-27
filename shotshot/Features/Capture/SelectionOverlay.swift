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
    private var isCleaned = false

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
        self.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = SelectionOverlayView(frame: screen.frame)
        self.overlayView = view
        self.contentView = view

        // ウィンドウ一覧を取得
        loadWindowList()

        // Escapeキー用のローカルイベントモニター
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.handleCancel()
                return nil
            }
            return event
        }

        // グローバルイベントモニター（アプリがアクティブでないときも検出）
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.handleCancel()
            }
        }

        // キーウィンドウでなくなったときに再アクティブ化
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, !self.isCleaned, self.isVisible else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isCleaned else { return }
                self.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        NSCursor.crosshair.set()
    }

    private func handleCancel() {
        guard !isCleaned, let cancel = onCancel else { return }
        cancel()
    }

    private func handleSelection(_ rect: CGRect) {
        guard !isCleaned, let selection = onSelection else { return }
        selection(rect)
    }

    func cleanup() {
        isCleaned = true
        onSelection = nil
        onCancel = nil
        NotificationCenter.default.removeObserver(self)
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func loadWindowList() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        // 全画面のサイズを取得（これより大きいウィンドウは除外）
        let mainScreenFrame = NSScreen.main?.frame ?? screenFrame

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

            // オーバーレイウィンドウ自身は除外
            if windowID == CGWindowID(windowNumber) {
                return nil
            }

            // ウィンドウレイヤーをチェック（通常のウィンドウは0）
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer < 0 || layer > 100 {
                return nil
            }

            let frame = CGRect(x: x, y: y, width: width, height: height)

            // 画面全体とほぼ同じサイズのウィンドウは除外（デスクトップ、Dockなど）
            if width >= mainScreenFrame.width * 0.95 && height >= mainScreenFrame.height * 0.9 {
                return nil
            }

            let name = info[kCGWindowName as String] as? String
            let ownerName = info[kCGWindowOwnerName as String] as? String

            // Dock, WindowServer, Finder のデスクトップは除外
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
        // スクリーン座標系でウィンドウを検索（上が0）
        for window in windowsUnderCursor {
            if window.frame.contains(screenPoint) {
                return window
            }
        }
        return nil
    }

    private func convertToScreenCoordinates(_ windowPoint: CGPoint) -> CGPoint {
        // ウィンドウ座標（左下原点）をスクリーン座標（左上原点）に変換
        let screenY = screenFrame.height - windowPoint.y + screenFrame.origin.y
        let screenX = windowPoint.x + screenFrame.origin.x
        return CGPoint(x: screenX, y: screenY)
    }

    private func convertWindowFrameToLocal(_ windowFrame: CGRect) -> CGRect {
        // CGWindowの座標系（スクリーン左上原点）をNSView座標系（左下原点）に変換
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
        guard !isDragging, !isCleaned else { return }

        let windowPoint = event.locationInWindow
        let screenPoint = convertToScreenCoordinates(windowPoint)

        if let window = findWindowAt(screenPoint: screenPoint) {
            let localRect = convertWindowFrameToLocal(window.frame)
            highlightedWindowRect = localRect
            overlayView?.highlightRect = localRect
        } else {
            highlightedWindowRect = nil
            overlayView?.highlightRect = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isCleaned else { return }
        NSLog("[SelectionOverlay] mouseDown at %@", "\(event.locationInWindow)")
        let point = event.locationInWindow
        startPoint = point
        currentRect = CGRect(origin: point, size: .zero)
        isDragging = false
        overlayView?.selectionRect = currentRect
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isCleaned else { return }
        guard let start = startPoint else { return }
        let current = event.locationInWindow

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)

        // ドラッグ開始とみなす閾値
        if width > 5 || height > 5 {
            isDragging = true
            overlayView?.highlightRect = nil
        }

        currentRect = CGRect(x: x, y: y, width: width, height: height)
        overlayView?.selectionRect = currentRect
    }

    override func mouseUp(with event: NSEvent) {
        guard !isCleaned else { return }
        NSLog("[SelectionOverlay] mouseUp - currentRect: %@, isDragging: %d", "\(currentRect)", isDragging ? 1 : 0)

        // ドラッグで選択した場合
        if isDragging && currentRect.width > 5 && currentRect.height > 5 {
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

        // クリックでウィンドウを選択した場合
        if let windowRect = highlightedWindowRect {
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

        // 何も選択されていない場合はリセット
        NSLog("[SelectionOverlay] No selection, resetting")
        startPoint = nil
        currentRect = .zero
        isDragging = false
        overlayView?.selectionRect = .zero
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        // ウィンドウハイライト表示
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

        // ドラッグ選択表示
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
