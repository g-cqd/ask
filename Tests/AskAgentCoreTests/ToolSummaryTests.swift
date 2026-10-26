import AskAI
import Testing

@testable import AskAgentCore

/// The one line that shows a tool call (roadmap 0028): the command or the path when there is one, the whole input otherwise, and never
/// more than the first line, cut at 160 characters.
@Suite("A tool call is shown as one short line")
struct ToolSummaryTests {
    private func summary(_ json: String) -> String {
        ToolSummary.line(for: try! JSONObject(validating: Array(json.utf8)))
    }

    @Test func `a command is shown as the command`() {
        #expect(summary(#"{"command":"swift build","yield_seconds":5}"#) == "swift build")
    }

    @Test func `a path is shown as the path`() {
        #expect(summary(#"{"path":"Sources/ask/Ask.swift","content":"x"}"#) == "Sources/ask/Ask.swift")
    }

    @Test func `a command wins over a path when a call has both`() {
        #expect(summary(#"{"path":"a.txt","command":"cat a.txt"}"#) == "cat a.txt")
    }

    @Test func `a call with neither is shown as its input`() {
        #expect(summary(#"{"query":"urlsession"}"#) == #"{"query":"urlsession"}"#)
    }

    @Test func `only the first line of a command is shown`() {
        #expect(summary(#"{"command":"echo one\necho two"}"#) == "echo one")
    }

    @Test func `a long line is cut at 160 characters with a mark`() {
        let long = String(repeating: "x", count: 200)
        let shown = summary(#"{"command":"\#(long)"}"#)
        #expect(shown == String(repeating: "x", count: 160) + "…")
    }

    @Test func `a line of exactly 160 characters is not cut`() {
        let exact = String(repeating: "y", count: 160)
        #expect(summary(#"{"command":"\#(exact)"}"#) == exact)
    }

    @Test func `a command that is not text falls back to the input`() {
        #expect(summary(#"{"command":7}"#) == #"{"command":7}"#)
    }

    @Test func `an empty command is an empty line, not the input`() {
        #expect(summary(#"{"command":""}"#) == "")
    }
}
