internal import Foundation
internal import PDFKit

/// The text layer of a PDF's pages, read by PDFKit. Opening it takes about 100 ms the first time in a process, so it is made only when a
/// PDF is read.
struct PDFPageText {
    private let document: PDFDocument?

    init(_ bytes: [UInt8]) { document = PDFDocument(data: Data(bytes)) }

    /// The text of page `number` (1-based), trimmed; empty when the page has none or cannot be read.
    func text(ofPage number: Int) -> String {
        (document?.page(at: number - 1)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
