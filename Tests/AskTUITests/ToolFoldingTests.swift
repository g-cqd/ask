internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// A tool's output starts folded to one line, and a click on its header or Ctrl+O opens it (TerminalKit roadmap 0018, ask roadmap 0051).
@Suite("A tool's output folds to a line and opens on a click")
struct ToolFoldingTests {
    private static let ls: [ConversationUpdate] = [
        .toolStarted(name: "bash", summary: "ls"), .toolFinished(.succeeded, output: "alpha\nbeta\ngamma")
    ]
    private static let ctrlO = KeyEvent(keyCode: UInt32(Character("o").asciiValue!), modifiers: .ctrl)

    @Test func `a tool with output starts as one line that says how much is inside`() {
        let rig = PointerRig(updates: Self.ls)
        #expect(rig.text(row: 9) == "bash ls ✓ · 3 lines")
        #expect(rig.text(row: 8) == "")
    }

    @Test func `a click on the header opens it, and another closes it`() {
        var rig = PointerRig(updates: Self.ls)
        rig.click(row: 9, col: 3)
        #expect(rig.text(row: 6) == "bash ls ✓")
        #expect([7, 8, 9].map { rig.text(row: $0) } == ["  alpha", "  beta", "  gamma"])
        rig.click(row: 6, col: 3)
        #expect(rig.text(row: 9) == "bash ls ✓ · 3 lines")
        #expect(rig.text(row: 8) == "")
    }

    @Test func `the body is dim and the header keeps its status colour`() {
        var rig = PointerRig(updates: Self.ls)
        rig.click(row: 9, col: 3)
        #expect(rig.buffer[7, 2].style.dim)
        #expect(!rig.buffer[7, 2].style.inverse)
    }

    @Test func `a click in the body does not toggle it`() {
        var rig = PointerRig(updates: Self.ls)
        rig.click(row: 9, col: 3)
        rig.click(row: 8, col: 4)
        #expect(rig.text(row: 6) == "bash ls ✓")
    }

    @Test func `a tool that returned nothing has nothing to fold`() {
        var rig = PointerRig(updates: [.toolStarted(name: "bash", summary: "true"), .toolFinished(.succeeded)])
        #expect(rig.text(row: 9) == "bash true ✓")
        rig.click(row: 9, col: 3)
        #expect(rig.text(row: 9) == "bash true ✓")
        #expect(!rig.controller.state.transcript.isFoldable(0))
    }

    @Test func `a running tool shows no count until it has returned`() {
        let rig = PointerRig(updates: [.toolStarted(name: "bash", summary: "sleep 9")])
        #expect(rig.text(row: 9) == "bash sleep 9 …")
    }

    @Test func `with folding off a tool's output is shown from the start`() {
        let rig = PointerRig(
            options: ScreenOptions(foldTools: false, prompt: "ask> ", tint: false, separator: false), updates: Self.ls)
        #expect(rig.text(row: 6) == "bash ls ✓")
        #expect(rig.text(row: 9) == "  gamma")
    }

    @Test func `control O flips every tool block, and a choice made by click gives way to it`() {
        var rig = PointerRig(
            updates: Self.ls + [.toolStarted(name: "grep", summary: "x"), .toolFinished(.succeeded, output: "one")])
        rig.click(row: 8, col: 3)  // opens the first
        _ = rig.controller.handle(.key(Self.ctrlO), pageRows: 10)
        rig.draw()
        #expect(!rig.controller.state.transcript.isFolded(0) && !rig.controller.state.transcript.isFolded(1))
        _ = rig.controller.handle(.key(Self.ctrlO), pageRows: 10)
        rig.draw()
        #expect(rig.controller.state.transcript.isFolded(0) && rig.controller.state.transcript.isFolded(1))
    }

    @Test func `control O does not reach the prompt`() {
        var rig = PointerRig(updates: Self.ls)
        _ = rig.controller.handle(.key(Self.ctrlO), pageRows: 10)
        #expect(rig.controller.state.editor.text.isEmpty)
    }

    @Test func `a long output is cut and the cut is said`() {
        var transcript = Transcript()
        transcript.startTool(name: "cat", summary: "big")
        transcript.finishTool(.succeeded, output: (1 ... 1000).map { "row \($0)" }.joined(separator: "\n") + "\n\n")
        guard case .tool(_, _, _, let output) = transcript.items[0] else {
            Issue.record("no tool")
            return
        }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == Transcript.outputLineLimit + 1)
        #expect(lines.first == "row 1" && lines[Transcript.outputLineLimit - 1] == "row 400")
        #expect(lines.last == "… 600 more lines not shown")
    }

    // MARK: - Where the reader is

    @Test func `opening a block while scrolled back keeps its header on the same row`() {
        var updates: [ConversationUpdate] = (1 ... 6).map { .notice("before \($0)", isError: false) }
        updates += Self.ls
        updates += (1 ... 12).map { .notice("after \($0)", isError: false) }
        var rig = PointerRig(updates: updates)
        rig.mouse(.scrollUp, .press, row: 3, col: 3)
        rig.mouse(.scrollUp, .press, row: 3, col: 3)
        guard let header = (0 ..< 10).first(where: { rig.text(row: $0).hasPrefix("bash") }) else {
            Issue.record("the header is not on screen")
            return
        }
        rig.click(row: header, col: 3)
        #expect(rig.text(row: header) == "bash ls ✓", "the header moved")
        rig.click(row: header, col: 3)
        #expect(rig.text(row: header) == "bash ls ✓ · 3 lines", "the header moved back")
    }

    @Test func `at the bottom, opening a block grows upward and the end stays in view`() {
        var rig = PointerRig(updates: Self.ls)
        rig.click(row: 9, col: 3)
        #expect(rig.controller.state.scrollback == 0)
        #expect(rig.text(row: 9) == "  gamma")
    }

    // MARK: - Selecting what is shown

    @Test func `a folded block copies as the line that is shown`() {
        var rig = PointerRig(updates: Self.ls)
        let effects = rig.drag(from: (9, 0), to: (9, 20))
        #expect(effects == [.copy("bash ls ✓ · 3 lines")])
    }

    @Test func `a selection across a folded block reads its placeholder and not what is inside`() {
        var rig = PointerRig(updates: Self.ls + [.notice("after", isError: false)])
        // Rows: the folded header, then the notice; the body (alpha, beta, gamma) is not drawn and must not be read.
        let effects = rig.drag(from: (8, 0), to: (9, 4))
        #expect(effects == [.copy("bash ls ✓ · 3 lines\nafter")])
    }

    @Test func `an open block copies its body, one line each`() {
        var rig = PointerRig(updates: Self.ls)
        rig.click(row: 9, col: 3)
        let effects = rig.drag(from: (7, 2), to: (9, 6))
        #expect(effects == [.copy("alpha\nbeta\ngamma")])
    }

    @Test func `closing a block clears a selection that was inside it`() {
        var rig = PointerRig(updates: Self.ls)
        rig.click(row: 9, col: 3)
        rig.drag(from: (7, 2), to: (9, 6))
        rig.click(row: 6, col: 3)
        #expect(rig.controller.state.selection == nil)
        #expect((0 ..< 10).allSatisfy { rig.inverse(row: $0).isEmpty })
    }
}
