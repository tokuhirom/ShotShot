import AppKit
import Foundation

@MainActor
struct ClipboardService {
    static func copy(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    static func copy(_ cgImage: CGImage) {
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        copy(image)
    }

    static func pasteImage() -> NSImage? {
        let pasteboard = NSPasteboard.general

        // 画像タイプをチェック
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff,
            .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic")
        ]

        for type in imageTypes {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data) {
                return image
            }
        }

        // ファイルURLから画像を読み込む
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                if let image = NSImage(contentsOf: url) {
                    return image
                }
            }
        }

        return nil
    }
}
