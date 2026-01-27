import AppKit
import CoreGraphics
import CoreImage
import Foundation

struct MosaicTool: AnnotationToolProtocol {
    static func draw(_ annotation: Annotation, in context: CGContext, imageSize: CGSize, scaleFactor: CGFloat = 1.0) {
        // 注釈座標をスケールファクターで調整
        let scale = scaleFactor
        let scaledStart = CGPoint(x: annotation.startPoint.x * scale, y: annotation.startPoint.y * scale)
        let scaledEnd = CGPoint(x: annotation.endPoint.x * scale, y: annotation.endPoint.y * scale)

        // CGImage用の座標（左上原点）
        let cropRect = CGRect(
            x: min(scaledStart.x, scaledEnd.x),
            y: min(scaledStart.y, scaledEnd.y),
            width: abs(scaledEnd.x - scaledStart.x),
            height: abs(scaledEnd.y - scaledStart.y)
        )

        // CGContext用の座標（左下原点）
        let drawRect = CGRect(
            x: cropRect.origin.x,
            y: imageSize.height - cropRect.origin.y - cropRect.height,
            width: cropRect.width,
            height: cropRect.height
        )

        guard cropRect.width > 0 && cropRect.height > 0 else {
            NSLog("[MosaicTool] rect size is zero")
            return
        }

        guard let currentImage = context.makeImage() else {
            NSLog("[MosaicTool] Failed to make image from context")
            return
        }
        NSLog("[MosaicTool] currentImage: %dx%d, cropRect: %@, drawRect: %@", currentImage.width, currentImage.height, "\(cropRect)", "\(drawRect)")

        guard let croppedImage = currentImage.cropping(to: cropRect) else {
            NSLog("[MosaicTool] Failed to crop image")
            return
        }
        NSLog("[MosaicTool] croppedImage: %dx%d", croppedImage.width, croppedImage.height)

        guard let pixellatedImage = applyPixellate(to: croppedImage, scale: 20) else {
            NSLog("[MosaicTool] Failed to apply pixellate filter")
            return
        }
        NSLog("[MosaicTool] pixellatedImage: %dx%d", pixellatedImage.width, pixellatedImage.height)

        context.saveGState()
        context.draw(pixellatedImage, in: drawRect)
        context.restoreGState()
        NSLog("[MosaicTool] Done drawing mosaic")
    }

    private static func applyPixellate(to image: CGImage, scale: CGFloat) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        NSLog("[MosaicTool] ciImage extent: %@", "\(ciImage.extent)")

        guard let filter = CIFilter(name: "CIPixellate") else {
            NSLog("[MosaicTool] Failed to create CIPixellate filter")
            return nil
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)

        guard let outputImage = filter.outputImage else {
            NSLog("[MosaicTool] Filter output is nil")
            return nil
        }
        NSLog("[MosaicTool] outputImage extent: %@", "\(outputImage.extent)")

        let ciContext = CIContext()
        let result = ciContext.createCGImage(outputImage, from: ciImage.extent)
        if result == nil {
            NSLog("[MosaicTool] Failed to create CGImage from CIImage")
        }
        return result
    }
}
