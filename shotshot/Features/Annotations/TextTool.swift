import AppKit
import CoreGraphics
import CoreText
import Foundation

struct TextTool: AnnotationToolProtocol {
    static func draw(_ annotation: Annotation, in context: CGContext, imageSize: CGSize, scaleFactor: CGFloat = 1.0) {
        guard let text = annotation.text, !text.isEmpty else { return }

        let scale = scaleFactor
        let point = CGPoint(
            x: annotation.endPoint.x * scale,
            y: imageSize.height - annotation.endPoint.y * scale
        )

        context.saveGState()

        let fontSize = (annotation.fontSize ?? 32.0) * scale
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let strokeWidth = fontSize * 0.08

        // Draw a white outline (offset in multiple directions)
        let strokeAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let strokeString = NSAttributedString(string: text, attributes: strokeAttributes)
        let strokeLine = CTLineCreateWithAttributedString(strokeString)

        let offsets: [(CGFloat, CGFloat)] = [
            (-strokeWidth, -strokeWidth), (0, -strokeWidth), (strokeWidth, -strokeWidth),
            (-strokeWidth, 0), (strokeWidth, 0),
            (-strokeWidth, strokeWidth), (0, strokeWidth), (strokeWidth, strokeWidth)
        ]

        for offset in offsets {
            context.textPosition = CGPoint(x: point.x + offset.0, y: point.y + offset.1)
            CTLineDraw(strokeLine, context)
        }

        // Draw main text
        let mainAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.color
        ]
        let mainString = NSAttributedString(string: text, attributes: mainAttributes)
        let mainLine = CTLineCreateWithAttributedString(mainString)

        context.textPosition = point
        CTLineDraw(mainLine, context)

        context.restoreGState()
    }
}
