internal import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// The model's reasoning is a block that starts folded to one line, and opens on a click or Ctrl+T (ADR-0046, ask roadmap 0051).
@Suite("Reasoning folds to a line and opens on a click")
struct ThinkingFoldingTests {
    private static let reasoning: [ConversationUpdate] = [.thinkingText("first thought\nsecond thought")]
    private static let ctrlT = KeyEvent(keyCode: UInt32(Character("t").asciiValue!), modifiers: .ctrl)
    private static let ctrlO = KeyEvent(keyCode: UInt32(Character("o").asciiValue!), modifiers: .ctrl)

    @Test func `reasoning starts as one line that says how much there is`() {
        let rig = PointerRig(updates: Self.reasoning)
        #expect(rig.text(row: 9) == "thinking · 2 lines")
        #expect(rig.text(row: 8) == "")
    }

    @Test func `streamed reasoning is one block whose count grows`() {
        var rig = PointerRig(updates: [.thinkingText("one")])
        #expect(rig.text(row: 9) == "thinking · 1 line")
        rig.controller.handle(.thinkingText("\ntwo\n"))
        rig.controller.handle(.thinkingText("three"))
        rig.draw()
        #expect(rig.controller.state.transcript.items.count == 1)
        #expect(rig.text(row: 9) == "thinking · 3 lines")
    }

    @Test func `reasoning after an answer is a new block`() {
        var rig = PointerRig(updates: Self.reasoning + [.assistantText("answer")])
        rig.controller.handle(.thinkingText("more"))
        rig.draw()
        #expect(rig.controller.state.transcript.items.count == 3)
    }

    @Test func `a click on the header opens it, dim and italic, and another closes it`() {
        var rig = PointerRig(updates: Self.reasoning)
        rig.click(row: 9, col: 3)
        #expect(rig.text(row: 7) == "thinking")
        #expect([8, 9].map { rig.text(row: $0) } == ["  first thought", "  second thought"])
        #expect(rig.buffer[8, 2].style.dim && rig.buffer[8, 2].style.italic)
        rig.click(row: 7, col: 3)
        #expect(rig.text(row: 9) == "thinking · 2 lines")
    }

    @Test func `with folding off reasoning is shown from the start`() {
        let rig = PointerRig(options: ScreenOptions(foldThinking: false), updates: Self.reasoning)
        #expect(rig.text(row: 7) == "thinking")
    }

    @Test func `control T flips reasoning and leaves tool output alone, and control O the reverse`() {
        let tool: [ConversationUpdate] = [
            .toolStarted(name: "bash", summary: "ls"), .toolFinished(.succeeded, output: "a\nb")
        ]
        var rig = PointerRig(updates: Self.reasoning + tool)
        let transcript = { rig.controller.state.transcript }
        _ = rig.controller.handle(.key(Self.ctrlT), pageRows: 10)
        #expect(!transcript().isFolded(0) && transcript().isFolded(1))
        _ = rig.controller.handle(.key(Self.ctrlO), pageRows: 10)
        #expect(!transcript().isFolded(0) && !transcript().isFolded(1))
        _ = rig.controller.handle(.key(Self.ctrlT), pageRows: 10)
        #expect(transcript().isFolded(0) && !transcript().isFolded(1))
        #expect(rig.controller.state.editor.text.isEmpty)
    }

    @Test func `a choice made by click on reasoning survives control O`() {
        var rig = PointerRig(updates: Self.reasoning)
        rig.click(row: 9, col: 3)
        _ = rig.controller.handle(.key(Self.ctrlO), pageRows: 10)
        #expect(!rig.controller.state.transcript.isFolded(0))
    }

    @Test func `a folded block copies as the line that is shown`() {
        var rig = PointerRig(updates: Self.reasoning)
        #expect(rig.drag(from: (9, 0), to: (9, 19)) == [.copy("thinking · 2 lines")])
    }

    @Test func `reasoning that is only blank has nothing to open`() {
        var rig = PointerRig(updates: [.thinkingText("\n\n")])
        #expect(rig.text(row: 9) == "thinking")
        rig.click(row: 9, col: 3)
        #expect(rig.text(row: 9) == "thinking")
        #expect(!rig.controller.state.transcript.isFoldable(0))
    }

    @Test func `a long reasoning is cut and the cut is said`() {
        var rig = PointerRig(updates: [.thinkingText((1 ... 1000).map { "t \($0)" }.joined(separator: "\n"))])
        #expect(rig.text(row: 9) == "thinking · \(Transcript.outputLineLimit + 1) lines")
        rig.click(row: 9, col: 3)
        #expect(rig.text(row: 9) == "  … 600 more lines not shown")
    }
}
