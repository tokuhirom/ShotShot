#!/usr/bin/env swift

import AppKit
import Foundation

// MARK: - Image Stitcher (same algorithm as the app)

class ImageStitcher {
    let minOverlap = 10
    let matchThreshold: Float = 0.65

    func analyzeImages(_ images: [CGImage]) -> [(imageIndex: Int, startY: Int, endY: Int, overlap: Int, similarity: Float)] {
        var results: [(imageIndex: Int, startY: Int, endY: Int, overlap: Int, similarity: Float)] = []

        for i in 0..<images.count {
            if i == images.count - 1 {
                // Last image: use full height
                results.append((imageIndex: i, startY: 0, endY: images[i].height, overlap: 0, similarity: 0))
            } else {
                let (overlap, similarity) = findOverlap(topImage: images[i], bottomImage: images[i + 1])
                let cropHeight = images[i].height - overlap
                if cropHeight > 0 {
                    results.append((imageIndex: i, startY: 0, endY: cropHeight, overlap: overlap, similarity: similarity))
                } else {
                    // Skip this image (duplicate)
                    results.append((imageIndex: i, startY: 0, endY: 0, overlap: overlap, similarity: similarity))
                }
            }
        }

        return results
    }

    func findOverlap(topImage: CGImage, bottomImage: CGImage) -> (overlap: Int, similarity: Float) {
        // Search up to 90% of image height to handle small scrolls (large overlaps)
        let searchRange = min(topImage.height * 9 / 10, bottomImage.height * 9 / 10)

        guard searchRange >= minOverlap else { return (0, 0) }

        let width = topImage.width

        guard let topData = getPixelData(from: topImage),
              let bottomData = getPixelData(from: bottomImage) else {
            return (0, 0)
        }

        // First check: if images are nearly identical overall, treat as duplicate
        let wholeSimilarity = calculateWholeSimilarity(topData: topData, bottomData: bottomData, width: width, height: min(topImage.height, bottomImage.height))
        if wholeSimilarity > 0.90 {
            print("  -> Images are \(String(format: "%.1f", wholeSimilarity * 100))% similar overall, treating as duplicate")
            return (bottomImage.height, wholeSimilarity)
        }

        let topHeight = topImage.height
        let bottomHeight = bottomImage.height
        let bytesPerRow = width * 4

        var bestOverlap = 0
        var bestSimilarity: Float = 0

        // Coarse search
        for overlap in stride(from: searchRange, through: minOverlap, by: -5) {
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

        // Fine refinement
        if bestOverlap > 0 {
            for offset in -4...4 {
                let overlap = bestOverlap + offset
                guard overlap >= minOverlap && overlap <= searchRange else { continue }

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
            print("  -> High overlap detected, treating as duplicate")
            return (bottomImage.height, bestSimilarity)
        }

        // If we found very small overlap (<200px) with very high similarity (>90%),
        // it's likely a false match - the images are probably nearly identical with small scroll
        if bestOverlap < 200 && bestSimilarity > 0.90 {
            print("  -> Suspicious small overlap with high similarity, treating as duplicate")
            return (bottomImage.height, bestSimilarity)
        }

        return (bestOverlap, bestSimilarity)
    }

    func calculateWholeSimilarity(topData: Data, bottomData: Data, width: Int, height: Int) -> Float {
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

    func getPixelData(from image: CGImage) -> Data? {
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

    func calculateRowSimilarity(
        topData: Data,
        bottomData: Data,
        topHeight: Int,
        bottomHeight: Int,
        overlap: Int,
        width: Int,
        bytesPerRow: Int
    ) -> Float {
        let topStartRow = topHeight - overlap
        let bottomStartRow = 0

        var matchingPixels = 0
        var totalSampled = 0

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

                        let bDiff = abs(Int(topPtr[topPixelOffset]) - Int(bottomPtr[bottomPixelOffset]))
                        let gDiff = abs(Int(topPtr[topPixelOffset + 1]) - Int(bottomPtr[bottomPixelOffset + 1]))
                        let rDiff = abs(Int(topPtr[topPixelOffset + 2]) - Int(bottomPtr[bottomPixelOffset + 2]))

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

    /// Stitch just two images together for debugging
    func stitchPair(top: CGImage, bottom: CGImage, overlap: Int) -> CGImage? {
        let width = top.width
        let topCropHeight = top.height - overlap
        let totalHeight = topCropHeight > 0 ? topCropHeight + bottom.height : bottom.height

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
            return nil
        }

        // Draw bottom image first (at y=0)
        context.draw(bottom, in: CGRect(x: 0, y: 0, width: width, height: bottom.height))

        // Draw top image (cropped) above
        if topCropHeight > 0 {
            let cropRect = CGRect(x: 0, y: 0, width: top.width, height: topCropHeight)
            if let croppedTop = top.cropping(to: cropRect) {
                context.draw(croppedTop, in: CGRect(x: 0, y: bottom.height, width: width, height: topCropHeight))
            }
        }

        return context.makeImage()
    }

    func stitch(images: [CGImage], results: [(imageIndex: Int, startY: Int, endY: Int, overlap: Int, similarity: Float)]) -> CGImage? {
        guard !images.isEmpty else { return nil }

        let width = images[0].width
        var totalHeight = 0

        for result in results {
            let height = result.endY - result.startY
            if height > 0 {
                totalHeight += height
            }
        }

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
            return nil
        }

        var currentY = 0
        for result in results.reversed() {
            let image = images[result.imageIndex]
            let cropHeight = result.endY - result.startY

            if cropHeight <= 0 {
                continue
            }

            if result.imageIndex == images.count - 1 {
                // Last image: draw full
                let rect = CGRect(x: 0, y: currentY, width: width, height: image.height)
                context.draw(image, in: rect)
                currentY += image.height
            } else {
                // Crop top portion
                let cropRect = CGRect(x: 0, y: 0, width: image.width, height: cropHeight)
                guard let croppedImage = image.cropping(to: cropRect) else {
                    continue
                }
                let rect = CGRect(x: 0, y: currentY, width: width, height: cropHeight)
                context.draw(croppedImage, in: rect)
                currentY += cropHeight
            }
        }

        return context.makeImage()
    }
}

// MARK: - Main

func loadImages(from directory: String) -> [CGImage] {
    let fileManager = FileManager.default
    let dirURL = URL(fileURLWithPath: directory)

    guard let files = try? fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else {
        print("Error: Cannot read directory \(directory)")
        return []
    }

    let imageFiles = files
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    var images: [CGImage] = []
    for file in imageFiles {
        guard let imageSource = CGImageSourceCreateWithURL(file as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            print("Warning: Cannot load \(file.lastPathComponent)")
            continue
        }
        images.append(cgImage)
        print("Loaded: \(file.lastPathComponent) (\(cgImage.width)x\(cgImage.height))")
    }

    return images
}

func saveImage(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else {
        print("Error: Cannot create image destination")
        return
    }
    CGImageDestinationAddImage(destination, image, nil)
    if CGImageDestinationFinalize(destination) {
        print("Saved: \(path)")
    } else {
        print("Error: Failed to save image")
    }
}

// Parse arguments
let args = CommandLine.arguments
if args.count < 2 {
    print("""
    Usage: \(args[0]) <debug_directory> [output.png]

    Analyzes scroll capture debug images and outputs stitching plan.

    Arguments:
      debug_directory  Directory containing capture_XXX.png files
      output.png       Optional: Save stitched result to this file

    Example:
      \(args[0]) /path/to/ShotShot_Debug/scroll_2026-02-05T01-45-07Z
      \(args[0]) /path/to/ShotShot_Debug/scroll_2026-02-05T01-45-07Z result.png
    """)
    exit(1)
}

let directory = args[1]
let outputPath = args.count > 2 ? args[2] : nil

print("=== Scroll Capture Debug Tool ===\n")
print("Loading images from: \(directory)\n")

let images = loadImages(from: directory)
if images.isEmpty {
    print("Error: No images found")
    exit(1)
}

print("\n=== Analyzing overlaps ===\n")

let stitcher = ImageStitcher()
let results = stitcher.analyzeImages(images)

print("Image | Height | Use Y range  | Overlap | Similarity")
print("------|--------|--------------|---------|----------")

var totalHeight = 0
for result in results {
    let image = images[result.imageIndex]
    let useHeight = result.endY - result.startY
    let status: String

    if useHeight <= 0 {
        status = "SKIP (duplicate)"
    } else {
        totalHeight += useHeight
        status = ""
    }

    print(String(format: "%5d | %6d | %4d - %4d | %7d | %5.1f%% %@",
                 result.imageIndex + 1,
                 image.height,
                 result.startY,
                 result.endY,
                 result.overlap,
                 result.similarity * 100,
                 status))
}

print("\nTotal output height: \(totalHeight) pixels")

if let outputPath = outputPath {
    let outputDir = (outputPath as NSString).deletingLastPathComponent
    let baseName = ((outputPath as NSString).lastPathComponent as NSString).deletingPathExtension

    print("\n=== Generating pair-wise stitched images ===\n")

    // Output each pair's stitched result
    for i in 0..<(images.count - 1) {
        let pairResult = stitcher.stitchPair(top: images[i], bottom: images[i + 1], overlap: results[i].overlap)
        if let pairImage = pairResult {
            let pairPath = "\(outputDir)/\(baseName)_pair_\(String(format: "%03d", i + 1))_\(String(format: "%03d", i + 2)).png"
            saveImage(pairImage, to: pairPath)
        }
    }

    print("\n=== Generating final stitched image ===\n")
    if let stitchedImage = stitcher.stitch(images: images, results: results) {
        saveImage(stitchedImage, to: outputPath)
    } else {
        print("Error: Failed to stitch images")
    }
}

print("\nDone!")
