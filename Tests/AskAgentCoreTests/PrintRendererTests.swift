import AskAI
import Synchronization
import Testing

@testable import AskAgentCore

/// What `ask -p` prints (roadmap 0028): the answer to standard output, everything else to standard error, a half-written line
/// finished before anything else is said, and the tokens counted over the run.
@Suite("A print run's output is routed, bounded and counted")
struct PrintRendererTests {
    /// Remembers what it was written, by handle.
    private final class Recorded: Sendable {
        private final class Writes: Sendable {
            let state = Mutex<[String: [String]]>(["out": [], "err": []])
        }

        private let writes = Writes()

        func sink(_ handle: String) -> @Sendable (String) -> Void {
            { [writes] text in writes.state.withLock { $0[handle]?.append(text) } }
        }

        func lines(_ handle: String) -> [String] {
            writes.state.withLock { ($0[handle] ?? []).joined().split(separator: "\n").map(String.init) }
        }

        func whole(_ handle: String) -> String { writes.state.withLock { ($0[handle] ?? []).joined() } }
    }

    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    @Test func `the answer goes to standard output and everything else to standard error`() {
        let written = Recorded()
        let renderer = PrintRenderer(out: written.sink("out"), err: written.sink("err"))
        renderer.render(.model(.textDelta(index: 0, "Hello")))
        renderer.render(.model(.notice("a diagnostic")))
        renderer.render(.finished(nil))
        #expect(written.whole("out") == "Hello\n")
        #expect(written.lines("err") == ["ask: a diagnostic"])
    }

    @Test func `a half-written line is finished before anything else is said`() {
        let written = Recorded()
        let renderer = PrintRenderer(out: written.sink("out"), err: written.sink("err"))
        renderer.render(.model(.textDelta(index: 0, "half")))
        renderer.render(.toolStarted(id: "t", name: "bash", input: input(#"{"command":"ls"}"#)))
        renderer.render(.model(.textDelta(index: 1, "line")))
        renderer.render(.finished(nil))
        #expect(written.whole("out") == "half\nline\n", "the tool's line came after a newline, not inside the answer")
    }

    @Test func `a whole line needs no second newline`() {
        let written = Recorded()
        let renderer = PrintRenderer(out: written.sink("out"), err: written.sink("err"))
        renderer.render(.model(.textDelta(index: 0, "whole\n")))
        renderer.render(.finished(nil))
        #expect(written.whole("out") == "whole\n")
    }

    @Test func `a tool's start is shown with its arguments, cut at two hundred characters`() {
        let written = Recorded()
        let renderer = PrintRenderer(out: written.sink("out"), err: written.sink("err"))
        renderer.render(.toolStarted(id: "t", name: "bash", input: input(#"{"command":"short"}"#)))
        let long = String(repeating: "x", count: 260)
        renderer.render(.toolStarted(id: "t2", name: "bash", input: input(#"{"command":"\#(long)"}"#)))
        #expect(written.lines("err")[0] == #"▸ bash {"command":"short"}"#)
        #expect(written.lines("err")[1].hasPrefix(#"▸ bash {"command":"xx"#) && written.lines("err")[1].hasSuffix("…"))
        #expect(written.lines("err")[1].utf8.count <= 220)
    }

    @Test func `a tool's end shows a tick, or the last line of what went wrong`() {
        let written = Recorded()
        let renderer = PrintRenderer(out: written.sink("out"), err: written.sink("err"))
        renderer.render(.toolFinished(id: "t", name: "bash", output: ToolOutput("done")))
        renderer.render(.toolFinished(id: "t2", name: "bash", output: ToolOutput.error("first\nlast line of it")))
        #expect(written.lines("err") == ["  ✓", "  ✗ last line of it"])
    }

    @Test func `a retry, a compaction and a continuation are each said once, in order`() {
        let written = Recorded()
        let renderer = PrintRenderer(out: written.sink("out"), err: written.sink("err"))
        renderer.render(.retrying(attempt: 1, of: 2, delay: .seconds(1), reason: "rate limited"))
        renderer.render(.compacted(summary: "s", usage: TokenUsage()))
        renderer.render(.continuedAtOutputLimit)
        #expect(
            written.lines("err") == [
                "ask: rate limited; retrying in 1 s (attempt 1 of 2).",
                "ask: Compacted the conversation: earlier messages are now a 1-character summary. The session file keeps them all.",
                "ask: the response hit the output limit; asking the model to continue."
            ])
    }

    @Test func `the tokens of the run are counted, responses and compactions both`() {
        let written = Recorded()
        let renderer = PrintRenderer(out: written.sink("out"), err: written.sink("err"))
        let response = AssembledResponse(
            id: "m", model: "any", blocks: [], stopReason: nil,
            usage: TokenUsage(input: 10, output: 2, cacheRead: 4, cacheCreation: 1), unrecognized: [])
        renderer.render(.responded(response))
        renderer.render(.compacted(summary: "s", usage: TokenUsage(input: 30, output: 40)))
        // The prompt counts every input token the server billed: the input of both requests, plus what was
        // read from and written to the cache (Anthropic bills all three as input).
        #expect(renderer.usageSummary == "in 45 (8% cached) · out 42")
    }
}
