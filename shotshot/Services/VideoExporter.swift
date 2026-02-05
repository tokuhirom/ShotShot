import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum VideoFormat: String, CaseIterable {
    case mp4 = "MP4"
    case gif = "GIF"

    var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .gif: return "gif"
        }
    }

    var utType: UTType {
        switch self {
        case .mp4: return .mpeg4Movie
        case .gif: return .gif
        }
    }
}

@MainActor
struct VideoExporter {
    static func showSavePanel(tempMP4URL: URL) async {
        let panel = NSSavePanel()
        panel.title = NSLocalizedString("export.video.save_title", comment: "")
        panel.nameFieldStringValue = generateFilename()
        panel.canCreateDirectories = true

        // Accessory view for format selection
        let formatPicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 28), pullsDown: false)
        for format in VideoFormat.allCases {
            formatPicker.addItem(withTitle: format.rawValue)
        }
        formatPicker.selectItem(at: 0) // Default to MP4

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 40))
        let label = NSTextField(labelWithString: NSLocalizedString("export.video.format_label", comment: ""))
        label.frame = NSRect(x: 0, y: 8, width: 80, height: 22)
        formatPicker.frame = NSRect(x: 85, y: 6, width: 150, height: 28)
        accessoryView.addSubview(label)
        accessoryView.addSubview(formatPicker)
        panel.accessoryView = accessoryView

        // Update file types
        panel.allowedContentTypes = [VideoFormat.mp4.utType]
        formatPicker.target = FormatPickerTarget.shared
        formatPicker.action = #selector(FormatPickerTarget.formatChanged(_:))
        FormatPickerTarget.shared.panel = panel

        // Show as independent dialog to avoid orphan window when no parent window exists
        let response = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response)
            }
        }

        guard response == .OK, let url = panel.url else {
            // Remove the temp file on cancel
            try? FileManager.default.removeItem(at: tempMP4URL)
            return
        }

        let selectedIndex = formatPicker.indexOfSelectedItem
        let format = VideoFormat.allCases[selectedIndex]

        do {
            switch format {
            case .mp4:
                // Overwrite existing file
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.moveItem(at: tempMP4URL, to: url)
                NSLog("[VideoExporter] MP4 saved to: %@", url.path)

            case .gif:
                let gifURL = url.deletingPathExtension().appendingPathExtension("gif")
                try await convertMP4ToGIF(source: tempMP4URL, destination: gifURL, fps: 10, maxWidth: 640)
                // Remove temp MP4
                try? FileManager.default.removeItem(at: tempMP4URL)
                NSLog("[VideoExporter] GIF saved to: %@", gifURL.path)
            }
        } catch {
            NSLog("[VideoExporter] Save error: %@", error.localizedDescription)
            // Remove temp file
            try? FileManager.default.removeItem(at: tempMP4URL)

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("export.video.save_failed", comment: "")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: NSLocalizedString("common.ok", comment: ""))
            alert.runModal()
        }
    }

    nonisolated static func convertMP4ToGIF(source: URL, destination: URL, fps: Int, maxWidth: CGFloat) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else { return }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: CMTimeScale(fps * 2))
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: CMTimeScale(fps * 2))

        // Resize to max width
        generator.maximumSize = CGSize(width: maxWidth, height: 0)

        let frameCount = Int(durationSeconds * Double(fps))
        guard frameCount > 0 else { return }

        var times: [NSValue] = []
        for i in 0..<frameCount {
            let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            times.append(NSValue(time: time))
        }

        // Create GIF
        guard let destination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw VideoExportError.gifCreationFailed
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0 // Infinite loop
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        let frameDelay = 1.0 / Double(fps)
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]

        // Generate and add frames
        for time in times {
            let cmTime = time.timeValue
            do {
                let (image, _) = try await generator.image(at: cmTime)
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            } catch {
                NSLog("[VideoExporter] Skipping frame at %@: %@", String(describing: cmTime), error.localizedDescription)
            }
        }

        if !CGImageDestinationFinalize(destination) {
            throw VideoExportError.gifFinalizationFailed
        }
    }

    static func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "ShotShot_\(formatter.string(from: Date()))"
    }
}

enum VideoExportError: LocalizedError {
    case gifCreationFailed
    case gifFinalizationFailed

    var errorDescription: String? {
        switch self {
        case .gifCreationFailed:
            return NSLocalizedString("export.video.gif_creation_failed", comment: "")
        case .gifFinalizationFailed:
            return NSLocalizedString("export.video.gif_write_failed", comment: "")
        }
    }
}

// Helper for switching NSSavePanel format
@MainActor
final class FormatPickerTarget: NSObject {
    static let shared = FormatPickerTarget()
    weak var panel: NSSavePanel?

    @objc func formatChanged(_ sender: NSPopUpButton) {
        let format = VideoFormat.allCases[sender.indexOfSelectedItem]
        panel?.allowedContentTypes = [format.utType]
    }
}
