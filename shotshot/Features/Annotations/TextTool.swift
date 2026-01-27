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

        let fontSize = (annotation.fontSize ?? 16.0) * scale
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.color
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)

        context.textPosition = point
        CTLineDraw(line, context)

        context.restoreGState()
    }
}
