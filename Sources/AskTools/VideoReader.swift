internal import AVFoundation
internal import AskAI
internal import AskAgentCore
internal import CoreGraphics
internal import Foundation

/// Shows frames of a video as images (roadmap 0084).
///
/// Which frames is up to the caller: explicit times, a count spread over the video or a window of it, or one every so
/// many seconds, never more than a limit at once. AVFoundation decodes and scales each frame; sampled frames may come
/// from the nearest keyframe (4–15× faster, measured in diary 2026-10-28-06), explicit times are exact.
enum VideoReader {
    /// What the model asked for. Seconds throughout.
    struct Request: Equatable {
        var at: [Double]?
        var count: Int?
        var every: Double?
        var start: Double?
        var end: Double?
        var maximumImages: Int

        init(
            at: [Double]? = nil, count: Int? = nil, every: Double? = nil, start: Double? = nil, end: Double? = nil,
            maximumImages: Int
        ) {
            self.at = at
            self.count = count
            self.every = every
            self.start = start
            self.end = end
            self.maximumImages = maximumImages
        }
    }

    /// Brands of an ISO base media file that are still pictures, not video.
    private static let pictureBrands: Set<String> = [
        "avif", "avis", "heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1"
    ]

    /// Whether the first bytes are an MP4, MOV or M4V file (an ISO base media file that is not a picture).
    static func looksLikeVideo(_ header: [UInt8]) -> Bool {
        guard header.count >= 12, Array(header[4 ..< 8]) == Array("ftyp".utf8) else { return false }
        return !pictureBrands.contains(String(decoding: header[8 ..< 12], as: UTF8.self))
    }

    /// The times to take frames at, and how many the request would have given before the limit cut it.
    static func times(duration: Double, _ request: Request) -> (times: [Double], wanted: Int) {
        let last = max(0, duration - 0.05)  // a frame exactly at the end often does not exist
        if let at = request.at, !at.isEmpty {
            let clamped = at.map { min(max(0, $0), last) }
            return (Array(clamped.prefix(request.maximumImages)), clamped.count)
        }
        let start = min(max(0, request.start ?? 0), last)
        let end = min(max(start, request.end ?? duration), duration)
        if let every = request.every, every > 0 {
            let step = max(0.04, every)
            let wanted = Int(((end - start) / step).rounded(.down)) + 1
            let times = (0 ..< min(wanted, request.maximumImages)).map { min(start + Double($0) * step, last) }
            return (times, wanted)
        }
        let count = max(1, request.count ?? 4)
        // The middle of each of `count` equal parts, so the first frame is not the (often black) very first one.
        let times = (0 ..< min(count, request.maximumImages))
            .map {
                min(start + (end - start) * (Double($0) + 0.5) / Double(count), last)
            }
        return (times, count)
    }

    static func read(_ url: URL, path: String, _ request: Request) async throws(ToolFailure) -> ToolOutput {
        let asset = AVURLAsset(url: url)
        let duration: Double
        let size: CGSize
        do {
            duration = try await asset.load(.duration).seconds
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw ToolFailure("\(path) has no video track.")
            }
            size = try await track.load(.naturalSize)
        } catch let failure as ToolFailure {
            throw failure
        } catch {
            throw ToolFailure("\(path) looks like a video but could not be opened.")
        }
        guard duration.isFinite, duration > 0 else { throw ToolFailure("\(path) is a video with no length.") }

        let (times, wanted) = times(duration: duration, request)
        let exact = request.at != nil
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: ImageReader.maximumSide, height: ImageReader.maximumSide)
        let tolerance = exact ? CMTime.zero : CMTime.positiveInfinity
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var images: [ImagePart] = []
        var shownAt: [Double] = []
        for await result in generator.images(for: times.map { CMTime(seconds: $0, preferredTimescale: 600) }) {
            guard case .success(_, let frame, let actual) = result else { continue }
            guard
                let fitted = try? ImageReader.fit(
                    favoursPNG: false, longSide: max(frame.width, frame.height),
                    render: { ImageReader.scaled(frame, toLongSide: $0) })
            else { continue }
            images.append(fitted.part)
            shownAt.append(actual.seconds)
        }
        guard !images.isEmpty else { throw ToolFailure("\(path): no frame could be read at the times asked for.") }

        let stamps = shownAt.map { String(format: "%.1f s", $0) }.joined(separator: ", ")
        var line = "\(path): video \(Int(size.width))×\(Int(size.height)), \(String(format: "%.1f", duration)) s; "
        line += "\(images.count) frame\(images.count == 1 ? "" : "s") at \(stamps)"
        if wanted > times.count {
            line += "; \(wanted - times.count) more asked for but over the limit of \(request.maximumImages) images"
        }
        if images.count < times.count { line += "; \(times.count - images.count) could not be read" }
        var output = ToolOutput(line)
        output.images = images
        return output
    }
}
