import AppKit
import Foundation
import SwiftUI

@Observable
@MainActor
final class EditorViewModel {
    let screenshot: Screenshot
    var annotations: [Annotation] = []
    var selectedTool: ToolType = .select
    var selectedColor: NSColor = NSColor(red: 0.98, green: 0.22, blue: 0.53, alpha: 1.0) // Skitch Pink
    var lineWidth: CGFloat = 3.0
    var fontSize: CGFloat = 32.0
    var statusMessage: String = ""

    // Undo/Redo stacks
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    // 選択状態
    var selectedAnnotationId: UUID? = nil

    var selectedColorBinding: Color {
        get { Color(nsColor: selectedColor) }
        set { selectedColor = NSColor(newValue) }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private var currentAnnotation: Annotation?

    init(screenshot: Screenshot) {
        self.screenshot = screenshot
    }

    // MARK: - Undo/Redo

    func saveStateForUndo() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    var compositeImage: NSImage {
        // モザイク注釈がある場合は、ベース画像にモザイクを適用
        let mosaicAnnotations = annotations.filter { $0.type == .mosaic }
        guard !mosaicAnnotations.isEmpty, let cgImage = screenshot.cgImage else {
            return screenshot.image
        }

        let width = cgImage.width
        let height = cgImage.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return screenshot.image
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // モザイク注釈のみ適用（スケールファクター考慮）
        let scaleFactor = screenshot.scaleFactor
        for annotation in mosaicAnnotations {
            MosaicTool.draw(annotation, in: context, imageSize: CGSize(width: width, height: height), scaleFactor: scaleFactor)
        }

        guard let resultImage = context.makeImage() else {
            return screenshot.image
        }

        return NSImage(cgImage: resultImage, size: screenshot.image.size)
    }

    func startAnnotation(at point: CGPoint) {
        let annotationType: AnnotationType
        switch selectedTool {
        case .select:
            return  // 選択ツールでは新規注釈を作成しない
        case .arrow:
            annotationType = .arrow
        case .rectangle:
            annotationType = .rectangle
        case .text:
            annotationType = .text
        case .mosaic:
            annotationType = .mosaic
        }

        currentAnnotation = Annotation(
            type: annotationType,
            startPoint: point,
            endPoint: point,
            color: selectedColor,
            lineWidth: lineWidth,
            fontSize: fontSize
        )
    }

    func updateAnnotation(to point: CGPoint) {
        currentAnnotation?.endPoint = point
    }

    func finishAnnotation(at point: CGPoint, text: String? = nil) {
        guard var annotation = currentAnnotation else { return }
        annotation.endPoint = point
        if let text = text {
            annotation.text = text
        }
        saveStateForUndo()
        annotations.append(annotation)
        currentAnnotation = nil
    }

    func addTextAnnotation(at point: CGPoint, text: String) {
        let annotation = Annotation(
            type: .text,
            startPoint: point,
            endPoint: point,
            color: selectedColor,
            lineWidth: lineWidth,
            text: text,
            fontSize: fontSize
        )
        saveStateForUndo()
        annotations.append(annotation)
    }

    func getCurrentAnnotation() -> Annotation? {
        return currentAnnotation
    }

    func clearAnnotations() {
        guard !annotations.isEmpty else { return }
        saveStateForUndo()
        annotations.removeAll()
        selectedAnnotationId = nil
        statusMessage = "注釈をクリアしました"
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(annotations)
        annotations = undoStack.removeLast()
        selectedAnnotationId = nil
        statusMessage = "操作を取り消しました"
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(annotations)
        annotations = redoStack.removeLast()
        selectedAnnotationId = nil
        statusMessage = "操作をやり直しました"
    }

    // MARK: - 選択・移動

    func hitTest(at point: CGPoint) -> Annotation? {
        // 後から追加された注釈が上にあるので逆順でチェック
        for annotation in annotations.reversed() {
            if annotationContainsPoint(annotation, point) {
                return annotation
            }
        }
        return nil
    }

    func selectAnnotation(id: UUID) {
        selectedAnnotationId = id
    }

    func deselectAnnotation() {
        selectedAnnotationId = nil
    }

    func moveSelectedAnnotation(by delta: CGPoint) {
        guard let selectedId = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == selectedId }) else { return }

