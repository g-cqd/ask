import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Appends 30 frames, each a different grey, as the writer accepts them.
// SAFETY: the writer calls `feed` on one serial queue, one call after another, and nothing else touches the state.
final class VideoFeeder: @unchecked Sendable {
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var frame = 0
    private var finished = false

    init(input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
        self.input = input
        self.adaptor = adaptor
    }

    func feed(_ done: CheckedContinuation<Void, Never>) {
        while input.isReadyForMoreMediaData, frame < 30 {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32ARGB, nil, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(frame * 8), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
            frame += 1
        }
        if frame == 30, !finished {
            finished = true
            input.markAsFinished()
            done.resume()
        }
    }
}
