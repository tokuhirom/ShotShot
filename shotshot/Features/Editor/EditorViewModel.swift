import AppKit
import Foundation
import SwiftUI

@Observable
@MainActor
final class EditorViewModel {
    let screenshot: Screenshot
    var annotations: [Annotation] = []
    var selectedTool: ToolType = .arrow
    var selectedColor: NSColor = NSColor(red: 0.98, green: 0.22, blue: 0.53, alpha: 1.0) // Skitch Pink
    var lineWidth: CGFloat = 3.0
    var fontSize: CGFloat = 16.0
    var statusMessage: String = ""

    var selectedColorBinding: Color {
        get { Color(nsColor: selectedColor) }
        set { selectedColor = NSColor(newValue) }
    }

    private var currentAnnotation: Annotation?

    init(screenshot: Screenshot) {
        self.screenshot = screenshot
    }

    var compositeImage: NSImage {
        let image = screenshot.image.copy() as! NSImage
        return image
    }

    func startAnnotation(at point: CGPoint) {
        let annotationType: AnnotationType
        switch selectedTool {
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
        annotations.append(annotation)
        currentAnnotation = nil
    }

    func getCurrentAnnotation() -> Annotation? {
        return currentAnnotation
    }

    func clearAnnotations() {
        annotations.removeAll()
        statusMessage = "注釈をクリアしました"
    }

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        statusMessage = "操作を取り消しました"
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
            drawAnnotation(annotation, in: context, imageSize: CGSize(width: width, height: height))
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let finalCGImage = context.makeImage() else {
            return screenshot.image
        }

        return NSImage(cgImage: finalCGImage, size: screenshot.image.size)
    }

    private func drawAnnotation(_ annotation: Annotation, in context: CGContext, imageSize: CGSize) {
        switch annotation.type {
        case .arrow:
            ArrowTool.draw(annotation, in: context, imageSize: imageSize)
        case .rectangle:
            RectangleTool.draw(annotation, in: context, imageSize: imageSize)
        case .text:
            TextTool.draw(annotation, in: context, imageSize: imageSize)
        case .mosaic:
            MosaicTool.draw(annotation, in: context, imageSize: imageSize)
        }
    }
}
