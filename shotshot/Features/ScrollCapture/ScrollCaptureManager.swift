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

    init() {
        captureManager = CaptureManager()
    }

    /// Starts the scroll capture process
    /// - Returns: A Screenshot of the stitched result
    func startScrollCapture() async throws -> Screenshot {
        guard !isCapturing else {
            throw CaptureError.cancelled
        }

        isCapturing = true
        capturedImages = []

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

            // Show overlay window (use converted coordinates)
            self.overlayWindow = ScrollCaptureOverlayWindow(selectionRect: selectionInScreen)
            self.overlayWindow?.updateCaptureCount(self.capturedImages.count)

            self.overlayWindow?.onDone = { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
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

        let filter = SCContentFilter(display: display, excludingWindows: [])

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
