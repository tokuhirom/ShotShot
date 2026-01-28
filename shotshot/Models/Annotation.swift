import AppKit
import Foundation

enum AnnotationType: Sendable {
    case arrow
    case rectangle
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
    var cornerRadius: CGFloat?

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        startPoint: CGPoint,
        endPoint: CGPoint,
        color: NSColor = .red,
        lineWidth: CGFloat = 3.0,
        text: String? = nil,
        fontSize: CGFloat? = nil,
        cornerRadius: CGFloat? = nil
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
    }

    /// テキスト注釈の境界矩形を計算（画像座標系）
    func textBounds() -> CGRect? {
        guard type == .text, let text = text, !text.isEmpty else { return nil }
        let fontSize = self.fontSize ?? 16.0

        let lines = text.components(separatedBy: "\n")
        let lineCount = max(lines.count, 1)
        let maxLineLength = lines.map { $0.count }.max() ?? 0

        // NSFont を使って正確なメトリクスを取得
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let lineHeight = font.ascender - font.descender + font.leading

        // 日本語文字も考慮した幅の推定
        let estimatedWidth = max(CGFloat(maxLineLength) * fontSize * 0.7, 50)
        let estimatedHeight = lineHeight * CGFloat(lineCount)

        return CGRect(
            x: endPoint.x,
            y: endPoint.y,
            width: estimatedWidth,
            height: estimatedHeight
        )
    }
}
