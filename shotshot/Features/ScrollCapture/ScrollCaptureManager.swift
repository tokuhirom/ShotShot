import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

/// Manages the scroll capture workflow
@MainActor
final class ScrollCaptureManager {
    private var captureManager: CaptureManager?
    private var scrollDetector: ScrollDetector?
    private var overlayWindow: ScrollCaptureOverlayWindow?
    private var capturedImages: [CGImage] = []
    private var isCapturing = false
    private var selection: CaptureSelection?
    private var debugDir: URL?
    private var sessionId: String = ""

    /// Check if debug mode is enabled via environment variable
    private var isDebugMode: Bool {
        ProcessInfo.processInfo.environment["SHOTSHOT_SCROLL_DEBUG"] == "1"
    }

    init() {
        captureManager = CaptureManager()
    }

    /// Creates debug directory for this session
    private func setupDebugDirectory() -> URL? {
        guard isDebugMode else { return nil }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        sessionId = "scroll_\(timestamp)"

        let tempDir = FileManager.default.temporaryDirectory
        let debugDir = tempDir.appendingPathComponent("ShotShot_Debug").appendingPathComponent(sessionId)

        do {
            try FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
            NSLog("[ScrollCaptureManager] Debug directory: %@", debugDir.path)
            return debugDir
        } catch {
            NSLog("[ScrollCaptureManager] Failed to create debug directory: %@", error.localizedDescription)
            return nil
        }
    }

    /// Saves a debug image
    private func saveDebugImage(_ image: CGImage, index: Int) {
        guard let debugDir = debugDir else { return }

        let filename = String(format: "capture_%03d.png", index)
        let fileURL = debugDir.appendingPathComponent(filename)

        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            NSLog("[ScrollCaptureManager] Failed to create PNG data for debug image")
            return
        }

