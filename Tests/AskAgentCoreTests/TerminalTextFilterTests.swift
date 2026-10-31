import AskAI
import Synchronization
import Testing

@testable import AskAgentCore

/// What `ask -p` writes to a terminal carries no control sequence from the model or a tool (roadmap 0153, finding 5): an OSC 52 would
/// write the person's clipboard, a CSI could move the cursor or hide text, a title sequence could mislead. The text around them stays.
@Suite("Control sequences never reach the terminal from a print run")
struct TerminalTextFilterTests {
    private func filtered(_ pieces: [String]) -> String {
        var filter = TerminalTextFilter()
        return pieces.map { filter.filter($0) }.joined()
    }

    @Test func `escape sequences are removed whole, and the text around them kept`() {
        #expect(filtered(["a\u{1B}]52;c;aGVsbG8=\u{07}b"]) == "ab", "an OSC 52 clipboard write")
        #expect(filtered(["\u{1B}[31mred\u{1B}[0m plain"]) == "red plain", "colours")
        #expect(filtered(["x\u{1B}]0;title\u{1B}\\y"]) == "xy", "a title ended by ST")
        #expect(filtered(["\u{9B}2Jz"]) == "z", "the 8-bit CSI")
        #expect(filtered(["\u{1B}Pq#0;2;0;0;0\u{1B}\\after"]) == "after", "a DCS (sixel)")
        #expect(filtered(["\u{1B}7saved\u{1B}8"]) == "saved", "two-byte escapes")
    }

    @Test func `a sequence split across pieces is still removed whole`() {
        #expect(filtered(["before \u{1B}", "]52;c;", "aGk=", "\u{07} after"]) == "before  after")
        #expect(filtered(["\u{1B}[3", "1mred"]) == "red")
    }

    @Test func `tabs and line ends stay, other controls go`() {
        #expect(filtered(["a\tb\nc\r\nd"]) == "a\tb\nc\nd")
        #expect(filtered(["bell\u{07} back\u{08}space del\u{7F} cr\rover"]) == "bell backspace del crover")
    }

    @Test func `a sequence that never ends cannot hide the rest of the answer`() {
        let swallowed = filtered(["\u{1B}]0;" + String(repeating: "x", count: 5_000) + "visible"])
        #expect(swallowed.hasSuffix("visible"))
        #expect(filtered(["\u{1B}]0;unterminated", "\nnext line"]) == "\nnext line", "a line end ends it")
    }

    @Test func `a print run writes the answer and the tool lines through it`() {
        let written = Mutex<[String]>([])
        let renderer = PrintRenderer(
            out: { text in written.withLock { $0.append("out:" + text) } },
            err: { text in written.withLock { $0.append("err:" + text) } })
        renderer.render(.model(.textDelta(index: 0, "ok \u{1B}]52;c;")))
        renderer.render(.model(.textDelta(index: 0, "aGk=\u{07}done")))
        renderer.render(
            .toolStarted(
                id: "1", name: "bash", input: try! JSONObject(validating: Array(#"{"command":"echo \u001b[2J"}"#.utf8)))
        )
        let all = written.withLock { $0 }.joined()
        #expect(
            !all.unicodeScalars.contains { $0.value == 0x1B || $0.value == 0x07 || $0.value == 0x9B },
            "\(all.debugDescription)")
        let answer = written.withLock { $0 }.filter { $0.hasPrefix("out:") }.map { String($0.dropFirst(4)) }.joined()
        #expect(answer.hasPrefix("ok done"), "\(answer.debugDescription)")
    }
}
