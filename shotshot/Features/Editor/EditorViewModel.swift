import AppKit
import Foundation
import SwiftUI

@Observable
@MainActor
final class EditorViewModel {
    var screenshot: Screenshot
    var annotations: [Annotation] = []
    var selectedTool: ToolType {
        didSet { AppSettings.shared.selectedToolName = selectedTool.name }
    }
    var selectedColor: NSColor {
        didSet { AppSettings.shared.selectedColor = selectedColor }
    }
    var lineWidth: CGFloat {
        didSet { AppSettings.shared.lineWidth = lineWidth }
    }
    var fontSize: CGFloat {
        didSet { AppSettings.shared.fontSize = fontSize }
    }
    var useRoundedCorners: Bool {
        didSet { AppSettings.shared.useRoundedCorners = useRoundedCorners }
    }
    var mosaicType: MosaicType {
        didSet { AppSettings.shared.mosaicType = mosaicType }
    }
    var statusMessage: String = ""

    // Undo/Redo stacks
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    // 選択状態
    var selectedAnnotationId: UUID? = nil

    // クロップ状態（画像座標系で保持）
    var cropRect: CGRect? = nil

    // 編集中テキストのバウンズ（画像座標系）- キャンバス拡張用
    var editingTextBounds: CGRect? = nil

