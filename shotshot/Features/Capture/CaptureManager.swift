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
            return "画面収録の許可が必要です"
        case .noDisplayFound:
            return "ディスプレイが見つかりません"
        case .captureFailedError(let message):
            return "キャプチャに失敗しました: \(message)"
        case .cancelled:
            return "キャンセルされました"
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

    func captureInteractively() async throws -> Screenshot {
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

        closeOverlayWindows()

        print("[CaptureManager] Capturing rect...")
        let screenshot = try await captureRect(selection)
        print("[CaptureManager] Capture done, image size: \(screenshot.image.size), scale: \(screenshot.scaleFactor)")

        return screenshot
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
                        guard let self = self, !self.hasResumed else { return }
                        self.hasResumed = true
                        let displayID = screen.displayID ?? CGMainDisplayID()
                        let scaleFactor = screen.backingScaleFactor
                        print("[CaptureManager] Resuming with selection, scaleFactor: \(scaleFactor)")
                        let selection = CaptureSelection(rect: rect, displayID: displayID, scaleFactor: scaleFactor)
                        continuation.resume(returning: selection)
                    },
                    onCancel: { [weak self] in
                        guard let self = self, !self.hasResumed else { return }
                        self.hasResumed = true
                        print("[CaptureManager] Resuming with cancel...")
                        continuation.resume(throwing: CaptureError.cancelled)
                    }
                )
                window.makeKeyAndOrderFront(nil)
                windows.append(window)
            }

            self.overlayWindows = windows

            // アプリをアクティブにしてマウスイベントを受け取れるようにする
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func closeOverlayWindows() {
        print("[CaptureManager] Closing \(overlayWindows.count) overlay windows...")
        let windows = overlayWindows
        overlayWindows = []
        for window in windows {
            window.orderOut(nil)
        }
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
