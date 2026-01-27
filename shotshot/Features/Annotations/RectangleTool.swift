import AppKit
import CoreGraphics
import Foundation

struct RectangleTool: AnnotationToolProtocol {
    static func draw(_ annotation: Annotation, in context: CGContext, imageSize: CGSize) {
        let start = CGPoint(
            x: annotation.startPoint.x,
            y: imageSize.height - annotation.startPoint.y
        )
        let end = CGPoint(
            x: annotation.endPoint.x,
            y: imageSize.height - annotation.endPoint.y
        )

        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        guard rect.width > 2 && rect.height > 2 else { return }

        context.saveGState()

        // Draw white outline (border)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(annotation.lineWidth + 2)
        context.setLineJoin(.round)
        context.addRect(rect)
        context.strokePath()

        // Draw colored rectangle
        context.setStrokeColor(annotation.color.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.addRect(rect)
        context.strokePath()

        context.restoreGState()
    }
}
