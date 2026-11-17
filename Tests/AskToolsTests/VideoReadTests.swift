import AVFoundation
import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// `read` on a video (roadmap 0084): frames at the times asked for, a bounded number at a time.
@Suite("read shows frames of a video: spread over it or a window of it, at a period, or at exact times")
struct VideoReadTests {
    private let root: URL
    private let context: ToolContext

    init() throws {
        // The real location, as the sandbox compares real locations: /var is a link to /private/var.
        root = URL(fileURLWithPath: CanonicalPath.of(NSTemporaryDirectory(), relativeTo: "/") ?? NSTemporaryDirectory())
            .appending(path: "ask-video-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        context = ToolContext(workingDirectory: root.path)
    }

    /// A 3-second, 10 frames per second MP4 whose frames change colour.
    private func video(_ name: String) async throws -> URL {
        let url = root.appending(path: name)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        // The writer says when it can take more frames; no waiting by time.
        let feeder = VideoFeeder(input: input, adaptor: adaptor)
        await withCheckedContinuation { done in
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "ask.media.test")) { feeder.feed(done) }
        }
        await writer.finishWriting()
        try #require(writer.status == .completed)
        return url
    }

    private func read(_ name: String, _ extra: String) async throws -> ToolOutput {
        let input = try JSONObject(validating: Array(#"{"path":"\#(name)"\#(extra)}"#.utf8))
        return await ReadTool().run(input, in: context)
    }

    @Test func `a video gives evenly spread frames by default, and exact frames at the times asked for`() async throws {
        _ = try await video("v.mp4")
        let spread = try await read("v.mp4", "")
        #expect(!spread.isError, "\(spread.content)")
        #expect(spread.images.count == 4 && spread.content.contains("64×48") && spread.content.contains("3.0 s"))
        let exact = try await read("v.mp4", #","at":[0.5,1.5]"#)
        #expect(exact.images.count == 2 && exact.content.contains("0.5 s, 1.5 s"))
        let every = try await read("v.mp4", #","every":1,"start":1,"max_images":2"#)
        #expect(every.images.count == 2 && every.content.contains("1 more asked for"))
    }

    /// ADR-0164: `count: 12` beside a limit of 8 gave the first eight of twelve parts, two thirds of the video. One number now.
    @Test func `max_images is how many frames a video gives, and count, its old name, is not dropped`() async throws {
        _ = try await video("v.mp4")
        let twelve = try await read("v.mp4", #","max_images":12"#)
        #expect(twelve.images.count == 12 && !twelve.content.contains("more asked for"), "\(twelve.content)")
        #expect(try await read("v.mp4", #","max_images":1"#).images.count == 1)
        #expect(try await read("v.mp4", #","max_images":99"#).images.count == 20, "at most twenty")
        let counted = try await read("v.mp4", #","count":12"#)
        #expect(counted.images.count == 12 && !counted.content.contains("more asked for"), "\(counted.content)")
        #expect(try await read("v.mp4", #","count":12,"max_images":2"#).images.count == 2, "the name that is told wins")
        let listed = try await read("v.mp4", #","at":[0.5,1,1.5],"max_images":2"#)
        #expect(
            listed.images.count == 2 && listed.content.contains("1 more asked for"),
            "it still limits what is listed"
        )
    }

    /// The seconds a read says its frames are at: "… 3 frames at 1.0 s, 1.5 s, 2.0 s".
    private func stamps(_ output: ToolOutput) -> [Double] {
        let line = output.content.split(separator: ";").first { $0.contains(" at ") } ?? ""
        return line.split(separator: " ").compactMap { Double($0) }.dropFirst().map(\.self)
    }

    /// Found with a real model on a video cut by ffmpeg (diary 2026-11-17-01): six frames asked of 1 s to 2 s came back as one
    /// frame six times, the key frame at 2.0 s, which is not in the window. Any frame near was allowed; now each part gives its own.
    @Test func `frames spread over a window are each from its own part of it, and a period gives its exact times`()
        async throws
    {
        _ = try await video("v.mp4")
        let window = stamps(try await read("v.mp4", #","start":1,"end":2,"max_images":4"#))
        #expect(window.count == 4 && window == window.sorted() && Set(window).count == 4, "\(window)")
        #expect(window.allSatisfy { $0 >= 1 && $0 < 2 }, "\(window)")
        let whole = stamps(try await read("v.mp4", ""))
        #expect(
            Set(whole).count == 4 && zip([0, 0.75, 1.5, 2.25], whole).allSatisfy { $0 <= $1 && $1 < $0 + 0.75 },
            "\(whole)"
        )
        #expect(stamps(try await read("v.mp4", #","every":0.5,"start":1,"end":2"#)) == [1, 1.5, 2])
    }

    @Test func `under a restricted sandbox a video is read from a verified copy, and a protected one is refused`()
        async throws
    {
        _ = try await video("v.mp4")
        let secret = root.appending(path: "secret")
        try FileManager.default.createDirectory(at: secret, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appending(path: "v.mp4"), to: secret.appending(path: "v.mp4"))
        let restricted = ToolContext(
            workingDirectory: root.path,
            sandbox: SandboxPolicy(denyRead: [SandboxRule(secret.path, .subpath)])
        )
        let allowed = await ReadTool().run(try JSONObject(validating: Array(#"{"path":"v.mp4"}"#.utf8)), in: restricted)
        #expect(!allowed.isError && allowed.images.count == 4, "\(allowed.content)")
        let denied = await ReadTool()
            .run(
                try JSONObject(validating: Array(#"{"path":"secret/v.mp4"}"#.utf8)),
                in: restricted
            )
        #expect(denied.isError && denied.images.isEmpty, "\(denied.content) \(denied.images.count)")
        let temporary = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        #expect(!temporary.contains { $0.hasPrefix("ask-read-") })
    }

    @Test func `frame times follow count, window, period, explicit times and the limit`() {
        func plan(_ request: VideoReader.Request) -> (times: [Double], wanted: Int) {
            VideoReader.times(duration: 10, request)
        }
        let base = VideoReader.Request(maximumImages: 8)
        #expect(plan(.init(count: 2, maximumImages: 8)).times == [2.5, 7.5])
        #expect(plan(.init(count: 2, start: 4, end: 6, maximumImages: 8)).times == [4.5, 5.5])
        #expect(plan(.init(every: 4, maximumImages: 8)).times == [0, 4, 8])
        #expect(plan(.init(every: 1, maximumImages: 3)).times == [0, 1, 2])
        #expect(plan(.init(every: 1, maximumImages: 3)).wanted == 11)
        #expect(plan(.init(at: [1, 99, -2], maximumImages: 8)).times == [1, 9.95, 0])
        #expect(plan(base).times.count == 4)
        // What the two numbers did when a call gave one (ADR-0164): eight of twelve parts, and nothing of the last third.
        #expect(plan(.init(count: 12, maximumImages: 8)).times.last == 6.25)
        #expect((plan(.init(count: 12, maximumImages: 12)).times.last ?? 0) > 9.5)
    }

    /// A file says how long it is, up to Int64 seconds: one frame every 0.04 s of that is past `Int.max`, which must not stop ask.
    @Test func `a video that claims an enormous length is planned, not trapped on`() {
        let planned = VideoReader.times(duration: 9e18, VideoReader.Request(every: 0.04, maximumImages: 8))
        #expect(planned.times.count == 8)
        #expect(planned.wanted == Int.max)
    }

    @Test func `the sniffer tells video from pictures that share the ISO container`() {
        let mp4 = Array("\0\0\0\u{18}ftypmp42".utf8)
        let avif = Array("\0\0\0\u{18}ftypavif".utf8)
        #expect(VideoReader.looksLikeVideo(mp4) && !VideoReader.looksLikeVideo(avif))
        #expect(ImageReader.mediaType(of: avif) == "image/avif" && ImageReader.mediaType(of: mp4) == nil)
    }
}