        do {
            try pngData.write(to: fileURL)
            NSLog("[ScrollCaptureManager] Debug image saved: %@", fileURL.path)
        } catch {
            NSLog("[ScrollCaptureManager] Failed to save debug image: %@", error.localizedDescription)
        }
    }

    /// Starts the scroll capture process
    /// - Returns: A Screenshot of the stitched result
    func startScrollCapture() async throws -> Screenshot {
        guard !isCapturing else {
            throw CaptureError.cancelled
        }

        isCapturing = true
        capturedImages = []
        debugDir = setupDebugDirectory()

        // Select capture region
        guard let captureManager = captureManager else {
            cleanup()
            throw CaptureError.captureFailedError("CaptureManager not initialized")
        }

        NSLog("[ScrollCaptureManager] Selecting capture area...")
        let selection: CaptureSelection
        do {
            selection = try await captureManager.selectArea()
        } catch {
            cleanup()
            throw error
        }
        self.selection = selection
        NSLog("[ScrollCaptureManager] Area selected: %@", NSStringFromRect(selection.rect))

        // Capture the initial image
        let initialImage: CGImage
        do {
            initialImage = try await captureRect(selection)
        } catch {
            cleanup()
            throw error
        }
        capturedImages.append(initialImage)
        saveDebugImage(initialImage, index: 1)
        NSLog("[ScrollCaptureManager] Initial capture done")

        // Convert selection rect from top-left origin (ScreenCaptureKit)
        // to bottom-left origin (NSWindow) coordinate system
        let screen = NSScreen.screens.first { $0.displayID == selection.displayID } ?? NSScreen.main!
        let screenFrame = screen.frame
        let selectionInScreen = NSRect(
            x: screenFrame.origin.x + selection.rect.origin.x,
            y: screenFrame.origin.y + screenFrame.height - selection.rect.origin.y - selection.rect.height,
            width: selection.rect.width,
            height: selection.rect.height
        )

        // Show overlay and start scroll detection
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(throwing: CaptureError.cancelled)
                return
            }

            // Flag to ensure continuation is only resumed once
            var hasResumed = false

            // Show overlay window (use converted coordinates)
            self.overlayWindow = ScrollCaptureOverlayWindow(selectionRect: selectionInScreen)
            self.overlayWindow?.updateCaptureCount(self.capturedImages.count)

            self.overlayWindow?.onDone = { [weak self] in
                Task { @MainActor in
                    guard let self = self, !hasResumed else { return }
                    hasResumed = true
                    do {
                        let result = try await self.finishCapture(selection: selection)
                        self.cleanup()
                        continuation.resume(returning: result)
                    } catch {
                        self.cleanup()
                        continuation.resume(throwing: error)
                    }
                }
            }

            self.overlayWindow?.onCancel = { [weak self] in
                guard !hasResumed else { return }
                hasResumed = true
                self?.cleanup()
                continuation.resume(throwing: CaptureError.cancelled)
            }

            self.overlayWindow?.makeKeyAndOrderFront()
            NSApp.activate(ignoringOtherApps: true)

            // Start scroll detection
            self.scrollDetector = ScrollDetector(selection: selection)
            self.scrollDetector?.onScrollDetected = { [weak self] in
                Task { @MainActor in
                    await self?.handleScrollDetected()
                }
            }

            Task { @MainActor in
                await self.scrollDetector?.startMonitoring()
            }
        }
    }

    private func handleScrollDetected() async {
        guard let selection = selection else { return }

        do {
            let image = try await captureRect(selection)
            capturedImages.append(image)
            saveDebugImage(image, index: capturedImages.count)
            overlayWindow?.updateCaptureCount(capturedImages.count)
            overlayWindow?.showCaptureFlash()
            await scrollDetector?.updateReferenceImage()
            NSLog("[ScrollCaptureManager] Captured image %d", capturedImages.count)
        } catch {
            NSLog("[ScrollCaptureManager] Failed to capture: %@", error.localizedDescription)
        }
    }

    private func finishCapture(selection: CaptureSelection) async throws -> Screenshot {
        NSLog("[ScrollCaptureManager] Finishing capture with %d images", capturedImages.count)

        scrollDetector?.stopMonitoring()
        scrollDetector = nil

        guard !capturedImages.isEmpty else {
            throw CaptureError.captureFailedError("No images captured")
        }

        // Copy images for background processing
        let imagesToStitch = capturedImages

        // Stitch images if more than one (run on background thread)
        let finalImage: CGImage
        if imagesToStitch.count == 1 {
            finalImage = imagesToStitch[0]
        } else {
            let stitched = await Task.detached(priority: .userInitiated) {
                let stitcher = ImageStitcher()
                return stitcher.stitch(images: imagesToStitch)
            }.value

            guard let stitchedImage = stitched else {
                throw CaptureError.captureFailedError("Failed to stitch images")
            }
            finalImage = stitchedImage
        }

        // Convert to NSImage
        let nsImage = NSImage(
            cgImage: finalImage,
            size: NSSize(
                width: CGFloat(finalImage.width) / selection.scaleFactor,
                height: CGFloat(finalImage.height) / selection.scaleFactor
            )
        )

        return Screenshot(
            image: nsImage,
            displayID: selection.displayID,
            scaleFactor: selection.scaleFactor
        )
    }

    private func captureRect(_ selection: CaptureSelection) async throws -> CGImage {
        let content = try await SCShareableContent.current

        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw CaptureError.noDisplayFound
        }

        // Exclude our overlay window from capture
        var excludedWindows: [SCWindow] = []
        if let overlayWindowNumber = overlayWindow?.window.windowNumber {
            if let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(overlayWindowNumber) }) {
                excludedWindows.append(scWindow)
            }
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

        let scaleFactor = Int(selection.scaleFactor)
        let config = SCStreamConfiguration()
        config.sourceRect = selection.rect
        config.width = Int(selection.rect.width) * scaleFactor
        config.height = Int(selection.rect.height) * scaleFactor
        config.scalesToFit = false
        config.showsCursor = false
        config.captureResolution = .best

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    private func cleanup() {
        isCapturing = false
        scrollDetector?.stopMonitoring()
        scrollDetector = nil
        overlayWindow?.close()
        overlayWindow = nil
        selection = nil
        capturedImages = []
    }
}
