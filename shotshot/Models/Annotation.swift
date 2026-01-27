import AppKit
import Foundation

enum AnnotationType: Sendable {
    case arrow
    case text
    case mosaic
}

struct Annotation: Identifiable, Sendable {
    let id: UUID
    let type: AnnotationType
    var startPoint: CGPoint
    var endPoint: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
    var text: String?
    var fontSize: CGFloat?

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        startPoint: CGPoint,
        endPoint: CGPoint,
        color: NSColor = .red,
        lineWidth: CGFloat = 3.0,
        text: String? = nil,
        fontSize: CGFloat? = nil
    ) {
        self.id = id
        self.type = type
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.fontSize = fontSize
    }
}
