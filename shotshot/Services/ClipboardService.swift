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
}
