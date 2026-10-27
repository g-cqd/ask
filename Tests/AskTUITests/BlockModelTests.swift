internal import TerminalKitInput
internal import TerminalKitRender
internal import TerminalKitStyle
internal import Testing

@testable import AskTUI

/// The block model (roadmap 0074): every block has a row of padding around it and an inset of one column; tool calls and the user's messages are
/// tinted and set apart from each other by a blank row; answers and thinking are not tinted and not spaced; thinking is faint italic.
@Suite("Blocks have padding all around, tints by kind, and a blank row between the tinted ones")
struct BlockModelTests {
    private let columns = 40
    private let style = BlockStyle()

    private func lines(_ items: [Transcript.Item], _ index: Int, folded: Bool = false) -> [ScreenComposer.Line] {
        var transcript = Transcript()
        for item in items {
            switch item {
                case .user(let text): transcript.addUser(text)
                case .assistant(let text): transcript.addAssistantText(text)
                case .thinking(let text): transcript.addThinkingText(text)
                case .tool(let name, let summary, let status, let output):
                    transcript.startTool(name: name, summary: summary)
                    transcript.finishTool(status, output: output)
                case .notice(let text, let isError): transcript.addNotice(text, isError: isError)
            }
        }
        return ScreenComposer.lines(in: transcript, at: index, columns: columns, style: style)
    }

    private func texts(_ lines: [ScreenComposer.Line]) -> [String] { lines.map(\.text) }

    @Test func `an answer has a row of padding above and below and an inset of one column, and no tint`() {
        let rows = lines([.assistant("hello")], 0)
        #expect(texts(rows) == ["", " hello", ""])
        #expect(rows.allSatisfy { $0.style.bg == .default })
        #expect(rows[1].source?.col == 1 && rows[0].source == nil && rows[2].source == nil)
    }

    @Test func `the user's message is tinted, padding included`() {
        let rows = lines([.user("hi")], 0)
        let tint = style.theme.tint(for: .user("hi"))
        #expect(tint != .default && texts(rows) == ["", " hi", ""])
        #expect(rows.allSatisfy { $0.style.bg == tint })
        #expect(rows[1].style.bold)
    }

    @Test func `a tool call is tinted by how it ended`() {
        let done = lines([.tool(name: "bash", summary: "ls", status: .succeeded, output: "")], 0)
        let failed = lines([.tool(name: "bash", summary: "ls", status: .failed("exit 1"), output: "")], 0)
        let running = lines([.tool(name: "bash", summary: "ls", status: .running, output: "")], 0)
        let tints = [done, failed, running].map { $0[1].style.bg }
        #expect(Set(tints).count == 3 && !tints.contains(.default))
        #expect(texts(done) == ["", " bash ls ✓", ""])
    }

    @Test func `a blank row, not tinted, stands between two tool calls, and between a message and a tool call`() {
        let tool = Transcript.Item.tool(name: "read", summary: "a", status: .succeeded, output: "")
        let second = lines([tool, tool], 1)
        #expect(texts(second) == ["", "", " read a ✓", ""])
        #expect(second[0].style.bg == .default && second[1].style.bg != .default)
        #expect(texts(lines([.user("go"), tool], 1)).first == "")
        #expect(lines([.user("go"), tool], 1).count == 4)
        #expect(lines([tool, .user("again")], 1).count == 4)
    }

    @Test func `answers and thinking get their padding and no blank row`() {
        let tool = Transcript.Item.tool(name: "read", summary: "a", status: .succeeded, output: "")
        #expect(lines([tool, .assistant("done")], 1).count == 3)
        #expect(lines([.assistant("a"), .assistant("b")], 0).count == 3)
        #expect(lines([tool, .thinking("hm")], 1).count == 3)
    }

    @Test func `thinking is faint italic with no tint, and says Thinking... folded`() {
        let rows = lines([.thinking("a\nb")], 0)
        #expect(rows[1].text == " Thinking...")
        #expect(rows.allSatisfy { $0.style.bg == .default })
        #expect(rows[1].style.italic && rows[1].style.dim)
    }

    @Test func `an open thinking block replaces its header with its body, italic and faint`() {
        var transcript = Transcript()
        transcript.addThinkingText("one\ntwo")
        transcript.toggleFold(0)
        let rows = ScreenComposer.lines(in: transcript, at: 0, columns: columns, style: style)
        #expect(texts(rows) == ["", " one", " two", ""])
        #expect(rows[2].style.italic && rows[2].style.dim && rows[2].source?.col == 1)
    }

