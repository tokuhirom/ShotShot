import AppKit
import Foundation

struct Screenshot: Sendable {
    let image: NSImage
    let capturedAt: Date
    let displayID: CGDirectDisplayID?
    let scaleFactor: CGFloat

    init(image: NSImage, displayID: CGDirectDisplayID? = nil, scaleFactor: CGFloat = 1.0) {
        self.image = image
        self.capturedAt = Date()
        self.displayID = displayID
        self.scaleFactor = scaleFactor
    }

    var cgImage: CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    var isRetina: Bool {
        scaleFactor > 1.0
    }
}
