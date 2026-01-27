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
    static func save(_ image: NSImage, to directory: String, filename: String? = nil) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: directory)

        if !fileManager.fileExists(atPath: directory) {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            } catch {
                throw ExportError.failedToCreateDirectory
            }
        }

        let actualFilename = filename ?? generateFilename()
        let fileURL = directoryURL.appendingPathComponent(actualFilename).appendingPathExtension("png")

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ExportError.failedToCreateImageData
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
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

    private static func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "shotshot_\(formatter.string(from: Date()))"
    }
}
