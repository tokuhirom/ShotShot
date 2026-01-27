import AppKit
import Foundation
import UniformTypeIdentifiers

enum ExportError: LocalizedError {
    case failedToCreateDirectory
    case failedToCreateImageData
    case failedToWriteFile

    var errorDescription: String? {
        switch self {
        case .failedToCreateDirectory:
            return "保存先フォルダの作成に失敗しました"
        case .failedToCreateImageData:
            return "画像データの作成に失敗しました"
        case .failedToWriteFile:
            return "ファイルの書き込みに失敗しました"
        }
    }
}

struct ImageExporter {
    static func save(_ screenshot: Screenshot, to directory: String, filename: String? = nil) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: directory)

        print("[ImageExporter] Saving to directory: \(directory)")
        print("[ImageExporter] Directory exists: \(fileManager.fileExists(atPath: directory))")

        if !fileManager.fileExists(atPath: directory) {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                print("[ImageExporter] Created directory: \(directory)")
            } catch {
                print("[ImageExporter] Failed to create directory: \(error)")
                throw ExportError.failedToCreateDirectory
            }
        }

        let baseName = filename ?? generateFilename()
        let scaleSuffix = screenshot.isRetina ? "@2x" : ""
        let fullFilename = "\(baseName)\(scaleSuffix)"
        let fileURL = directoryURL.appendingPathComponent(fullFilename).appendingPathExtension("png")

        guard let cgImage = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ExportError.failedToCreateImageData
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        bitmapRep.size = screenshot.image.size

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw ExportError.failedToCreateImageData
        }

        do {
            try pngData.write(to: fileURL)
        } catch {
            throw ExportError.failedToWriteFile
        }

        return fileURL
    }

    static func save(_ image: NSImage, to directory: String, filename: String? = nil) throws -> URL {
        let screenshot = Screenshot(image: image, scaleFactor: 1.0)
        return try save(screenshot, to: directory, filename: filename)
    }

    private static func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "ShotShot_\(formatter.string(from: Date()))"
    }
}
