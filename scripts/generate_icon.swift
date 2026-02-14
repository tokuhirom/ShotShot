#!/usr/bin/env swift

import AppKit
import Foundation

// Generate app icons from SF Symbol
func generateIcon(symbolName: String, size: CGSize, scale: CGFloat, outputPath: String) {
    let pointSize = size.width * 0.7 // Icon takes up 70% of canvas
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)

    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        print("Failed to create symbol image")
        return
    }

    let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)

    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixelSize.width),
        pixelsHigh: Int(pixelSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("Failed to create bitmap")
        return
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)

    // Draw with accent color (blue)
    let accentColor = NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
    accentColor.set()

    // Center the symbol
    let symbolRect = CGRect(
        x: (pixelSize.width - pointSize * scale) / 2,
        y: (pixelSize.height - pointSize * scale) / 2,
        width: pointSize * scale,
        height: pointSize * scale
    )

    symbol.draw(in: symbolRect)

    NSGraphicsContext.restoreGraphicsState()

    // Save PNG
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data")
        return
    }

    try? pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Generated: \(outputPath)")
}

// Icon sizes needed for macOS app
let iconSizes: [(size: CGSize, scale: CGFloat, filename: String)] = [
    (CGSize(width: 16, height: 16), 1.0, "icon_16x16.png"),
    (CGSize(width: 16, height: 16), 2.0, "icon_16x16@2x.png"),
    (CGSize(width: 32, height: 32), 1.0, "icon_32x32.png"),
    (CGSize(width: 32, height: 32), 2.0, "icon_32x32@2x.png"),
    (CGSize(width: 128, height: 128), 1.0, "icon_128x128.png"),
    (CGSize(width: 128, height: 128), 2.0, "icon_128x128@2x.png"),
    (CGSize(width: 256, height: 256), 1.0, "icon_256x256.png"),
    (CGSize(width: 256, height: 256), 2.0, "icon_256x256@2x.png"),
    (CGSize(width: 512, height: 512), 1.0, "icon_512x512.png"),
    (CGSize(width: 512, height: 512), 2.0, "icon_512x512@2x.png"),
]

let basePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let outputDir = "\(basePath)/shotshot/Resources/Assets.xcassets/AppIcon.appiconset"

for icon in iconSizes {
    let outputPath = "\(outputDir)/\(icon.filename)"
    generateIcon(
        symbolName: "camera.viewfinder",
        size: icon.size,
        scale: icon.scale,
        outputPath: outputPath
    )
}

print("\n✓ All icons generated successfully!")
