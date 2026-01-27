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

        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = hypot(end.x - start.x, end.y - start.y)

        guard length > 5 else { return }

        // Arrow dimensions
        let baseWidth = annotation.lineWidth * 0.15
        let headWidth = annotation.lineWidth * 3
        let headLength = annotation.lineWidth * 6

        // Calculate perpendicular direction
        let perpAngle = angle + .pi / 2

        // Shaft tapers from baseWidth at start to headWidth at head base
        let shaftLength = max(0, length - headLength)

        // Points for the tapered shaft
        let startLeft = CGPoint(
            x: start.x + baseWidth * cos(perpAngle),
            y: start.y + baseWidth * sin(perpAngle)
        )
        let startRight = CGPoint(
            x: start.x - baseWidth * cos(perpAngle),
            y: start.y - baseWidth * sin(perpAngle)
        )

        // Point where shaft meets head
        let shaftEnd = CGPoint(
            x: start.x + shaftLength * cos(angle),
            y: start.y + shaftLength * sin(angle)
        )
        let shaftEndLeft = CGPoint(
            x: shaftEnd.x + headWidth * 0.5 * cos(perpAngle),
            y: shaftEnd.y + headWidth * 0.5 * sin(perpAngle)
        )
        let shaftEndRight = CGPoint(
            x: shaftEnd.x - headWidth * 0.5 * cos(perpAngle),
            y: shaftEnd.y - headWidth * 0.5 * sin(perpAngle)
        )

        // Arrow head points
        let headLeft = CGPoint(
            x: shaftEnd.x + headWidth * cos(perpAngle),
            y: shaftEnd.y + headWidth * sin(perpAngle)
        )
        let headRight = CGPoint(
            x: shaftEnd.x - headWidth * cos(perpAngle),
            y: shaftEnd.y - headWidth * sin(perpAngle)
        )

        context.saveGState()

        // Build arrow path
        let arrowPath = CGMutablePath()
        arrowPath.move(to: startLeft)
        arrowPath.addLine(to: shaftEndLeft)
        arrowPath.addLine(to: headLeft)
        arrowPath.addLine(to: end)
        arrowPath.addLine(to: headRight)
        arrowPath.addLine(to: shaftEndRight)
        arrowPath.addLine(to: startRight)
        arrowPath.closeSubpath()

        // Draw outline (border)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(annotation.lineWidth * 0.4)
        context.setLineJoin(.round)
        context.addPath(arrowPath)
        context.strokePath()

        // Fill arrow
        context.setFillColor(annotation.color.cgColor)
        context.addPath(arrowPath)
        context.fillPath()

        context.restoreGState()
    }
}