        var annotation = annotations[index]
        annotation.startPoint = CGPoint(
            x: annotation.startPoint.x + delta.x,
            y: annotation.startPoint.y + delta.y
        )
        annotation.endPoint = CGPoint(
            x: annotation.endPoint.x + delta.x,
            y: annotation.endPoint.y + delta.y
        )
        annotations[index] = annotation
    }

    func resizeSelectedAnnotation(handle: ResizeHandle, to point: CGPoint) {
        guard let selectedId = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == selectedId }) else { return }

        var annotation = annotations[index]

        switch handle {
        case .startPoint:
            // startPoint を動かす
            annotation.startPoint = point
        case .endPoint:
            // endPoint を動かす
            annotation.endPoint = point
        case .startXEndY:
            // startPoint.x と endPoint.y を動かす
            annotation.startPoint.x = point.x
            annotation.endPoint.y = point.y
        case .endXStartY:
            // endPoint.x と startPoint.y を動かす
            annotation.endPoint.x = point.x
            annotation.startPoint.y = point.y
        }

        annotations[index] = annotation
    }

    func deleteSelectedAnnotation() {
        guard let selectedId = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == selectedId }) else { return }

        saveStateForUndo()
        annotations.remove(at: index)
        selectedAnnotationId = nil
        statusMessage = "注釈を削除しました"
    }

    private func annotationContainsPoint(_ annotation: Annotation, _ point: CGPoint) -> Bool {
        switch annotation.type {
        case .arrow:
            return arrowContainsPoint(annotation, point)
        case .rectangle:
            return rectangleContainsPoint(annotation, point)
        case .text:
            return textContainsPoint(annotation, point)
        case .mosaic:
            return rectangleContainsPoint(annotation, point)
        }
    }

    private func arrowContainsPoint(_ annotation: Annotation, _ point: CGPoint) -> Bool {
        // 矢印の線分からの距離で判定
        let tolerance: CGFloat = 15.0

        let start = annotation.startPoint
        let end = annotation.endPoint

        let lineLength = hypot(end.x - start.x, end.y - start.y)
        guard lineLength > 0 else { return false }

        // 点と線分の距離を計算
        let t = max(0, min(1, ((point.x - start.x) * (end.x - start.x) + (point.y - start.y) * (end.y - start.y)) / (lineLength * lineLength)))
        let nearestX = start.x + t * (end.x - start.x)
        let nearestY = start.y + t * (end.y - start.y)
        let distance = hypot(point.x - nearestX, point.y - nearestY)

        return distance <= tolerance
    }

    private func rectangleContainsPoint(_ annotation: Annotation, _ point: CGPoint) -> Bool {
        let rect = CGRect(
            x: min(annotation.startPoint.x, annotation.endPoint.x),
            y: min(annotation.startPoint.y, annotation.endPoint.y),
            width: abs(annotation.endPoint.x - annotation.startPoint.x),
            height: abs(annotation.endPoint.y - annotation.startPoint.y)
        )
        // 境界線付近も含める
        let expandedRect = rect.insetBy(dx: -10, dy: -10)
        return expandedRect.contains(point)
    }

    private func textContainsPoint(_ annotation: Annotation, _ point: CGPoint) -> Bool {
        guard let text = annotation.text, !text.isEmpty else { return false }
        let fontSize = annotation.fontSize ?? 16.0

        // テキストの大まかなサイズを推定（日本語も考慮して1文字≒fontSizeとする）
        let estimatedWidth = max(CGFloat(text.count) * fontSize * 0.8, 50)
        let estimatedHeight = fontSize * 1.5

        let rect = CGRect(
            x: annotation.endPoint.x,
            y: annotation.endPoint.y,
            width: estimatedWidth,
            height: estimatedHeight
        )
        let expandedRect = rect.insetBy(dx: -15, dy: -15)
        return expandedRect.contains(point)
    }

    func copyToClipboard() {
        let finalImage = renderFinalImage()
        ClipboardService.copy(finalImage)
        statusMessage = "クリップボードにコピーしました"
    }

    func done() {
        let finalImage = renderFinalImage()
        let settings = AppSettings.shared

        // Save to file
        do {
            let finalScreenshot = Screenshot(
                image: finalImage,
                displayID: screenshot.displayID,
                scaleFactor: screenshot.scaleFactor
            )
            let url = try ImageExporter.save(finalScreenshot, to: settings.savePath)
            print("[EditorViewModel] Saved to: \(url.path)")
        } catch {
            print("[EditorViewModel] Save failed: \(error.localizedDescription)")
        }

        // Copy to clipboard
        ClipboardService.copy(finalImage)

        // Close window
        NSApp.keyWindow?.close()
    }

    func cancel() {
        NSApp.keyWindow?.close()
    }

    private func renderFinalImage() -> NSImage {
        guard let cgImage = screenshot.cgImage else { return screenshot.image }

        let width = cgImage.width
        let height = cgImage.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return screenshot.image
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        for annotation in annotations {
            drawAnnotation(annotation, in: context, imageSize: CGSize(width: width, height: height), scaleFactor: screenshot.scaleFactor)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let finalCGImage = context.makeImage() else {
            return screenshot.image
        }

        return NSImage(cgImage: finalCGImage, size: screenshot.image.size)
    }

    private func drawAnnotation(_ annotation: Annotation, in context: CGContext, imageSize: CGSize, scaleFactor: CGFloat) {
        switch annotation.type {
        case .arrow:
            ArrowTool.draw(annotation, in: context, imageSize: imageSize, scaleFactor: scaleFactor)
        case .rectangle:
            RectangleTool.draw(annotation, in: context, imageSize: imageSize, scaleFactor: scaleFactor)
        case .text:
            TextTool.draw(annotation, in: context, imageSize: imageSize, scaleFactor: scaleFactor)
        case .mosaic:
            MosaicTool.draw(annotation, in: context, imageSize: imageSize, scaleFactor: scaleFactor)
        }
    }
}
