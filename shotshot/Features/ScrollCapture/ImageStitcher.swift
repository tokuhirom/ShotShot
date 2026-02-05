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

        // Calculate overlaps between consecutive images
        var overlaps: [Int] = []
        for i in 0..<(images.count - 1) {
            let overlap = findOverlap(topImage: images[i], bottomImage: images[i + 1])
            overlaps.append(overlap)
            NSLog("[ImageStitcher] Overlap between image %d and %d: %d pixels", i, i + 1, overlap)
        }

        // Calculate total height (accounting for skipped duplicate images)
        let width = images[0].width
        var totalHeight = images.last!.height  // Last image is always drawn in full

        for i in 0..<(images.count - 1) {
            let cropHeight = images[i].height - overlaps[i]
            if cropHeight > 0 {
                totalHeight += cropHeight
            }
            // If cropHeight <= 0, image will be skipped, contributing 0 to height
        }

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
        // For each image except the last, we only use the TOP portion (removing overlap at bottom)
        var currentY = 0
        for i in (0..<images.count).reversed() {
            let image = images[i]

            if i == images.count - 1 {
                // Last image (bottom-most): draw full image
                let rect = CGRect(x: 0, y: currentY, width: width, height: image.height)
                context.draw(image, in: rect)
                currentY += image.height
            } else {
                // Other images: crop to remove overlapping bottom portion
                let cropHeight = image.height - overlaps[i]

                // Skip if this image is entirely overlapped (duplicate)
                if cropHeight <= 0 {
                    NSLog("[ImageStitcher] Skipping duplicate image %d (overlap >= height)", i)
                    continue
                }

                // CGImage uses top-left origin, so crop from top
                let cropRect = CGRect(x: 0, y: 0, width: image.width, height: cropHeight)
                guard let croppedImage = image.cropping(to: cropRect) else {
                    NSLog("[ImageStitcher] Failed to crop image %d", i)
                    continue
                }
                let rect = CGRect(x: 0, y: currentY, width: width, height: cropHeight)
                context.draw(croppedImage, in: rect)
                currentY += cropHeight
            }
        }

        NSLog("[ImageStitcher] Stitching complete")
        return context.makeImage()
    }

    /// Finds the overlap between two consecutive images
    private func findOverlap(topImage: CGImage, bottomImage: CGImage) -> Int {
        // Search up to 90% of image height to handle small scrolls (large overlaps)
        let maxSearchRange = min(topImage.height * 9 / 10, bottomImage.height * 9 / 10)
        let minOverlap = 10
        let matchThreshold: Float = 0.65  // Lower threshold to catch more overlaps

        guard maxSearchRange >= minOverlap else { return 0 }

        let width = topImage.width

        // Get full pixel data for both images
        guard let topData = getPixelData(from: topImage),
              let bottomData = getPixelData(from: bottomImage) else {
            NSLog("[ImageStitcher] Failed to get pixel data")
            return 0
        }

        // First check: if images are nearly identical overall, treat as duplicate
        let wholeSimilarity = calculateWholeSimilarity(topData: topData, bottomData: bottomData, width: width, height: min(topImage.height, bottomImage.height))
        if wholeSimilarity > 0.90 {
            NSLog("[ImageStitcher] Images are %.1f%% similar overall, treating as duplicate", wholeSimilarity * 100)
            return bottomImage.height
        }

        let topHeight = topImage.height
        let bottomHeight = bottomImage.height
        let bytesPerRow = width * 4

        var bestOverlap = 0
        var bestSimilarity: Float = 0

        // Check various overlap values
        // Start from larger overlaps and work down for efficiency
        for overlap in stride(from: maxSearchRange, through: minOverlap, by: -5) {
            let similarity = calculateRowSimilarity(
                topData: topData,
                bottomData: bottomData,
                topHeight: topHeight,
                bottomHeight: bottomHeight,
                overlap: overlap,
                width: width,
                bytesPerRow: bytesPerRow
            )

            if similarity > bestSimilarity {
                bestSimilarity = similarity
                if similarity > matchThreshold {
                    bestOverlap = overlap
                }
            }
        }

        // Refine around best match
        if bestOverlap > 0 {
            for offset in -4...4 {
                let overlap = bestOverlap + offset
                guard overlap >= minOverlap && overlap <= maxSearchRange else { continue }

                let similarity = calculateRowSimilarity(
                    topData: topData,
                    bottomData: bottomData,
                    topHeight: topHeight,
                    bottomHeight: bottomHeight,
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

        // If we found high overlap (>90% of height) with decent similarity, treat as full duplicate
        let heightThreshold = min(topImage.height, bottomImage.height) * 9 / 10
        if bestOverlap >= heightThreshold && bestSimilarity > 0.70 {
            NSLog("[ImageStitcher] High overlap detected (%.2f%% at %d px), treating as duplicate", bestSimilarity * 100, bestOverlap)
            return bottomImage.height
        }

        // If we found very small overlap (<200px) with very high similarity (>90%),
        // it's likely a false match - the images are probably nearly identical with small scroll
        if bestOverlap < 200 && bestSimilarity > 0.90 {
            NSLog("[ImageStitcher] Suspicious small overlap (%d px) with high similarity (%.2f%%), treating as duplicate", bestOverlap, bestSimilarity * 100)
            return bottomImage.height
        }

        NSLog("[ImageStitcher] Best similarity: %.2f%% at overlap %d", bestSimilarity * 100, bestOverlap)
        return bestOverlap
    }

    /// Calculates similarity between two whole images (for duplicate detection)
    private func calculateWholeSimilarity(image1: CGImage, image2: CGImage) -> Float {
        guard image1.width == image2.width && image1.height == image2.height else {
            return 0
        }

        guard let data1 = getPixelData(from: image1),
              let data2 = getPixelData(from: image2) else {
            return 0
        }

        let width = image1.width
        let height = image1.height
        let bytesPerRow = width * 4

        var matchingPixels = 0
        var totalSampled = 0

        // Sample pixels across the whole image
        let colStep = 8
        let rowStep = 8

        data1.withUnsafeBytes { buffer1 in
            data2.withUnsafeBytes { buffer2 in
                guard let ptr1 = buffer1.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let ptr2 = buffer2.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }

                for row in stride(from: 0, to: height, by: rowStep) {
                    for col in stride(from: 0, to: width, by: colStep) {
                        let offset = row * bytesPerRow + col * 4

                        let bDiff = abs(Int(ptr1[offset]) - Int(ptr2[offset]))
                        let gDiff = abs(Int(ptr1[offset + 1]) - Int(ptr2[offset + 1]))
                        let rDiff = abs(Int(ptr1[offset + 2]) - Int(ptr2[offset + 2]))

                        totalSampled += 1

                        if bDiff <= 25 && gDiff <= 25 && rDiff <= 25 {
                            matchingPixels += 1
                        }
                    }
                }
            }
        }

        return totalSampled > 0 ? Float(matchingPixels) / Float(totalSampled) : 0
    }

    /// Calculates whole-image similarity using pre-loaded pixel data
    private func calculateWholeSimilarity(topData: Data, bottomData: Data, width: Int, height: Int) -> Float {
        let bytesPerRow = width * 4
        var matchingPixels = 0
        var totalSampled = 0

        let colStep = 8
        let rowStep = 8

        topData.withUnsafeBytes { buffer1 in
            bottomData.withUnsafeBytes { buffer2 in
                guard let ptr1 = buffer1.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let ptr2 = buffer2.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }

                for row in stride(from: 0, to: height, by: rowStep) {
                    for col in stride(from: 0, to: width, by: colStep) {
                        let offset = row * bytesPerRow + col * 4

                        let bDiff = abs(Int(ptr1[offset]) - Int(ptr2[offset]))
                        let gDiff = abs(Int(ptr1[offset + 1]) - Int(ptr2[offset + 1]))
                        let rDiff = abs(Int(ptr1[offset + 2]) - Int(ptr2[offset + 2]))

                        totalSampled += 1

                        if bDiff <= 25 && gDiff <= 25 && rDiff <= 25 {
                            matchingPixels += 1
                        }
                    }
                }
            }
        }

        return totalSampled > 0 ? Float(matchingPixels) / Float(totalSampled) : 0
    }

    /// Gets raw pixel data from a CGImage
    /// Note: CGContext default origin is bottom-left, CGImage origin is top-left.
    /// When drawing CGImage into CGContext without transforms:
    /// - Image's top-left goes to context's bottom-left
    /// - So buffer row 0 = TOP of the image visually
    /// - Buffer row (height-1) = BOTTOM of the image visually
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
            // No Y-flip: row 0 in buffer = top of image
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return success ? pixelData : nil
    }

    /// Calculates similarity between overlapping regions
    /// Memory layout (no Y-flip):
    /// - Row 0 in data = top of image
    /// - Row (height-1) in data = bottom of image
    /// We compare: bottom of topImage with top of bottomImage
    private func calculateRowSimilarity(
        topData: Data,
        bottomData: Data,
        topHeight: Int,
        bottomHeight: Int,
        overlap: Int,
        width: Int,
        bytesPerRow: Int
    ) -> Float {
        // Compare:
        // - Bottom `overlap` rows of topImage (rows from topHeight-overlap to topHeight-1)
        // - Top `overlap` rows of bottomImage (rows from 0 to overlap-1)

        let topStartRow = topHeight - overlap
        let bottomStartRow = 0

        var matchingPixels = 0
        var totalSampled = 0

        // Sample every 4th pixel horizontally and every 2nd row for speed
        let colStep = 4
        let rowStep = 2

        topData.withUnsafeBytes { topBuffer in
            bottomData.withUnsafeBytes { bottomBuffer in
                guard let topPtr = topBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let bottomPtr = bottomBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }

                for rowOffset in stride(from: 0, to: overlap, by: rowStep) {
                    let topRow = topStartRow + rowOffset
                    let bottomRow = bottomStartRow + rowOffset

                    for col in stride(from: 0, to: width, by: colStep) {
                        let topPixelOffset = topRow * bytesPerRow + col * 4
                        let bottomPixelOffset = bottomRow * bytesPerRow + col * 4

                        // BGRA format: B at +0, G at +1, R at +2, A at +3
                        let bDiff = abs(Int(topPtr[topPixelOffset]) - Int(bottomPtr[bottomPixelOffset]))
                        let gDiff = abs(Int(topPtr[topPixelOffset + 1]) - Int(bottomPtr[bottomPixelOffset + 1]))
                        let rDiff = abs(Int(topPtr[topPixelOffset + 2]) - Int(bottomPtr[bottomPixelOffset + 2]))

                        totalSampled += 1

                        // Allow differences for compression artifacts and scroll blur
                        if bDiff <= 25 && gDiff <= 25 && rDiff <= 25 {
                            matchingPixels += 1
                        }
                    }
                }
            }
        }

        return totalSampled > 0 ? Float(matchingPixels) / Float(totalSampled) : 0
    }
}
