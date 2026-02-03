@preconcurrency import AVFoundation
import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

enum RecordingError: LocalizedError {
    case alreadyRecording
    case noDisplay
    case writerSetupFailed(String)
    case streamFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "すでに録画中です"
        case .noDisplay:
            return "ディスプレイが見つかりません"
        case .writerSetupFailed(let msg):
            return "録画の準備に失敗しました: \(msg)"
        case .streamFailed(let msg):
            return "録画エラー: \(msg)"
        }
    }
}

@MainActor
final class RecordingManager: NSObject {
    private var stream: SCStream?
    private var streamOutput: RecordingStreamOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private(set) var isRecording = false
    private var indicatorWindow: RecordingIndicatorWindow?
    private var stopContinuation: CheckedContinuation<URL, Error>?
    private var tempFileURL: URL?

    var recording: Bool { isRecording }

    func startRecording(selection: CaptureSelection) async throws -> URL {
        guard !isRecording else { throw RecordingError.alreadyRecording }

        isRecording = true
        NSLog("[RecordingManager] Starting recording for rect: %@", String(describing: selection.rect))

        do {
            let url = try await beginRecording(selection: selection)
            return url
        } catch {
            await cleanupOnError()
            throw error
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        NSLog("[RecordingManager] Stopping recording...")

        Task { @MainActor in
            await finalizeRecording()
        }
    }

    // MARK: - Private

    private func beginRecording(selection: CaptureSelection) async throws -> URL {
        // Prepare temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        self.tempFileURL = tempURL

        // AVAssetWriter configuration (use logical size, not physical pixels)
        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)

        let videoWidth = Int(selection.rect.width)
        let videoHeight = Int(selection.rect.height)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
        ]

        // Create format hint for BGRA input
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(videoWidth),
            height: Int32(videoHeight),
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings, sourceFormatHint: formatDescription)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RecordingError.writerSetupFailed("Cannot add video input to writer")
        }
        writer.add(input)

        self.assetWriter = writer
        self.videoInput = input

        writer.startWriting()

        // Show indicator first so we can exclude it from recording
        showIndicator(for: selection)

        // SCStream configuration
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw RecordingError.noDisplay
        }

        // Find indicator window to exclude from recording
        var excludedWindows: [SCWindow] = []
        if let indicatorWindowNumber = indicatorWindow?.window.windowNumber {
            if let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(indicatorWindowNumber) }) {
                excludedWindows.append(scWindow)
                NSLog("[RecordingManager] Excluding indicator window %d from recording", indicatorWindowNumber)
            }
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let config = SCStreamConfiguration()
        config.sourceRect = selection.rect
        config.width = videoWidth
        config.height = videoHeight
        config.scalesToFit = false
        config.showsCursor = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30fps
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)

        let output = RecordingStreamOutput(writer: writer, videoInput: input) { [weak self] error in
            NSLog("[RecordingManager] Stream output error: %@", error.localizedDescription)
            Task { @MainActor in
                self?.handleStreamError(error)
            }
        }

        try scStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.shotshot.recording", qos: .userInitiated))

        self.stream = scStream
        self.streamOutput = output

        // Start capture
        try await scStream.startCapture()
        NSLog("[RecordingManager] SCStream capture started")

        // Wait for stop
        let resultURL: URL = try await withCheckedThrowingContinuation { continuation in
            self.stopContinuation = continuation
        }

        return resultURL
    }

    private func finalizeRecording() async {
        guard isRecording else { return }
        isRecording = false

        // Close indicator
        indicatorWindow?.close()
        indicatorWindow = nil

        // Stop SCStream
        if let stream = stream {
            do {
                try await stream.stopCapture()
                NSLog("[RecordingManager] SCStream capture stopped")
            } catch {
                NSLog("[RecordingManager] Error stopping stream: %@", error.localizedDescription)
            }
        }
        stream = nil
        streamOutput = nil

        // AVAssetWriter finalize
        if let writer = assetWriter, writer.status == .writing {
            videoInput?.markAsFinished()
            await writer.finishWriting()
            NSLog("[RecordingManager] AVAssetWriter finalized, status: %d", writer.status.rawValue)

            if writer.status == .completed, let url = tempFileURL {
                stopContinuation?.resume(returning: url)
            } else {
                let error = writer.error ?? RecordingError.writerSetupFailed("Writer finalization failed")
                stopContinuation?.resume(throwing: error)
            }
        } else {
            let error = RecordingError.writerSetupFailed("Writer not in writing state")
            stopContinuation?.resume(throwing: error)
        }

        stopContinuation = nil
        assetWriter = nil
        videoInput = nil
        tempFileURL = nil
    }

    private func cleanupOnError() async {
        isRecording = false

        indicatorWindow?.close()
        indicatorWindow = nil

        if let stream = stream {
            try? await stream.stopCapture()
        }
        stream = nil
        streamOutput = nil

        if let writer = assetWriter, writer.status == .writing {
            videoInput?.markAsFinished()
            writer.cancelWriting()
        }
        assetWriter = nil
        videoInput = nil

        // Remove temp file
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURL = nil
        stopContinuation = nil
    }

    private func showIndicator(for selection: CaptureSelection) {
        // Convert selection area to screen coordinates
        guard let screen = NSScreen.screens.first(where: { $0.displayID == selection.displayID }) ?? NSScreen.main else {
            return
        }

        // CaptureSelection.rect is in screen coordinates (top-left origin),
        // so convert to NSWindow coordinates (bottom-left origin)
        let screenFrame = screen.frame
        let selectionInScreen = NSRect(
            x: screenFrame.origin.x + selection.rect.origin.x,
            y: screenFrame.origin.y + screenFrame.height - selection.rect.origin.y - selection.rect.height,
            width: selection.rect.width,
            height: selection.rect.height
        )

        let indicator = RecordingIndicatorWindow(selectionRect: selectionInScreen)
        indicator.onStop = { [weak self] in
            self?.stopRecording()
        }
        indicator.makeKeyAndOrderFront()
        indicatorWindow = indicator
    }

    private func handleStreamError(_ error: Error) {
        guard isRecording else { return }
        NSLog("[RecordingManager] Handling stream error, stopping recording")
        stopRecording()
    }
}
