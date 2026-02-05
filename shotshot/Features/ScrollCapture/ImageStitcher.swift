import AppKit
import Accelerate
import Foundation

/// Stitches multiple images vertically by detecting overlapping regions
@MainActor
final class ImageStitcher {

    /// Stitches an array of images vertically, detecting and removing overlapping regions
    /// - Parameter images: Array of CGImages to stitch (in order from top to bottom)
    /// - Returns: A single stitched CGImage
    func stitch(images: [CGImage]) -> CGImage? {
        guard !images.isEmpty else { return nil }
        guard images.count > 1 else { return images.first }

        NSLog("[ImageStitcher] Starting to stitch %d images", images.count)

        // Calculate overlaps between consecutive images
        var overlaps: [Int] = []
        for i in 0..<(images.count - 1) {
            let overlap = findOverlap(topImage: images[i], bottomImage: images[i + 1])
            overlaps.append(overlap)
            NSLog("[ImageStitcher] Overlap between image %d and %d: %d pixels", i, i + 1, overlap)
        }

        // Calculate total height
        let width = images[0].width
        var totalHeight = images.reduce(0) { $0 + $1.height }
        totalHeight -= overlaps.reduce(0, +)

        NSLog("[ImageStitcher] Final image size: %dx%d", width, totalHeight)

        // Create the output context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            NSLog("[ImageStitcher] Failed to create CGContext")
            return nil
        }

        // Draw images from bottom to top (CGContext has bottom-left origin)
        var currentY = 0
        for i in (0..<images.count).reversed() {
            let image = images[i]
            let drawHeight: Int

            if i == images.count - 1 {
                // Last image (bottom-most): draw full height
                drawHeight = image.height
            } else {
                // Other images: subtract overlap with the image below
                drawHeight = image.height - overlaps[i]
            }

            let rect = CGRect(x: 0, y: currentY, width: width, height: image.height)
            context.draw(image, in: rect)

            currentY += drawHeight
        }

        return context.makeImage()
    }

    /// Finds the overlap between two consecutive images
    /// - Parameters:
    ///   - topImage: The image above
    ///   - bottomImage: The image below
    /// - Returns: The number of pixels of overlap
    private func findOverlap(topImage: CGImage, bottomImage: CGImage) -> Int {
        let searchRange = min(200, topImage.height / 2, bottomImage.height / 2)
        let minOverlap = 20
        let matchThreshold: Float = 0.95

        guard searchRange >= minOverlap else { return 0 }

        // Get pixel data for comparison
        guard let topData = getPixelData(from: topImage),
              let bottomData = getPixelData(from: bottomImage) else {
            return 0
        }

        let width = topImage.width
        let topHeight = topImage.height
        _ = bottomImage.height  // bottomHeight not used but validates image
        let bytesPerRow = width * 4

        // Search for best overlap
        var bestOverlap = 0
        var bestSimilarity: Float = 0

        for overlap in minOverlap...searchRange {
            let similarity = calculateSimilarity(
                topData: topData,
                bottomData: bottomData,
                topStartRow: topHeight - overlap,
                bottomStartRow: 0,
                rowCount: overlap,
                bytesPerRow: bytesPerRow
            )

            if similarity > matchThreshold && similarity > bestSimilarity {
                bestSimilarity = similarity
                bestOverlap = overlap
            }
        }

        return bestOverlap
    }

    /// Gets raw pixel data from a CGImage
    private func getPixelData(from image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height

        var pixelData = Data(count: totalBytes)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        let success = pixelData.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return success ? pixelData : nil
    }

    /// Calculates similarity between two image regions using Accelerate framework
    private func calculateSimilarity(
        topData: Data,
        bottomData: Data,
        topStartRow: Int,
        bottomStartRow: Int,
        rowCount: Int,
        bytesPerRow: Int
    ) -> Float {
        let topOffset = topStartRow * bytesPerRow
        let bottomOffset = bottomStartRow * bytesPerRow
        let compareBytes = rowCount * bytesPerRow

        guard topOffset >= 0,
              bottomOffset >= 0,
              topOffset + compareBytes <= topData.count,
              bottomOffset + compareBytes <= bottomData.count else {
            return 0
        }

        var matchingPixels = 0
        let totalPixels = rowCount * (bytesPerRow / 4)

        topData.withUnsafeBytes { topBuffer in
            bottomData.withUnsafeBytes { bottomBuffer in
                guard let topPtr = topBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let bottomPtr = bottomBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }

                // Compare pixels (skip alpha channel)
                for i in 0..<totalPixels {
                    let topPixelOffset = topOffset + i * 4
                    let bottomPixelOffset = bottomOffset + i * 4

                    let rDiff = abs(Int(topPtr[topPixelOffset + 1]) - Int(bottomPtr[bottomPixelOffset + 1]))
                    let gDiff = abs(Int(topPtr[topPixelOffset + 2]) - Int(bottomPtr[bottomPixelOffset + 2]))
                    let bDiff = abs(Int(topPtr[topPixelOffset + 3]) - Int(bottomPtr[bottomPixelOffset + 3]))

                    // Allow small differences for anti-aliasing and compression artifacts
                    if rDiff <= 5 && gDiff <= 5 && bDiff <= 5 {
                        matchingPixels += 1
                    }
                }
            }
        }

        return Float(matchingPixels) / Float(totalPixels)
    }
}
