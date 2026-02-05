import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

/// Detects scroll activity by periodically comparing screen captures
@MainActor
final class ScrollDetector {
    private let selection: CaptureSelection
    private var previousImage: CGImage?
    private var comparisonTimer: Timer?
    private var lastCaptureTime: Date = .distantPast
    private let cooldownInterval: TimeInterval = 0.2  // 200ms cooldown between captures
    private let comparisonInterval: TimeInterval = 0.1  // 100ms between comparisons
    private let changeThreshold: Float = 0.03  // 3% difference triggers capture

    var onScrollDetected: (() -> Void)?

    init(selection: CaptureSelection) {
        self.selection = selection
    }

    /// Starts monitoring for scroll activity
    func startMonitoring() async {
        NSLog("[ScrollDetector] Starting monitoring")

        // Capture initial image
        do {
            previousImage = try await captureCurrentState()
        } catch {
            NSLog("[ScrollDetector] Failed to capture initial state: %@", error.localizedDescription)
        }

        // Start comparison timer
        comparisonTimer = Timer.scheduledTimer(withTimeInterval: comparisonInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForChanges()
            }
        }
    }

    /// Stops monitoring for scroll activity
    func stopMonitoring() {
        NSLog("[ScrollDetector] Stopping monitoring")
        comparisonTimer?.invalidate()
        comparisonTimer = nil
        previousImage = nil
    }

    /// Updates the reference image after a capture
    func updateReferenceImage() async {
        do {
            previousImage = try await captureCurrentState()
            lastCaptureTime = Date()
        } catch {
            NSLog("[ScrollDetector] Failed to update reference image: %@", error.localizedDescription)
        }
    }

    private func checkForChanges() async {
        // Check cooldown
        guard Date().timeIntervalSince(lastCaptureTime) >= cooldownInterval else {
            return
        }

        guard let previousImage = previousImage else {
            do {
                self.previousImage = try await captureCurrentState()
            } catch {
                NSLog("[ScrollDetector] Failed to capture state: %@", error.localizedDescription)
            }
            return
        }

        do {
            let currentImage = try await captureCurrentState()
            let difference = calculateDifference(between: previousImage, and: currentImage)

            if difference > changeThreshold {
                NSLog("[ScrollDetector] Change detected: %.2f%%", difference * 100)
                self.previousImage = currentImage
                lastCaptureTime = Date()
                onScrollDetected?()
            }
        } catch {
            NSLog("[ScrollDetector] Failed to capture for comparison: %@", error.localizedDescription)
        }
    }

    private func captureCurrentState() async throws -> CGImage {
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

    private func calculateDifference(between image1: CGImage, and image2: CGImage) -> Float {
        guard image1.width == image2.width && image1.height == image2.height else {
            return 1.0  // Completely different if sizes don't match
        }

        guard let data1 = getPixelData(from: image1),
              let data2 = getPixelData(from: image2) else {
            return 1.0
        }

        let totalPixels = image1.width * image1.height
        var differentPixels = 0

        data1.withUnsafeBytes { buffer1 in
            data2.withUnsafeBytes { buffer2 in
                guard let ptr1 = buffer1.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let ptr2 = buffer2.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }

                // Sample every 4th pixel for performance
                for i in stride(from: 0, to: totalPixels, by: 4) {
                    let offset = i * 4

                    let rDiff = abs(Int(ptr1[offset + 1]) - Int(ptr2[offset + 1]))
                    let gDiff = abs(Int(ptr1[offset + 2]) - Int(ptr2[offset + 2]))
                    let bDiff = abs(Int(ptr1[offset + 3]) - Int(ptr2[offset + 3]))

                    // Consider pixels different if any channel differs by more than 10
                    if rDiff > 10 || gDiff > 10 || bDiff > 10 {
                        differentPixels += 1
                    }
                }
            }
        }

        // Adjust for sampling (we only checked every 4th pixel)
        return Float(differentPixels * 4) / Float(totalPixels)
    }

    private func getPixelData(from image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height

        var pixelData = Data(count: totalBytes)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        let success = pixelData.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return success ? pixelData : nil
    }
}
