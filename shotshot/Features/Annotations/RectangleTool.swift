import AppKit
import CoreGraphics
import Foundation

struct RectangleTool: AnnotationToolProtocol {
    static func draw(_ annotation: Annotation, in context: CGContext, imageSize: CGSize, scaleFactor: CGFloat = 1.0) {
        let scale = scaleFactor
        let start = CGPoint(
            x: annotation.startPoint.x * scale,
            y: imageSize.height - annotation.startPoint.y * scale
        )
        let end = CGPoint(
            x: annotation.endPoint.x * scale,
            y: imageSize.height - annotation.endPoint.y * scale
        )
        let lineWidth = annotation.lineWidth * scale

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
        context.setLineWidth(lineWidth + 4 * scale)
        context.setLineJoin(.round)
        context.addRect(rect)
        context.strokePath()

        // Draw colored rectangle
        context.setStrokeColor(annotation.color.cgColor)
        context.setLineWidth(lineWidth)
        context.addRect(rect)
        context.strokePath()

        context.restoreGState()
    }
}
