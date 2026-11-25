import AskCore
import Foundation
import Testing

@Suite("Agent guidelines stay concise")
struct WhitePaperTests {
    @Test func `AGENTS.md exists and stays within its line budget`() throws {
        let lines = try DocumentationLayout.whitePaperLineCount()
        #expect(lines > 0 && lines <= DocumentationLayout.maximumWhitePaperLines)
    }

    @Test func `AGENTS.md does not carry a probe ledger`() throws {
        let text = try String(contentsOf: DocumentationLayout.whitePaperURL(), encoding: .utf8)
        #expect(!text.contains("## Probe ledger"))
    }
}
