import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit

final class RecordingStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let onError: @Sendable (Error) -> Void
    private var sessionStarted = false

    init(writer: AVAssetWriter, videoInput: AVAssetWriterInput, onError: @escaping @Sendable (Error) -> Void) {
        self.writer = writer
        self.videoInput = videoInput
        self.onError = onError
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }
        guard writer.status == .writing else { return }

        if !sessionStarted {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        if videoInput.isReadyForMoreMediaData {
            if !videoInput.append(sampleBuffer) {
                if let error = writer.error {
                    NSLog("[RecordingStreamOutput] Failed to append sample buffer: %@", error.localizedDescription)
                    onError(error)
                }
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[RecordingStreamOutput] Stream stopped with error: %@", error.localizedDescription)
        onError(error)
    }
}
