import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit

final class RecordingStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let onError: @Sendable (Error) -> Void
    private var sessionStarted = false

    init(
        writer: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        self.writer = writer
        self.videoInput = videoInput
        self.pixelBufferAdaptor = pixelBufferAdaptor
        self.onError = onError
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else {
            NSLog("[RecordingStreamOutput] Invalid sample buffer")
            return
        }
        guard writer.status == .writing else {
            if writer.status == .failed, let error = writer.error {
                logWriterError(prefix: "[RecordingStreamOutput] Writer failed before append", error: error)
                onError(error)
            } else {
                NSLog("[RecordingStreamOutput] Writer not in writing state: %ld", writer.status.rawValue)
            }
            return
        }

        if !sessionStarted {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
            logSampleBufferSummary(prefix: "[RecordingStreamOutput] First sample", sampleBuffer: sampleBuffer)
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            NSLog("[RecordingStreamOutput] Sample buffer does not contain an image buffer, skipping")
            return
        }

        if videoInput.isReadyForMoreMediaData {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: timestamp) {
                if let error = writer.error {
                    logWriterError(prefix: "[RecordingStreamOutput] Failed to append pixel buffer", error: error)
                    onError(error)
                } else {
                    let error = NSError(
                        domain: "RecordingStreamOutput",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to append pixel buffer with unknown writer error"]
                    )
                    NSLog("[RecordingStreamOutput] Failed to append pixel buffer: %@", error.localizedDescription)
                    onError(error)
                }
            }
        } else {
            NSLog("[RecordingStreamOutput] Video input not ready for more data")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logWriterError(prefix: "[RecordingStreamOutput] Stream stopped with error", error: error)
        onError(error)
    }

    private func logWriterError(prefix: String, error: Error) {
        let nsError = error as NSError
        NSLog("%@ (domain=%@ code=%ld): %@ userInfo=%@", prefix, nsError.domain, nsError.code, nsError.localizedDescription, nsError.userInfo as NSDictionary)
    }

    private func logSampleBufferSummary(prefix: String, sampleBuffer: CMSampleBuffer) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        var mediaSubType: FourCharCode = 0
        if let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            mediaSubType = CMFormatDescriptionGetMediaSubType(format)
        }
        let fourCC = String(format: "%c%c%c%c",
                            (mediaSubType >> 24) & 0xFF,
                            (mediaSubType >> 16) & 0xFF,
                            (mediaSubType >> 8) & 0xFF,
                            mediaSubType & 0xFF)
        NSLog("%@ pts=%@ duration=%@ mediaSubType=%@", prefix, String(describing: timestamp), String(describing: duration), fourCC)
    }
}
