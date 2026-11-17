import AskAI
import AskAgentCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AskTools

/// `read` on formats beyond the four a provider takes, and on PDFs (roadmap 0084). Video is in `VideoReadTests`.
@Suite("read shows other image formats and PDF pages, a bounded number at a time")
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
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
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

    /// The spec is the model's, so it is bounded as a whole: many wide ranges would otherwise build millions of pages, checked for
    /// repeats one by one, before a single page is read.
    @Test func `a page spec names at most ten thousand pages in all`() {
        #expect(PDFReader.pages("1-9999,10000-19998,20000-29998") == nil)
        #expect(PDFReader.pages("1-5000,1-5000,5001-10000")?.count == 10_000, "repeats count once")
    }
}
