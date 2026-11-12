import Testing

@testable import AskTUI

/// A tool's header is its name alone when the call has nothing to show (note n70): never `notes · ` with nothing after it.
@Suite("A tool header without a summary")
struct ToolHeaderTests {
    @Test func `no summary, no separator`() {
        #expect(
            Transcript.Item.toolHeader(name: "notes", summary: "", status: .succeeded, output: "", folded: true)
                == "notes"
        )
        #expect(
            Transcript.Item.toolHeader(name: "notes", summary: "x", status: .succeeded, output: "", folded: true)
                == "notes · x"
        )
    }
}
