import AppKit
import CoreGraphics
import Foundation

struct ArrowTool: AnnotationToolProtocol {
    static func draw(_ annotation: Annotation, in context: CGContext, imageSize: CGSize) {
        let start = CGPoint(
            x: annotation.startPoint.x,
            y: imageSize.height - annotation.startPoint.y
        )
        let end = CGPoint(
            x: annotation.endPoint.x,
            y: imageSize.height - annotation.endPoint.y
        )

        context.saveGState()

        context.setStrokeColor(annotation.color.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = annotation.lineWidth * 5

        let arrowPoint1 = CGPoint(
            x: end.x - arrowLength * cos(angle - .pi / 6),
            y: end.y - arrowLength * sin(angle - .pi / 6)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - arrowLength * cos(angle + .pi / 6),
            y: end.y - arrowLength * sin(angle + .pi / 6)
        )

        context.setFillColor(annotation.color.cgColor)
        context.move(to: end)
        context.addLine(to: arrowPoint1)
        context.addLine(to: arrowPoint2)
        context.closePath()
        context.fillPath()

        context.restoreGState()
    }
}
