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

    // Undo/Redo stacks - stores both screenshot and annotations
    private struct EditorState {
        let screenshot: Screenshot
        let annotations: [Annotation]
    }
    private var undoStack: [EditorState] = []
    private var redoStack: [EditorState] = []

    // Selection state
    var selectedAnnotationId: UUID?

    // Crop state (kept in image coordinates)
    var cropRect: CGRect?
    private var cropStartPoint: CGPoint?

    // Editing text bounds (image coordinates) - for canvas expansion
    var editingTextBounds: CGRect?

    var selectedColorBinding: Color {
        get { Color(nsColor: selectedColor) }
        set { selectedColor = NSColor(newValue) }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private var currentAnnotation: Annotation?

    /// Padding for canvas expansion (pixels in image coordinate space).
    private let expandPadding: CGFloat = 12

    /// Expanded bounding box that includes all annotations and the base image (image coordinates).
    var expandedBounds: CGRect {
        let imageRect = CGRect(origin: .zero, size: screenshot.image.size)
        var bounds = imageRect
        for annotation in annotations {
            bounds = bounds.union(annotation.bounds())
        }
        if let current = currentAnnotation {
            bounds = bounds.union(current.bounds())
        }
        // Include editing text bounds
        if let textBounds = editingTextBounds {
            bounds = bounds.union(textBounds)
        }
        // Add padding only when expansion is needed
        if bounds != imageRect {
            bounds = bounds.insetBy(dx: -expandPadding, dy: -expandPadding)
            // Apply padding only where it exceeds the original image area
            bounds = bounds.union(imageRect)
        }
        return bounds
    }

    /// Offset from expanded canvas origin to original image origin.
    var imageOffset: CGPoint {
        let eb = expandedBounds
        return CGPoint(x: -eb.origin.x, y: -eb.origin.y)
    }

    /// Image size after expansion (image coordinates).
    var expandedImageSize: CGSize {
        return expandedBounds.size
    }

    /// Whether canvas expansion is needed.
    var needsExpansion: Bool {
        let imageRect = CGRect(origin: .zero, size: screenshot.image.size)
        return expandedBounds != imageRect
    }

    init(screenshot: Screenshot) {
        self.screenshot = screenshot
        // Load previous settings from AppSettings
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
        undoStack.append(EditorState(screenshot: screenshot, annotations: annotations))
        redoStack.removeAll()
    }

    var compositeImage: NSImage {
        // Apply mosaic to base image if mosaic annotations exist
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

        // Apply only mosaic annotations (consider scale factor)
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
            return  // Do not create new annotation with select tool
        case .crop:
            return  // Crop is handled separately in AnnotationCanvas
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

    // MARK: - Crop

    func startCrop(at point: CGPoint) {
        cropStartPoint = point
        cropRect = CGRect(origin: point, size: .zero)
    }

    func updateCrop(to point: CGPoint) {
        guard let startPoint = cropStartPoint else { return }
        cropRect = CGRect(
            x: min(startPoint.x, point.x),
            y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x),
            height: abs(point.y - startPoint.y)
        )
    }

    func cancelCrop() {
        cropRect = nil
        cropStartPoint = nil
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

        // Save state for undo before modifying
        saveStateForUndo()

        let imageBounds = CGRect(origin: .zero, size: screenshot.image.size)
        let clampedRect = rect.intersection(imageBounds)
        guard clampedRect.width > 10 && clampedRect.height > 10 else {
            _ = undoStack.popLast()
            cropRect = nil
            return
        }

        let pixelScaleX = CGFloat(cgImage.width) / screenshot.image.size.width
        let pixelScaleY = CGFloat(cgImage.height) / screenshot.image.size.height

        // Convert to CGImage pixel coordinates (top-left origin)
        let cropX = clampedRect.origin.x * pixelScaleX
        let cropY = clampedRect.origin.y * pixelScaleY
        let cropWidth = clampedRect.width * pixelScaleX
        let cropHeight = clampedRect.height * pixelScaleY

        let cropCGRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

        guard let croppedCGImage = cgImage.cropping(to: cropCGRect) else {
            // Remove the undo state we just added since crop failed
            _ = undoStack.popLast()
            cropRect = nil
            return
        }

        // Create a new screenshot
        let newSize = NSSize(width: clampedRect.width, height: clampedRect.height)
        let newImage = NSImage(cgImage: croppedCGImage, size: newSize)

        screenshot = Screenshot(
            image: newImage,
            displayID: screenshot.displayID,
            scaleFactor: screenshot.scaleFactor
        )

        // Adjust annotation coordinates (relative to crop origin)
        let offsetX = clampedRect.origin.x
        let offsetY = clampedRect.origin.y
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
            // Exclude annotations outside the crop area
            let bounds = CGRect(origin: .zero, size: newSize)
            if bounds.contains(newAnnotation.startPoint) || bounds.contains(newAnnotation.endPoint) {
                return newAnnotation
            }
            return nil
        }

        // Clear redo stack since we made a new change
        redoStack.removeAll()

        cropRect = nil
        cropStartPoint = nil
        statusMessage = NSLocalizedString("editor.status.cropped", comment: "")
    }

    func clearAnnotations() {
        guard !annotations.isEmpty else { return }
        saveStateForUndo()
        annotations.removeAll()
        selectedAnnotationId = nil
        statusMessage = NSLocalizedString("editor.status.cleared", comment: "")
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(EditorState(screenshot: screenshot, annotations: annotations))
        let state = undoStack.removeLast()
        screenshot = state.screenshot
        annotations = state.annotations
        selectedAnnotationId = nil
        statusMessage = NSLocalizedString("editor.status.undo", comment: "")
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(EditorState(screenshot: screenshot, annotations: annotations))
        let state = redoStack.removeLast()
        screenshot = state.screenshot
        annotations = state.annotations
        selectedAnnotationId = nil
        statusMessage = NSLocalizedString("editor.status.redo", comment: "")
    }

    // MARK: - Selection & Move

    func hitTest(at point: CGPoint) -> Annotation? {
        // Check in reverse because newer annotations are on top
        for annotation in annotations.reversed() where annotationContainsPoint(annotation, point) {
            return annotation
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
            // Move startPoint
            annotation.startPoint = point
        case .endPoint:
            // Move endPoint
            annotation.endPoint = point
        case .startXEndY:
            // Move startPoint.x and endPoint.y
            annotation.startPoint.x = point.x
            annotation.endPoint.y = point.y
        case .endXStartY:
            // Move endPoint.x and startPoint.y
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
        statusMessage = NSLocalizedString("editor.status.deleted", comment: "")
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
        // Determine by distance to the arrow segment
        let tolerance: CGFloat = 15.0

        let start = annotation.startPoint
        let end = annotation.endPoint

        let lineLength = hypot(end.x - start.x, end.y - start.y)
        guard lineLength > 0 else { return false }

        // Compute distance between point and line segment
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
        // Include the area near the border
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
        statusMessage = NSLocalizedString("editor.status.copied", comment: "")
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
                    statusMessage = NSLocalizedString("editor.status.convert_failed", comment: "")
                    return
                }
                try pngData.write(to: url)
                let format = NSLocalizedString("editor.status.saved_format", comment: "")
                statusMessage = String.localizedStringWithFormat(format, url.lastPathComponent)
            } catch {
                let format = NSLocalizedString("editor.status.save_failed_format", comment: "")
                statusMessage = String.localizedStringWithFormat(format, error.localizedDescription)
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

        // Keep existing behavior when no expansion is needed
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

        // Draw on expanded canvas
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

        // Fill with white background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: expandedPixelWidth, height: expandedPixelHeight))

        // Draw base image at offset (CGContext is Y-flipped: bottom-left origin)
        let imgX = offset.x * scaleFactor
        let imgY = CGFloat(expandedPixelHeight) - offset.y * scaleFactor - CGFloat(origPixelHeight)
        context.draw(cgImage, in: CGRect(x: imgX, y: imgY,
                                          width: CGFloat(origPixelWidth),
                                          height: CGFloat(origPixelHeight)))

        // Draw annotations with offset adjustment
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
