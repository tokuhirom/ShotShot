import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplayFound
    case captureFailedError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return NSLocalizedString("capture.error.permission_denied", comment: "")
        case .noDisplayFound:
            return NSLocalizedString("capture.error.no_display", comment: "")
        case .captureFailedError(let message):
            let format = NSLocalizedString("capture.error.capture_failed_format", comment: "")
            return String.localizedStringWithFormat(format, message)
        case .cancelled:
            return NSLocalizedString("capture.error.cancelled", comment: "")
        }
    }
}

struct CaptureSelection: Sendable {
    let rect: CGRect
    let displayID: CGDirectDisplayID
    let scaleFactor: CGFloat
}

@MainActor
final class CaptureManager {
    private var overlayWindows: [NSWindow] = []
    private var hasResumed = false
    private var isCapturing = false
    private var countdownCancelled = false

    func selectArea() async throws -> CaptureSelection {
        guard !isCapturing else {
            NSLog("[CaptureManager] Already capturing, ignoring request")
            throw CaptureError.cancelled
        }
        isCapturing = true
        defer {
            isCapturing = false
            closeOverlayWindows()
        }

        let hasPermission = await checkPermission()
        guard hasPermission else {
            throw CaptureError.permissionDenied
        }

        hasResumed = false
        let selection = try await showSelectionOverlay()
        return selection
    }

    func captureInteractively() async throws -> Screenshot {
        // Prevent duplicate execution
        guard !isCapturing else {
            NSLog("[CaptureManager] Already capturing, ignoring request")
            throw CaptureError.cancelled
        }
        isCapturing = true
        defer {
            isCapturing = false
            closeOverlayWindows()
        }

        print("[CaptureManager] Checking permission...")
        let hasPermission = await checkPermission()
        guard hasPermission else {
            print("[CaptureManager] Permission denied")
            throw CaptureError.permissionDenied
        }
        print("[CaptureManager] Permission granted, showing overlay...")

        hasResumed = false
        let selection = try await showSelectionOverlay()
        print("[CaptureManager] Selection completed: \(selection)")

        print("[CaptureManager] Capturing rect...")
        let screenshot = try await captureRect(selection)
        print("[CaptureManager] Capture done, image size: \(screenshot.image.size), scale: \(screenshot.scaleFactor)")

        return screenshot
    }

    func captureWithTimer(countdownSeconds: Int = 3) async throws -> Screenshot {
        guard !isCapturing else {
            NSLog("[CaptureManager] Already capturing, ignoring request")
            throw CaptureError.cancelled
        }
        isCapturing = true
        countdownCancelled = false
        defer {
            isCapturing = false
            closeOverlayWindows()
        }

        print("[CaptureManager] Timer capture: checking permission...")
        let hasPermission = await checkPermission()
        guard hasPermission else {
            throw CaptureError.permissionDenied
        }

        hasResumed = false
        let selection = try await showSelectionOverlay()
        print("[CaptureManager] Timer capture: selection completed: \(selection)")

        // Switch to countdown mode
        transitionToCountdownMode()

        // Run countdown
        try await runCountdown(seconds: countdownSeconds)

        // Close the overlay
        closeOverlayWindows()

        // Wait for screen redraw
        try await Task.sleep(nanoseconds: 150_000_000)

        print("[CaptureManager] Timer capture: capturing rect...")
        let screenshot = try await captureRect(selection)
        print("[CaptureManager] Timer capture done, image size: \(screenshot.image.size)")

        return screenshot
    }

    private func transitionToCountdownMode() {
        for window in overlayWindows {
            if let overlay = window as? SelectionOverlayWindow {
                overlay.onCountdownCancel = { [weak self] in
                    self?.countdownCancelled = true
                }
                overlay.enterCountdownMode()
            }
        }
    }

