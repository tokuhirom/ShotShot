import AppKit
import CoreGraphics
import CoreImage
import Foundation

struct MosaicTool: AnnotationToolProtocol {
    static func draw(_ annotation: Annotation, in context: CGContext, imageSize: CGSize) {
        let start = CGPoint(
            x: annotation.startPoint.x,
            y: imageSize.height - annotation.startPoint.y
        )
        let end = CGPoint(
            x: annotation.endPoint.x,
            y: imageSize.height - annotation.endPoint.y
        )

        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        guard rect.width > 0 && rect.height > 0 else { return }

        guard let currentImage = context.makeImage() else { return }

        guard let croppedImage = currentImage.cropping(to: rect) else { return }

        guard let pixellatedImage = applyPixellate(to: croppedImage, scale: 20) else { return }

        context.saveGState()

        context.draw(pixellatedImage, in: rect)

        context.restoreGState()
    }

    private static func applyPixellate(to image: CGImage, scale: CGFloat) -> CGImage? {
        let ciImage = CIImage(cgImage: image)

        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)

        guard let outputImage = filter.outputImage else { return nil }

        let ciContext = CIContext()
        return ciContext.createCGImage(outputImage, from: outputImage.extent)
    }
}
