import AppKit
import Foundation

struct Screenshot: Sendable {
    let image: NSImage
    let capturedAt: Date
    let displayID: CGDirectDisplayID?

    init(image: NSImage, displayID: CGDirectDisplayID? = nil) {
        self.image = image
        self.capturedAt = Date()
        self.displayID = displayID
    }

    var cgImage: CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