    @Test func `command and authentication notices have one row of padding above and below`() {
        #expect(texts(lines([.notice("note", isError: false)], 0)) == ["", " note", ""])
    }

    @Test func `a long line wraps inside the inset`() {
        let rows = lines([.assistant(String(repeating: "x", count: 100))], 0)
        #expect(rows.dropFirst().dropLast().allSatisfy { $0.text.count <= columns })
        #expect(rows.count == 2 + 3)
    }

    @Test func `padding rows carry no source, so a selection and a copy contain the text and not the padding`() {
        var rig = PointerRig(columns: 30, rows: 12, options: ScreenOptions(), updates: [.assistantText("hello world")])
        let transcript = rig.composer.transcriptRows
        let text = (0 ..< transcript).map { rig.text(row: $0) }
        let row = text.lastIndex { $0.contains("hello world") }!
        let effects = rig.drag(from: (row - 1, 0), to: (row + 1, 29))
        #expect(effects == [.copy("hello world")])
    }

    @Test func `a click on a tool header opens it even with padding, and the view stays put`() {
        var rig = PointerRig(columns: 30, rows: 14, options: ScreenOptions(), lines: [])
        rig.controller.handle(.toolStarted(name: "bash", summary: "ls"))
        rig.controller.handle(.toolFinished(.succeeded, output: "a\nb"))
        rig.draw()
        let header = (0 ..< 14).first { rig.text(row: $0).contains("bash ls ✓") }!
        rig.click(row: header, col: 3)
        #expect(!rig.controller.state.transcript.isFolded(0))
        #expect((0 ..< 14).contains { rig.text(row: $0) == "   a" })
    }

    @Test(arguments: [0, 1, 2])
    func `each folded thinking row including padding opens the block`(offset: Int) {
        var rig = PointerRig(columns: 40, rows: 16, options: ScreenOptions(), updates: [.thinkingText("one\ntwo")])
        let header = (0 ..< 16).first { rig.text(row: $0).contains("Thinking...") }!
        rig.click(row: header - 1 + offset, col: 39)
        #expect(!rig.controller.state.transcript.isFolded(0))
        #expect(!(0 ..< 16).contains { rig.text(row: $0).contains("Thinking...") })
        let content = (0 ..< 16).first { rig.text(row: $0) == " one" }!
        rig.click(row: content, col: 39)
        #expect(rig.controller.state.transcript.isFolded(0))
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5])
    func `every open tool row including padding and header gap closes it`(offset: Int) {
        let updates: [ConversationUpdate] = [
            .toolStarted(name: "bash", summary: "ls"), .toolFinished(.succeeded, output: "a\nb")
        ]
        var rig = PointerRig(columns: 40, rows: 16, options: ScreenOptions(foldTools: false), updates: updates)
        let header = (0 ..< 16).first { rig.text(row: $0).contains("bash ls ✓") }!
        #expect(rig.text(row: header + 1) == "")
        #expect(rig.text(row: header + 2) == "   a")
        rig.click(row: header - 1 + offset, col: 39)
        #expect(rig.controller.state.transcript.isFolded(0))
    }

    @Test func `open thinking selection copies content without a hidden header`() {
        var rig = PointerRig(
            columns: 40, rows: 16, options: ScreenOptions(foldThinking: false), updates: [.thinkingText("one\ntwo")])
        let content = (0 ..< 16).first { rig.text(row: $0) == " one" }!
        #expect(rig.drag(from: (content, 1), to: (content + 1, 4)) == [.copy("one\ntwo")])
    }

    @Test func `with padding off the older plain layout is unchanged`() {
        var transcript = Transcript()
        transcript.addAssistantText("hello")
        #expect(texts(ScreenComposer.lines(in: transcript, at: 0, columns: 40, style: .plain)) == ["hello"])
    }

    @Test func `the tint reaches the edge of the screen on every row of a tinted block`() {
        let rig = PointerRig(columns: 30, rows: 12, options: ScreenOptions(), updates: [.userPrompt("hi")])
        let tint = ScreenTheme().tint(for: .user("hi"))
        let rows = (0 ..< 12).filter { rig.buffer[$0, 0].style.bg == tint }
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { row in (0 ..< 30).allSatisfy { rig.buffer[row, $0].style.bg == tint } })
    }
}