    private func runCountdown(seconds: Int) async throws {
        for i in stride(from: seconds, through: 1, by: -1) {
            guard !countdownCancelled else {
                throw CaptureError.cancelled
            }

            // Update countdown number
            for window in overlayWindows {
                if let overlay = window as? SelectionOverlayWindow {
                    overlay.updateCountdown(i)
                }
            }

            // Wait 1 second in 100ms steps and check for cancel
            for _ in 0..<10 {
                guard !countdownCancelled else {
                    throw CaptureError.cancelled
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        // Final cancel check
        guard !countdownCancelled else {
            throw CaptureError.cancelled
        }
    }

    nonisolated private func checkPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.current
            return true
        } catch {
            return false
        }
    }

    private func showSelectionOverlay() async throws -> CaptureSelection {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CaptureSelection, Error>) in
            let screens = NSScreen.screens
            var windows: [NSWindow] = []

            for screen in screens {
                let window = SelectionOverlayWindow(
                    screen: screen,
                    onSelection: { [weak self] rect in
                        NSLog("[CaptureManager] onSelection called, self=%@, hasResumed=%d", self == nil ? "nil" : "exists", (self?.hasResumed ?? true) ? 1 : 0)
                        guard let self = self else {
                            NSLog("[CaptureManager] ERROR: self is nil!")
                            return
                        }
                        guard !self.hasResumed else {
                            NSLog("[CaptureManager] ERROR: already resumed!")
                            return
                        }
                        self.hasResumed = true
                        let displayID = screen.displayID ?? CGMainDisplayID()
                        let scaleFactor = screen.backingScaleFactor
                        NSLog("[CaptureManager] Resuming with selection, scaleFactor: %f", scaleFactor)
                        let selection = CaptureSelection(rect: rect, displayID: displayID, scaleFactor: scaleFactor)
                        continuation.resume(returning: selection)
                    },
                    onCancel: { [weak self] in
                        NSLog("[CaptureManager] onCancel called, self=%@, hasResumed=%d", self == nil ? "nil" : "exists", (self?.hasResumed ?? true) ? 1 : 0)
                        guard let self = self else {
                            NSLog("[CaptureManager] ERROR: self is nil!")
                            return
                        }
                        guard !self.hasResumed else {
                            NSLog("[CaptureManager] ERROR: already resumed!")
                            return
                        }
                        self.hasResumed = true
                        NSLog("[CaptureManager] Resuming with cancel...")
                        continuation.resume(throwing: CaptureError.cancelled)
                    }
                )
                window.makeKeyAndOrderFront(nil)
                windows.append(window)
            }

            self.overlayWindows = windows

            // Activate the app to receive mouse events
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func closeOverlayWindows() {
        NSLog("[CaptureManager] Closing %d overlay windows...", overlayWindows.count)
        let windows = overlayWindows
        overlayWindows = []
        for window in windows {
            if let overlay = window as? SelectionOverlayWindow {
                overlay.cleanup()
            }
            window.orderOut(nil)
            window.close()
        }
        NSLog("[CaptureManager] All overlay windows closed")
    }

    nonisolated private func captureRect(_ selection: CaptureSelection) async throws -> Screenshot {
        print("[CaptureManager] captureRect called with displayID: \(selection.displayID), scale: \(selection.scaleFactor)")
        let content = try await SCShareableContent.current

        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            print("[CaptureManager] Display not found!")
            throw CaptureError.noDisplayFound
        }
        print("[CaptureManager] Found display: \(display.displayID)")

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let scaleFactor = Int(selection.scaleFactor)
        let config = SCStreamConfiguration()
        config.sourceRect = selection.rect
        config.width = Int(selection.rect.width) * scaleFactor
        config.height = Int(selection.rect.height) * scaleFactor
        config.scalesToFit = false
        config.showsCursor = false
        config.captureResolution = .best

        print("[CaptureManager] Calling SCScreenshotManager.captureImage...")
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        print("[CaptureManager] Got CGImage: \(image.width)x\(image.height)")

        let nsImage = NSImage(cgImage: image, size: NSSize(width: selection.rect.width, height: selection.rect.height))
        return Screenshot(image: nsImage, displayID: selection.displayID, scaleFactor: selection.scaleFactor)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
