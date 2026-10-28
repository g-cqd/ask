import AskAI
import AskAgentCore
import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import AskTools

/// A PDF page with a text layer is read as text and one without as a picture (roadmap 0084).
@Suite("read gives the text of a PDF page that has some, and a picture of one that has none")
struct PDFTextTests {
    private let root: URL
    private let context: ToolContext

    init() throws {
        root = URL(fileURLWithPath: CanonicalPath.of(NSTemporaryDirectory(), relativeTo: "/") ?? NSTemporaryDirectory())
            .appending(path: "ask-pdftext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        context = ToolContext(workingDirectory: root.path)
    }

    /// A PDF whose pages say `texts`; an empty text leaves the page a drawing only.
    private func pdf(_ texts: [String]) throws -> URL {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 900, height: 300)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        for text in texts {
            context.beginPDFPage(nil)
            context.setFillColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
            context.fill(CGRect(x: 20, y: 20, width: 60, height: 60))
            if !text.isEmpty {
                let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(
                        string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                context.textPosition = CGPoint(x: 20, y: 200)
                CTLineDraw(line, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        let url = root.appending(path: "d.pdf")
        try (data as Data).write(to: url)
        return url
    }

    private func read(_ extra: String = "") async throws -> ToolOutput {
        await ReadTool().run(try JSONObject(validating: Array(#"{"path":"d.pdf"\#(extra)}"#.utf8)), in: context)
    }

    private let sentence = "The quick brown fox jumps over the lazy dog while the committee reads the annual report."

    @Test func `a page with text is text, and a page without is a picture`() async throws {
        _ = try pdf([sentence, "", sentence + " Second page."])
        let output = try await read()
        #expect(!output.isError, "\(output.content)")
        #expect(output.images.count == 1)
        #expect(output.content.contains("text of pages 1, 3") && output.content.contains("page 2"))
        #expect(output.content.contains("[page 1]\n" + sentence) && output.content.contains("Second page."))
        #expect(output.content.contains("render: true"))
    }

    @Test func `render gives a picture of every page, text or not`() async throws {
        _ = try pdf([sentence, sentence])
        let output = try await read(#","render":true"#)
        #expect(output.images.count == 2 && !output.content.contains("[page 1]"))
    }

    @Test func `text stops at the budget of a call and says how to read the rest`() async throws {
        let page = sentence
        let url = try pdf(Array(repeating: page, count: 3))
        let output = try PDFReader.read(
            [UInt8](try Data(contentsOf: url)), path: "d.pdf", pages: nil, maximumImages: 8, textBytes: 150)
        #expect(output.content.contains("text of page 1;") && output.content.contains("2 more pages, not shown"))
        #expect(output.content.contains("pass pages to read them"))
        let rest = try await read(#","pages":"2""#)
        #expect(rest.content.contains("text of page 2") && !rest.content.contains("not shown"))
    }

    @Test func `page lists are written as ranges`() {
        #expect(PDFReader.Shown.ranges([1, 2, 3, 7]) == "pages 1-3, 7")
        #expect(PDFReader.Shown.ranges([5]) == "page 5" && PDFReader.Shown.ranges([5, 6]) == "pages 5, 6")
    }
}
