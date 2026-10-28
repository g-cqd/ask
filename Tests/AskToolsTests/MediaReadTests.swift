import AVFoundation
import AskAI
import AskAgentCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AskTools

/// `read` on formats beyond the four a provider takes, on PDFs, and on video (roadmap 0084).
@Suite("read shows other image formats, PDF pages and video frames, a bounded number at a time")
struct MediaReadTests {
    private let root: URL
    private let context: ToolContext

    init() throws {
        // The real location, as the sandbox compares real locations: /var is a link to /private/var.
        root = URL(fileURLWithPath: CanonicalPath.of(NSTemporaryDirectory(), relativeTo: "/") ?? NSTemporaryDirectory())
            .appending(path: "ask-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        context = ToolContext(workingDirectory: root.path)
    }

    private func picture(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func encoded(_ type: UTType, _ width: Int = 64, _ height: Int = 48) -> Data {
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, picture(width, height), nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func run(_ name: String, _ data: Data, _ extra: String = "") async throws -> ToolOutput {
        try data.write(to: root.appending(path: name))
        let input = try JSONObject(validating: Array(#"{"path":"\#(name)"\#(extra)}"#.utf8))
        return await ReadTool().run(input, in: context)
    }

    // MARK: - formats

    @Test(arguments: [UTType.bmp, .tiff, .heic, UTType(filenameExtension: "avif")!])
    func `a format no provider takes is decoded and sent as PNG or JPEG`(type: UTType) async throws {
        let output = try await run("a.bin", encoded(type))
        #expect(!output.isError, "\(output.content)")
        let media = try #require(output.images.first?.mediaType)
        #expect(media == "image/png" || media == "image/jpeg")
    }

    @Test func `a GIF becomes a still image`() async throws {
        let output = try await run("a.gif", encoded(.gif))
        #expect(output.images.count == 1 && !output.isError)
    }

    // MARK: - PDF

    private func pdf(pages: Int) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let consumer = CGDataConsumer(data: data)!
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for page in 1 ... pages {
            context.beginPDFPage(nil)
            context.setFillColor(red: CGFloat(page) / CGFloat(pages), green: 0.4, blue: 0.6, alpha: 1)
            context.fill(CGRect(x: 20, y: 20, width: 100, height: 100))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    @Test func `a PDF gives its first pages as images and says how to see the rest`() async throws {
        let output = try await run("d.pdf", pdf(pages: 12))
        #expect(output.images.count == 8)
        #expect(output.content.contains("12 pages") && output.content.contains("pass pages"))
    }

    @Test func `pages chooses pages, and max_images bounds how many come back`() async throws {
        let some = try await run("d.pdf", pdf(pages: 12), #","pages":"2,5-6""#)
        #expect(some.images.count == 3 && some.content.contains("pages 2, 5, 6"))
        let capped = try await run("d.pdf", pdf(pages: 12), #","pages":"1-10","max_images":2"#)
        #expect(capped.images.count == 2 && capped.content.contains("8 more asked for,"))
        let past = try await run("d.pdf", pdf(pages: 3), #","pages":"9""#)
        #expect(past.isError && past.content.contains("past the end"))
    }

    @Test func `page specs parse strictly`() {
        #expect(PDFReader.pages("1-3,7,2") == [1, 2, 3, 7])
        #expect(PDFReader.pages("0") == nil && PDFReader.pages("3-1") == nil && PDFReader.pages("a") == nil)
        #expect(PDFReader.pages("") == nil && PDFReader.pages("1,,2") == nil)
    }

    // MARK: - video

    /// A 3-second, 10 frames per second MP4 whose frames change colour.
    private func video(_ name: String) async throws -> URL {
        let url = root.appending(path: name)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48
            ])
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

    @Test func `under a restricted sandbox a video is read from a verified copy, and a protected one is refused`()
        async throws
    {
        _ = try await video("v.mp4")
        let secret = root.appending(path: "secret")
        try FileManager.default.createDirectory(at: secret, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appending(path: "v.mp4"), to: secret.appending(path: "v.mp4"))
        let restricted = ToolContext(
            workingDirectory: root.path,
            sandbox: SandboxPolicy(denyRead: [SandboxRule(secret.path, .subpath)]))
        let allowed = await ReadTool().run(try JSONObject(validating: Array(#"{"path":"v.mp4"}"#.utf8)), in: restricted)
        #expect(!allowed.isError && allowed.images.count == 4, "\(allowed.content)")
        let denied = await ReadTool()
            .run(
                try JSONObject(validating: Array(#"{"path":"secret/v.mp4"}"#.utf8)), in: restricted)
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
    }

    @Test func `the sniffer tells video from pictures that share the ISO container`() {
        let mp4 = Array("\0\0\0\u{18}ftypmp42".utf8)
        let avif = Array("\0\0\0\u{18}ftypavif".utf8)
        #expect(VideoReader.looksLikeVideo(mp4) && !VideoReader.looksLikeVideo(avif))
        #expect(ImageReader.mediaType(of: avif) == "image/avif" && ImageReader.mediaType(of: mp4) == nil)
    }
}
