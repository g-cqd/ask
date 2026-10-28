internal import AskAI
internal import AskAgentCore
internal import CoreGraphics
internal import Foundation

/// Shows pages of a PDF as images (roadmap 0084).
///
/// Pages are drawn by Core Graphics at up to 2000 px on the long side and bounded like any image, so every provider
/// that takes images takes a PDF, and no page text is lost to a parser. Sending the PDF itself, where a provider
/// accepts one, is a later slice.
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

    static func read(
        _ bytes: [UInt8], path: String, pages spec: String?, maximumImages: Int,
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
        let wanted = try chosen(spec, of: total, path: path, maximumImages: maximumImages)
        let shown = Array(wanted.prefix(maximumImages))
        var images: [ImagePart] = []
        for number in shown {
            guard let page = document.page(at: number) else {
                throw ToolFailure("\(path): page \(number) could not be read.")
            }
            do {
                let fitted = try render(page, allowance: allowance)
                images.append(fitted.part)
            } catch {
                throw ToolFailure("\(path): page \(number) could not be made small enough to send.")
            }
        }
        var line = "\(path): PDF, \(total) page\(total == 1 ? "" : "s"); showing page\(shown.count == 1 ? "" : "s") "
        line += shown.map(String.init).joined(separator: ", ")
        if wanted.count > shown.count {
            line += "; \(wanted.count - shown.count) more asked for but over the limit of \(maximumImages) images"
        } else if spec == nil, total > shown.count {
            line += "; pass pages to see the other \(total - shown.count)"
        }
        var output = ToolOutput(line)
        output.images = images
        return output
    }

    /// The pages `spec` asks for, or the first ones when it is nil.
    private static func chosen(
        _ spec: String?, of total: Int, path: String, maximumImages: Int
    ) throws(ToolFailure) -> [Int] {
        guard let spec else { return Array(1 ... min(total, maximumImages)) }
        guard let named = pages(spec) else {
            throw ToolFailure("pages must look like \"3\", \"1-4\" or \"1-3,7\"; got \"\(spec)\".")
        }
        if let outside = named.first(where: { $0 > total }) {
            throw ToolFailure("\(path) has \(total) pages; page \(outside) is past the end.")
        }
        return named
    }

    private static func render(_ page: CGPDFPage, allowance: ImageReader.Allowance) throws(ImageReader.Failure)
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
