internal import AskAI
internal import AskAgentCore
internal import CoreGraphics
internal import Foundation

/// Shows the pages of a PDF (roadmap 0084): the text of a page that has some, and a picture of one that has none.
///
/// A picture is drawn by Core Graphics at up to 2000 px on the long side and bounded like any image, so every provider that takes
/// images takes it. The PDF itself is not sent as a document: its pages cost more as pictures than as text, and ask has the text.
enum PDFReader {
    static func isPDF(_ header: [UInt8]) -> Bool { header.starts(with: Array("%PDF-".utf8)) }

    /// The page numbers `spec` names, in order and without repeats: `"3"`, `"1-4"`, `"1-3,7,9-10"`.
    /// - Returns: nil when `spec` is not that form or names page 0.
    static func pages(_ spec: String) -> [Int]? {
        var result: [Int] = []
        for part in spec.split(separator: ",", omittingEmptySubsequences: false) {
            let ends = part.split(separator: "-", omittingEmptySubsequences: false)
                .map {
                    Int($0.trimmingCharacters(in: .whitespaces))
                }
            guard (1 ... 2).contains(ends.count), let first = ends[0], first >= 1 else { return nil }
            let last = ends.count == 2 ? ends[1] : first
            guard let last, last >= first, last - first < 10_000 else { return nil }
            for page in first ... last where !result.contains(page) { result.append(page) }
        }
        return result.isEmpty ? nil : result
    }

    /// What `read` gives for a PDF: the text of each page that has some, and a picture of each page that has none or when `render` asks.
    ///
    /// Text is a quarter of the tokens of a picture of the same page (roadmap 0084, diary 2026-10-28-08), exact where a picture is read,
    /// and the only thing a model without images can use. A page with no text layer is a scan or a drawing, so it is shown as a picture.
    static func read(
        _ bytes: [UInt8], path: String, pages spec: String?, maximumImages: Int, render: Bool = false,
        textBytes: Int = Shown.textBytes,
        allowance: ImageReader.Allowance = ImageReader.Allowance()
    ) throws(ToolFailure) -> ToolOutput {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let document = CGPDFDocument(provider) else {
            throw ToolFailure("\(path) looks like a PDF but could not be opened.")
        }
        guard !document.isEncrypted || document.isUnlocked else {
            throw ToolFailure("\(path) is a password-protected PDF; it was not read.")
        }
        let total = document.numberOfPages
        guard total > 0 else { throw ToolFailure("\(path) is a PDF with no pages.") }
        let wanted = try chosen(spec, of: total, path: path)
        var shown = Shown(maximumImages: maximumImages, textBytes: textBytes)
        let texts = render ? nil : PDFPageText(bytes)
        for number in wanted {
            guard let page = document.page(at: number) else {
                throw ToolFailure("\(path): page \(number) could not be read.")
            }
            let text = texts?.text(ofPage: number) ?? ""
            guard try shown.add(page, number: number, text: text, allowance: allowance, path: path) else { break }
        }
        return shown.output(path: path, total: total, wanted: wanted, explicit: spec != nil)
    }

    /// The pages of a PDF read so far, within the budgets of one call.
    struct Shown {
        /// The most bytes of page text one call returns: about 25,000 tokens.
        static let textBytes = 100_000
        /// A page with less text than this is a picture or a scan; its text is not worth a page of its own.
        static let minimumText = 80

        let maximumImages: Int
        let textBudget: Int
        var textPages: [Int] = []
        var picturePages: [Int] = []
        var text = ""
        var images: [ImagePart] = []

        init(maximumImages: Int, textBytes: Int = Shown.textBytes) {
            self.maximumImages = maximumImages
            textBudget = textBytes
        }

