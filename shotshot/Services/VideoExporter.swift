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
        panel.title = "録画を保存"
        panel.nameFieldStringValue = generateFilename()
        panel.canCreateDirectories = true

        // フォーマット選択用のアクセサリビュー
        let formatPicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 28), pullsDown: false)
        for format in VideoFormat.allCases {
            formatPicker.addItem(withTitle: format.rawValue)
        }
        formatPicker.selectItem(at: 0) // MP4 をデフォルトに

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 40))
        let label = NSTextField(labelWithString: "フォーマット:")
        label.frame = NSRect(x: 0, y: 8, width: 80, height: 22)
        formatPicker.frame = NSRect(x: 85, y: 6, width: 150, height: 28)
        accessoryView.addSubview(label)
        accessoryView.addSubview(formatPicker)
        panel.accessoryView = accessoryView

        // ファイルタイプの更新
        panel.allowedContentTypes = [VideoFormat.mp4.utType]
        formatPicker.target = FormatPickerTarget.shared
        formatPicker.action = #selector(FormatPickerTarget.formatChanged(_:))
        FormatPickerTarget.shared.panel = panel

        // シートではなく独立したダイアログとして表示（親ウィンドウがない場合の問題を回避）
        let response = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response)
            }
        }

        guard response == .OK, let url = panel.url else {
            // キャンセル時は一時ファイル削除
            try? FileManager.default.removeItem(at: tempMP4URL)
            return
        }

        let selectedIndex = formatPicker.indexOfSelectedItem
        let format = VideoFormat.allCases[selectedIndex]

        do {
            switch format {
            case .mp4:
                // 既存ファイルを上書き
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.moveItem(at: tempMP4URL, to: url)
                NSLog("[VideoExporter] MP4 saved to: %@", url.path)

            case .gif:
                let gifURL = url.deletingPathExtension().appendingPathExtension("gif")
                try await convertMP4ToGIF(source: tempMP4URL, destination: gifURL, fps: 10, maxWidth: 640)
                // 一時MP4を削除
                try? FileManager.default.removeItem(at: tempMP4URL)
                NSLog("[VideoExporter] GIF saved to: %@", gifURL.path)
            }
        } catch {
            NSLog("[VideoExporter] Save error: %@", error.localizedDescription)
            // 一時ファイル削除
            try? FileManager.default.removeItem(at: tempMP4URL)

            let alert = NSAlert()
            alert.messageText = "保存に失敗しました"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
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

        // 最大幅でリサイズ
        generator.maximumSize = CGSize(width: maxWidth, height: 0)

        let frameCount = Int(durationSeconds * Double(fps))
        guard frameCount > 0 else { return }

        var times: [NSValue] = []
        for i in 0..<frameCount {
            let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            times.append(NSValue(time: time))
        }

        // GIF 作成
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
                kCGImagePropertyGIFLoopCount as String: 0 // 無限ループ
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        let frameDelay = 1.0 / Double(fps)
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]

        // フレームを生成して追加
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
            return "GIFファイルの作成に失敗しました"
        case .gifFinalizationFailed:
            return "GIFファイルの書き出しに失敗しました"
        }
    }
}

// NSSavePanel のフォーマット切り替え用ヘルパー
@MainActor
final class FormatPickerTarget: NSObject {
    static let shared = FormatPickerTarget()
    weak var panel: NSSavePanel?

    @objc func formatChanged(_ sender: NSPopUpButton) {
        let format = VideoFormat.allCases[sender.indexOfSelectedItem]
        panel?.allowedContentTypes = [format.utType]
    }
}
