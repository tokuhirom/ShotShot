import AppKit
import Foundation

enum AnnotationType: Sendable {
    case arrow
    case rectangle
    case text
    case mosaic
}

enum MosaicType: String, CaseIterable, Sendable {
    case pixelateFine = "pixelate_fine"
    case pixelateCoarse = "pixelate_coarse"
    case blur = "blur"

    var displayName: String {
        switch self {
        case .pixelateFine: return "モザイク（細）"
        case .pixelateCoarse: return "モザイク（粗）"
        case .blur: return "ぼかし"
        }
    }

    var iconName: String {
        switch self {
        case .pixelateFine: return "square.grid.3x3"
        case .pixelateCoarse: return "square.grid.2x2"
        case .blur: return "drop.circle"
        }
    }
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
    var cornerRadius: CGFloat?
    var mosaicType: MosaicType?

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        startPoint: CGPoint,
        endPoint: CGPoint,
        color: NSColor = .red,
        lineWidth: CGFloat = 3.0,
        text: String? = nil,
        fontSize: CGFloat? = nil,
        cornerRadius: CGFloat? = nil,
        mosaicType: MosaicType? = nil
    ) {
        self.id = id
        self.type = type
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.fontSize = fontSize
        self.cornerRadius = cornerRadius
        self.mosaicType = mosaicType
    }

    /// Returns the annotation bounding box (image coordinate space).
    func bounds() -> CGRect {
        switch type {
        case .arrow:
            let margin = lineWidth * 6
            return CGRect(
                x: min(startPoint.x, endPoint.x) - margin,
                y: min(startPoint.y, endPoint.y) - margin,
                width: abs(endPoint.x - startPoint.x) + margin * 2,
                height: abs(endPoint.y - startPoint.y) + margin * 2
            )
        case .rectangle:
            let margin = lineWidth + 4
            return CGRect(
                x: min(startPoint.x, endPoint.x) - margin,
                y: min(startPoint.y, endPoint.y) - margin,
                width: abs(endPoint.x - startPoint.x) + margin * 2,
                height: abs(endPoint.y - startPoint.y) + margin * 2
            )
        case .text:
            return textBounds() ?? CGRect(origin: endPoint, size: CGSize(width: 50, height: 20))
        case .mosaic:
            return CGRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            )
        }
    }

    /// Computes the bounding rectangle for a text annotation (image coordinate space).
    func textBounds() -> CGRect? {
        guard type == .text, let text = text, !text.isEmpty else { return nil }
        let fontSize = self.fontSize ?? 16.0

        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let nsString = text as NSString
        let size = nsString.size(withAttributes: attributes)

        return CGRect(
            x: endPoint.x,
            y: endPoint.y,
            width: max(size.width, 50),
            height: max(size.height, fontSize * 1.2)
        )
    }

    /// Static helper to compute the bounding rectangle for arbitrary text and font size.
    static func computeTextBounds(text: String, fontSize: CGFloat, origin: CGPoint) -> CGRect {
        guard !text.isEmpty else {
            return CGRect(origin: origin, size: CGSize(width: 50, height: fontSize * 1.2))
        }
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let nsString = text as NSString
        let size = nsString.size(withAttributes: attributes)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: max(size.width, 50),
            height: max(size.height, fontSize * 1.2)
        )
    }
}