        /// Adds a page, as text when it has enough and as a picture otherwise.
        /// - Returns: false when the page does not fit the budgets, so reading stops before it.
        mutating func add(
            _ page: CGPDFPage, number: Int, text pageText: String, allowance: ImageReader.Allowance, path: String
        ) throws(ToolFailure) -> Bool {
            if pageText.count >= Self.minimumText {
                let block = "[page \(number)]\n\(pageText)"
                if !text.isEmpty, text.utf8.count + block.utf8.count > textBudget { return false }
                text += (text.isEmpty ? "" : "\n\n") + block
                textPages.append(number)
                return true
            }
            guard images.count < maximumImages else { return false }
            do { images.append(try PDFReader.render(page, allowance: allowance).part) } catch {
                throw ToolFailure("\(path): page \(number) could not be made small enough to send.")
            }
            picturePages.append(number)
            return true
        }

        func output(path: String, total: Int, wanted: [Int], explicit: Bool) -> ToolOutput {
            var line = "\(path): PDF, \(total) page\(total == 1 ? "" : "s")"
            if !textPages.isEmpty { line += "; text of \(Self.ranges(textPages))" }
            if !picturePages.isEmpty {
                line += "; \(textPages.isEmpty ? "" : "pictures of ")\(textPages.isEmpty ? "showing page" : "page")"
                line += "\(picturePages.count == 1 ? "" : "s") \(Self.ranges(picturePages))"
            }
            let read = textPages.count + picturePages.count
            if wanted.count > read {
                line +=
                    "; \(wanted.count - read) more \(explicit ? "asked for," : "pages,") not shown (over the limit of "
                line += "\(maximumImages) pictures or \(textBudget / 1000) KB of text); pass pages to read them"
            }
            if !textPages.isEmpty {
                line += ". Pass render: true for pictures of the pages, which show figures and layout"
            }
            var output = ToolOutput(text.isEmpty ? line : line + "\n\n" + text)
            output.images = images
            return output
        }

        /// `[1, 2, 3, 7]` as "1-3, 7" (a single page as "5", two as "5, 6").
        static func ranges(_ pages: [Int]) -> String {
            var parts: [String] = []
            var start = 0
            while start < pages.count {
                var end = start
                while end + 1 < pages.count, pages[end + 1] == pages[end] + 1 { end += 1 }
                parts.append(
                    end - start >= 2
                        ? "\(pages[start])-\(pages[end])"
                        : pages[start ... end].map(String.init).joined(separator: ", "))
                start = end + 1
            }
            return (pages.count == 1 ? "page " : "pages ") + parts.joined(separator: ", ")
        }
    }

    /// The pages `spec` asks for, or every page when it is nil (the budgets of a call decide how many are shown).
    private static func chosen(_ spec: String?, of total: Int, path: String) throws(ToolFailure) -> [Int] {
        guard let spec else { return Array(1 ... total) }
        guard let named = pages(spec) else {
            throw ToolFailure("pages must look like \"3\", \"1-4\" or \"1-3,7\"; got \"\(spec)\".")
        }
        if let outside = named.first(where: { $0 > total }) {
            throw ToolFailure("\(path) has \(total) pages; page \(outside) is past the end.")
        }
        return named
    }

    fileprivate static func render(_ page: CGPDFPage, allowance: ImageReader.Allowance) throws(ImageReader.Failure)
        -> ImageReader.Fitted
    {
        let box = page.getBoxRect(.cropBox)
        let turned = page.rotationAngle % 180 != 0
        let pageWidth = turned ? box.height : box.width
        let pageHeight = turned ? box.width : box.height
        guard pageWidth > 0, pageHeight > 0 else { throw .undecodable }
        return try ImageReader.fit(favoursPNG: true, longSide: ImageReader.maximumSide, allowance: allowance) { side in
            let scale = Double(side) / max(pageWidth, pageHeight)
            let width = max(1, Int(pageWidth * scale))
            let height = max(1, Int(pageHeight * scale))
            guard
                // @dl:accept -- a bitmap context is made the same way for a scaled image and a drawn page; the arguments differ, so sharing would take as many
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return nil }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.concatenate(
                page.getDrawingTransform(
                    .cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0,
                    preserveAspectRatio: true))
            context.drawPDFPage(page)
            return context.makeImage()
        }
    }
}