    var selectedColorBinding: Color {
        get { Color(nsColor: selectedColor) }
        set { selectedColor = NSColor(newValue) }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private var currentAnnotation: Annotation?

    /// キャンバス拡張時の余白（画像座標系でのピクセル数）
    private let expandPadding: CGFloat = 12

    /// 全注釈と元画像を包含する拡張バウンディングボックス（画像座標系）
    var expandedBounds: CGRect {
        let imageRect = CGRect(origin: .zero, size: screenshot.image.size)
        var bounds = imageRect
        for annotation in annotations {
            bounds = bounds.union(annotation.bounds())
        }
        if let current = currentAnnotation {
            bounds = bounds.union(current.bounds())
        }
        // 編集中テキストのバウンズも含める
        if let textBounds = editingTextBounds {
            bounds = bounds.union(textBounds)
        }
        // 拡張が必要な場合のみパディングを追加
        if bounds != imageRect {
            bounds = bounds.insetBy(dx: -expandPadding, dy: -expandPadding)
            // パディングで元画像領域を超えた分のみ反映（元画像内にはパディング不要）
            bounds = bounds.union(imageRect)
        }
        return bounds
    }

    /// 拡張キャンバスの原点から元画像原点までのオフセット
    var imageOffset: CGPoint {
        let eb = expandedBounds
        return CGPoint(x: -eb.origin.x, y: -eb.origin.y)
    }

    /// 拡張後の画像サイズ（画像座標系）
    var expandedImageSize: CGSize {
        return expandedBounds.size
    }

    /// キャンバス拡張が必要かどうか
    var needsExpansion: Bool {
        let imageRect = CGRect(origin: .zero, size: screenshot.image.size)
        return expandedBounds != imageRect
    }

    init(screenshot: Screenshot) {
        self.screenshot = screenshot
        // AppSettingsから前回の設定を読み込み
        let settings = AppSettings.shared
        self.selectedTool = ToolType.from(name: settings.selectedToolName)
        self.selectedColor = settings.selectedColor
        self.lineWidth = settings.lineWidth
        self.fontSize = settings.fontSize
        self.useRoundedCorners = settings.useRoundedCorners
        self.mosaicType = settings.mosaicType
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
        case .crop:
            return  // クロップはAnnotationCanvasで別途処理
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
            fontSize: fontSize,
            cornerRadius: (annotationType == .rectangle && useRoundedCorners) ? 8.0 : nil,
            mosaicType: annotationType == .mosaic ? mosaicType : nil
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

    func updateTextAnnotation(id: UUID, text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        saveStateForUndo()
        annotations[index].text = text
    }

    func deleteAnnotation(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        saveStateForUndo()
        annotations.remove(at: index)
        if selectedAnnotationId == id {
            selectedAnnotationId = nil
        }
    }

    // MARK: - クロップ

    func startCrop(at point: CGPoint) {
        cropRect = CGRect(origin: point, size: .zero)
    }

    func updateCrop(to point: CGPoint) {
        guard let startPoint = cropRect?.origin else { return }
        cropRect = CGRect(
            x: min(startPoint.x, point.x),
            y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x),
            height: abs(point.y - startPoint.y)
        )
    }

    func cancelCrop() {
        cropRect = nil
    }

    func applyCrop() {
        guard let rect = cropRect, rect.width > 10 && rect.height > 10 else {
            cropRect = nil
            return
        }

        guard let cgImage = screenshot.cgImage else {
            cropRect = nil
            return
        }

        let scale = screenshot.scaleFactor

        // 画像座標系に変換（Y軸反転）
        let imageHeight = CGFloat(cgImage.height)
        let cropX = rect.origin.x * scale
        let cropY = imageHeight - (rect.origin.y + rect.height) * scale
        let cropWidth = rect.width * scale
        let cropHeight = rect.height * scale

        let cropCGRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

        guard let croppedCGImage = cgImage.cropping(to: cropCGRect) else {
            cropRect = nil
            return
        }

        // 新しいスクリーンショットを作成
        let newSize = NSSize(width: rect.width, height: rect.height)
        let newImage = NSImage(cgImage: croppedCGImage, size: newSize)

        screenshot = Screenshot(
            image: newImage,
            displayID: screenshot.displayID,
            scaleFactor: screenshot.scaleFactor
        )

        // 注釈の座標を調整（クロップ領域の原点を基準に）
        let offsetX = rect.origin.x
        let offsetY = rect.origin.y
        annotations = annotations.compactMap { annotation in
            var newAnnotation = annotation
            newAnnotation.startPoint = CGPoint(
                x: annotation.startPoint.x - offsetX,
                y: annotation.startPoint.y - offsetY
            )
            newAnnotation.endPoint = CGPoint(
                x: annotation.endPoint.x - offsetX,
                y: annotation.endPoint.y - offsetY
            )
            // クロップ領域外の注釈は除外
            let bounds = CGRect(origin: .zero, size: newSize)
            if bounds.contains(newAnnotation.startPoint) || bounds.contains(newAnnotation.endPoint) {
                return newAnnotation
            }
            return nil
        }

        // Undo履歴をクリア（クロップ後は戻せない）
        undoStack.removeAll()
        redoStack.removeAll()

        cropRect = nil
        statusMessage = "画像を切り抜きました"
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
        guard let bounds = annotation.textBounds() else { return false }
        let padding: CGFloat = 15
        let expandedRect = bounds.insetBy(dx: -padding, dy: -padding)
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

    func saveAs() {
        let finalImage = renderFinalImage()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ImageExporter.generateFilename()
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                guard let tiffData = finalImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    statusMessage = "画像の変換に失敗しました"
                    return
                }
                try pngData.write(to: url)
                statusMessage = "保存しました: \(url.lastPathComponent)"
            } catch {
                statusMessage = "保存に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    private func renderFinalImage() -> NSImage {
        guard let cgImage = screenshot.cgImage else { return screenshot.image }

        let scaleFactor = screenshot.scaleFactor
        let eb = expandedBounds
        let offset = imageOffset

        let origPixelWidth = cgImage.width
        let origPixelHeight = cgImage.height

        let expandedPixelWidth = Int(eb.width * scaleFactor)
        let expandedPixelHeight = Int(eb.height * scaleFactor)

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // 拡張不要の場合は従来通り
        let isExpanded = offset.x != 0 || offset.y != 0
            || expandedPixelWidth != origPixelWidth
            || expandedPixelHeight != origPixelHeight

        if !isExpanded {
            guard let context = CGContext(
                data: nil,
                width: origPixelWidth,
                height: origPixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return screenshot.image
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: origPixelWidth, height: origPixelHeight))

            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext

            for annotation in annotations {
                drawAnnotation(annotation, in: context, imageSize: CGSize(width: origPixelWidth, height: origPixelHeight), scaleFactor: scaleFactor)
            }

            NSGraphicsContext.restoreGraphicsState()

            guard let finalCGImage = context.makeImage() else {
                return screenshot.image
            }

            return NSImage(cgImage: finalCGImage, size: screenshot.image.size)
        }

        // 拡張キャンバスで描画
        guard let context = CGContext(
            data: nil,
            width: expandedPixelWidth,
            height: expandedPixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return screenshot.image
        }

        // 白背景で塗りつぶし
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: expandedPixelWidth, height: expandedPixelHeight))

        // 元画像を offset 位置に描画（CGContext は Y 反転: 左下原点）
        let imgX = offset.x * scaleFactor
        let imgY = CGFloat(expandedPixelHeight) - offset.y * scaleFactor - CGFloat(origPixelHeight)
        context.draw(cgImage, in: CGRect(x: imgX, y: imgY,
                                          width: CGFloat(origPixelWidth),
                                          height: CGFloat(origPixelHeight)))

        // 注釈を offset 補正して描画
        let expandedImageSize = CGSize(width: expandedPixelWidth, height: expandedPixelHeight)

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        for annotation in annotations {
            var adjusted = annotation
            adjusted.startPoint.x += offset.x
            adjusted.startPoint.y += offset.y
            adjusted.endPoint.x += offset.x
            adjusted.endPoint.y += offset.y
            drawAnnotation(adjusted, in: context, imageSize: expandedImageSize, scaleFactor: scaleFactor)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let finalCGImage = context.makeImage() else {
            return screenshot.image
        }

        return NSImage(cgImage: finalCGImage, size: eb.size)
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
