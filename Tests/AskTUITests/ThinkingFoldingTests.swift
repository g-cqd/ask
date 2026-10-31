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
        let rig = PointerRig(columns: 60, updates: Self.reasoning)
        #expect(rig.contentText(row: 9) == "Thinking...")
        #expect(rig.contentText(row: 8) == "")
    }

    @Test func `streamed reasoning is one block whose count grows`() {
        var rig = PointerRig(columns: 60, updates: [.thinkingText("one")])
        #expect(rig.contentText(row: 9) == "Thinking...")
        rig.controller.handle(.thinkingText("\ntwo\n"))
        rig.controller.handle(.thinkingText("three"))
        rig.draw()
        #expect(rig.controller.state.transcript.items.count == 1)
        #expect(rig.contentText(row: 9) == "Thinking...")
    }

    @Test func `reasoning after an answer is a new block`() {
        var rig = PointerRig(columns: 60, updates: Self.reasoning + [.assistantText("answer")])
        rig.controller.handle(.thinkingText("more"))
        rig.draw()
        #expect(rig.controller.state.transcript.items.count == 3)
    }

    @Test func `a click on the header opens it, dim and italic, and another closes it`() {
        var rig = PointerRig(columns: 60, updates: Self.reasoning)
        rig.click(row: 9, col: 3)
        #expect([8, 9].map { rig.contentText(row: $0) } == ["first thought", "second thought"])
        #expect(rig.buffer[8, 2].style.dim && rig.buffer[8, 2].style.italic)
        rig.click(row: 8, col: 3)
        #expect(rig.contentText(row: 9) == "Thinking...")
    }

    /// Owner (2026-10-31): open, a thinking block's first row is the reasoning's own first line, with the block's status after the usual
    /// 4-cell spacer, as a tool's header carries it, however long that line is. A line too long for both no longer pushes the status onto
    /// a row of its own above the reasoning.
    @Test(arguments: [true, false])
    func `open reasoning keeps its status on its first line, however long`(markdown: Bool) {
        let long = "Weighing the options for the cache key carefully before choosing one of them for good"
        let rig = PointerRig(
            columns: 60,
            options: ScreenOptions(
                foldThinking: false, markdown: markdown, prompt: "ask> ", tint: false, separator: false, padding: false),
            updates: [.thinkingText(long + "\nsecond thought")])
        let shown = (0 ..< 10).map { rig.text(row: $0) }
        let first = shown.firstIndex { $0.contains("Weighing") }
        #expect(first != nil, "\(shown)")
        guard let first else { return }
        #expect(shown[first].hasPrefix("Weighing the options") && shown[first].hasSuffix("2 lines · |"), "\(shown)")
        #expect(shown[first].contains("    2 lines"), "the usual spacer: \(shown)")
        #expect(!shown[..<first].contains { $0.contains("lines") }, "no status row above: \(shown)")
        #expect(shown.last == "second thought", "\(shown)")
        #expect(shown.allSatisfy { $0.count <= 60 })
    }

    @Test func `with folding off reasoning is shown from the start`() {
        let rig = PointerRig(
            columns: 60,
            options: ScreenOptions(foldThinking: false, prompt: "ask> ", tint: false, separator: false, padding: false),
            updates: Self.reasoning)
        #expect(rig.contentText(row: 8) == "first thought")
    }

    @Test func `control T flips reasoning and leaves tool output alone, and control O the reverse`() {
        let tool: [ConversationUpdate] = [
            .toolStarted(name: "bash", summary: "ls"), .toolFinished(.succeeded, output: "a\nb")
        ]
        var rig = PointerRig(columns: 60, updates: Self.reasoning + tool)
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
        var rig = PointerRig(columns: 60, updates: Self.reasoning)
        rig.click(row: 9, col: 3)
        _ = rig.controller.handle(.key(Self.ctrlO), pageRows: 10)
        #expect(!rig.controller.state.transcript.isFolded(0))
    }

    @Test func `a folded block copies as the line that is shown`() {
        var rig = PointerRig(columns: 60, updates: Self.reasoning)
        #expect(rig.drag(from: (9, 0), to: (9, 19)) == [.copy("Thinking...")])
    }

    @Test func `blank reasoning shows while the model thinks, then leaves no block behind`() {
        for blank in ["", "\n\n", " \t \n"] {
            var rig = PointerRig(columns: 60, updates: [.userPrompt("q"), .thinkingText(blank)])
            #expect(rig.contentText(row: 9) == "Thinking...", "live, the spinner says the model is thinking")
            #expect(!rig.controller.state.transcript.isFoldable(1))
            rig.controller.handle(.assistantText("answer"))
            rig.draw()
            #expect(rig.controller.state.transcript.items == [.user("q"), .assistant("answer")])
        }
    }

    @Test func `blank reasoning that ends the run, or comes before a tool, is dropped too`() {
        var ended = PointerRig(columns: 60, updates: [.userPrompt("q"), .thinkingText("\n")])
        ended.controller.handle(.runEnded)
        #expect(ended.controller.state.transcript.items == [.user("q")])
        var tool = PointerRig(columns: 60, updates: [.thinkingText(" ")])
        tool.controller.handle(.toolStarted(name: "shell", summary: "ls", id: "t1", fullInput: "ls"))
        tool.controller.handle(.toolFinished(.succeeded, output: "a", id: "t1"))
        #expect(tool.controller.state.transcript.items.count == 1)
        #expect(tool.controller.state.transcript.isFoldable(0), "the tool kept its index and its output")
    }

    @Test func `reasoning that says something stays, whatever follows it`() {
        var rig = PointerRig(columns: 60, updates: [.thinkingText("\n  why\n")])
        rig.controller.handle(.assistantText("answer"))
        rig.controller.handle(.runEnded)
        #expect(rig.controller.state.transcript.items == [.thinking("\n  why\n"), .assistant("answer")])
    }

    @Test func `a long reasoning is cut and the cut is said`() {
        var rig = PointerRig(
            columns: 60, updates: [.thinkingText((1 ... 1000).map { "t \($0)" }.joined(separator: "\n"))])
        #expect(rig.contentText(row: 9) == "Thinking...")
        rig.click(row: 9, col: 3)
        #expect(rig.contentText(row: 9) == "… 600 more lines not shown")
    }
}
