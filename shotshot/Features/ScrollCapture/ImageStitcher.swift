import AppKit
import Accelerate
import Foundation

/// Stitches multiple images vertically by detecting overlapping regions
final class ImageStitcher {

    /// Stitches an array of images vertically, detecting and removing overlapping regions
    /// - Parameter images: Array of CGImages to stitch (in order from top to bottom)
    /// - Returns: A single stitched CGImage
    nonisolated func stitch(images: [CGImage]) -> CGImage? {
        guard !images.isEmpty else { return nil }
        guard images.count > 1 else { return images.first }

        NSLog("[ImageStitcher] Starting to stitch %d images", images.count)

        // Calculate overlaps between consecutive images using fast sampling
        var overlaps: [Int] = []
        for i in 0..<(images.count - 1) {
            let overlap = findOverlapFast(topImage: images[i], bottomImage: images[i + 1])
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

        NSLog("[ImageStitcher] Stitching complete")
        return context.makeImage()
    }

    /// Fast overlap detection using sampled rows only
    private func findOverlapFast(topImage: CGImage, bottomImage: CGImage) -> Int {
        let maxSearchRange = min(150, topImage.height / 4, bottomImage.height / 4)
        let minOverlap = 20
        let matchThreshold: Float = 0.90

        guard maxSearchRange >= minOverlap else { return 0 }

        let width = topImage.width
        _ = topImage.height  // Validate image has height
        let bytesPerRow = width * 4

        // Get pixel data for just the regions we need to compare
        guard let topData = getBottomRegionPixelData(from: topImage, rows: maxSearchRange),
              let bottomData = getTopRegionPixelData(from: bottomImage, rows: maxSearchRange) else {
            return 0
        }

        // Use binary search style: check larger overlaps first, then refine
        let stepsToCheck = [maxSearchRange, maxSearchRange * 3/4, maxSearchRange / 2, maxSearchRange / 4, minOverlap]

        var bestOverlap = 0
        var bestSimilarity: Float = 0

        // Quick scan with large steps first
        for overlap in stepsToCheck where overlap >= minOverlap && overlap <= maxSearchRange {
            let similarity = calculateSimilaritySampled(
                topData: topData,
                bottomData: bottomData,
                topRegionRows: maxSearchRange,
                overlap: overlap,
                width: width,
                bytesPerRow: bytesPerRow
            )

            if similarity > matchThreshold && similarity > bestSimilarity {
                bestSimilarity = similarity
                bestOverlap = overlap
            }
        }

        // If we found a good match, refine around it
        if bestOverlap > 0 {
            let refinementRange = 10
            for offset in -refinementRange...refinementRange {
                let overlap = bestOverlap + offset
                guard overlap >= minOverlap && overlap <= maxSearchRange else { continue }

                let similarity = calculateSimilaritySampled(
                    topData: topData,
                    bottomData: bottomData,
                    topRegionRows: maxSearchRange,
                    overlap: overlap,
                    width: width,
                    bytesPerRow: bytesPerRow
                )

                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    bestOverlap = overlap
                }
            }
        }

        return bestOverlap
    }

    /// Gets pixel data from the bottom region of an image
    private func getBottomRegionPixelData(from image: CGImage, rows: Int) -> Data? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let rowsToGet = min(rows, height)
        let totalBytes = bytesPerRow * rowsToGet

        var pixelData = Data(count: totalBytes)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        // Crop to bottom region
        let cropRect = CGRect(x: 0, y: height - rowsToGet, width: width, height: rowsToGet)
        guard let croppedImage = image.cropping(to: cropRect) else { return nil }

        let success = pixelData.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: rowsToGet,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                return false
            }
            context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: width, height: rowsToGet))
            return true
        }

        return success ? pixelData : nil
    }

    /// Gets pixel data from the top region of an image
    private func getTopRegionPixelData(from image: CGImage, rows: Int) -> Data? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let rowsToGet = min(rows, height)
        let totalBytes = bytesPerRow * rowsToGet

        var pixelData = Data(count: totalBytes)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        // Crop to top region
        let cropRect = CGRect(x: 0, y: 0, width: width, height: rowsToGet)
        guard let croppedImage = image.cropping(to: cropRect) else { return nil }

        let success = pixelData.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: rowsToGet,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                return false
            }
            context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: width, height: rowsToGet))
            return true
        }

        return success ? pixelData : nil
    }

    /// Calculates similarity using sampled pixels for speed
    private func calculateSimilaritySampled(
        topData: Data,
        bottomData: Data,
        topRegionRows: Int,
        overlap: Int,
        width: Int,
        bytesPerRow: Int
    ) -> Float {
        // Top data: bottom of top image (we want the bottom `overlap` rows of topData)
        // In topData, the bottom of the original image is at the top (due to CGImage cropping)
        let topOffset = (topRegionRows - overlap) * bytesPerRow

        // Bottom data: top of bottom image (we want the top `overlap` rows)
        let bottomOffset = 0

        let compareBytes = overlap * bytesPerRow

        guard topOffset >= 0,
              topOffset + compareBytes <= topData.count,
              bottomOffset + compareBytes <= bottomData.count else {
            return 0
        }

        var matchingPixels = 0
        var totalSampled = 0

        // Sample every 8th pixel for speed
        let sampleStep = 8

        topData.withUnsafeBytes { topBuffer in
            bottomData.withUnsafeBytes { bottomBuffer in
                guard let topPtr = topBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let bottomPtr = bottomBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }

                // Sample rows and columns
                for row in stride(from: 0, to: overlap, by: 2) {
                    for col in stride(from: 0, to: width, by: sampleStep) {
                        let pixelIndex = row * width + col
                        let topPixelOffset = topOffset + pixelIndex * 4
                        let bottomPixelOffset = bottomOffset + pixelIndex * 4

                        let rDiff = abs(Int(topPtr[topPixelOffset + 1]) - Int(bottomPtr[bottomPixelOffset + 1]))
                        let gDiff = abs(Int(topPtr[topPixelOffset + 2]) - Int(bottomPtr[bottomPixelOffset + 2]))
                        let bDiff = abs(Int(topPtr[topPixelOffset + 3]) - Int(bottomPtr[bottomPixelOffset + 3]))

                        totalSampled += 1

                        // Allow small differences for anti-aliasing and compression artifacts
                        if rDiff <= 10 && gDiff <= 10 && bDiff <= 10 {
                            matchingPixels += 1
                        }
                    }
                }
            }
        }

        return totalSampled > 0 ? Float(matchingPixels) / Float(totalSampled) : 0
    }
}
