import AppKit
import CoreGraphics
import CoreImage
import Foundation

struct MosaicTool: AnnotationToolProtocol {
    static func draw(_ annotation: Annotation, in context: CGContext, imageSize: CGSize, scaleFactor: CGFloat = 1.0) {
        // Adjust annotation coordinates by scale factor
        let scale = scaleFactor
        let scaledStart = CGPoint(x: annotation.startPoint.x * scale, y: annotation.startPoint.y * scale)
        let scaledEnd = CGPoint(x: annotation.endPoint.x * scale, y: annotation.endPoint.y * scale)

        // Coordinates for CGImage (top-left origin)
        let cropRect = CGRect(
            x: min(scaledStart.x, scaledEnd.x),
            y: min(scaledStart.y, scaledEnd.y),
            width: abs(scaledEnd.x - scaledStart.x),
            height: abs(scaledEnd.y - scaledStart.y)
        )

        // Coordinates for CGContext (bottom-left origin)
        let drawRect = CGRect(
            x: cropRect.origin.x,
            y: imageSize.height - cropRect.origin.y - cropRect.height,
            width: cropRect.width,
            height: cropRect.height
        )

        guard cropRect.width > 0 && cropRect.height > 0 else {
            return
        }

        guard let currentImage = context.makeImage() else {
            return
        }

        guard let croppedImage = currentImage.cropping(to: cropRect) else {
            return
        }

        let mosaicType = annotation.mosaicType ?? .pixelateFine
        let processedImage: CGImage?

        switch mosaicType {
        case .pixelateFine:
            processedImage = applyPixellate(to: croppedImage, scale: 10)
        case .pixelateCoarse:
            processedImage = applyPixellate(to: croppedImage, scale: 25)
        case .blur:
            processedImage = applyBlur(to: croppedImage, radius: 20)
        }

        guard let finalImage = processedImage else {
            return
        }

        context.saveGState()
        context.draw(finalImage, in: drawRect)
        context.restoreGState()
    }

    private static func applyPixellate(to image: CGImage, scale: CGFloat) -> CGImage? {
        let ciImage = CIImage(cgImage: image)

        guard let filter = CIFilter(name: "CIPixellate") else {
            return nil
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let ciContext = CIContext()
        return ciContext.createCGImage(outputImage, from: ciImage.extent)
    }

    private static func applyBlur(to image: CGImage, radius: CGFloat) -> CGImage? {
        let ciImage = CIImage(cgImage: image)

        guard let filter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let outputImage = filter.outputImage else {
            return nil
        }

        // Blur expands edges, so clip to original size
        let ciContext = CIContext()
        return ciContext.createCGImage(outputImage, from: ciImage.extent)
    }
}
