import AskCore
import Foundation
import Testing

@Suite("The white paper stays a core document")
struct WhitePaperTests {
    @Test func `the white paper stays within its budget`() throws {
        // A principles document that grows with every experiment stops being one. The probe history
        // belongs in the diary, which is where it now lives.
        let lines = try DocumentationLayout.whitePaperLineCount()
        #expect(
            lines <= DocumentationLayout.maximumWhitePaperLines,
            """
            docs/WHITE-PAPER.md is \(lines) lines, over the \
            \(DocumentationLayout.maximumWhitePaperLines)-line budget for a principles document.
            Probe history belongs in the diary, not here.
            """
        )
    }

    @Test func `the white paper does not carry a probe ledger`() throws {
        // The failure mode this guards against is specific: a table of probes appended to a
        // principles document, which then changes on every iteration and is never read whole.
        let text = try String(contentsOf: DocumentationLayout.whitePaperURL(), encoding: .utf8)
        #expect(!text.contains("## Probe ledger"), "the probe history belongs in the diary")
    }
}
