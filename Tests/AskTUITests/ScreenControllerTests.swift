import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import Testing

@testable import AskTUI

/// The screen's behaviour without a terminal: keys and conversation updates in, state and effects out.
@Suite("The screen controller turns keys into runs, aborts and quits")
struct ScreenControllerTests {
    private func key(_ code: UInt32) -> InputEvent { .key(KeyEvent(keyCode: code)) }
    private func type(_ text: String, into controller: inout ScreenController) {
        for scalar in text.unicodeScalars { _ = controller.handle(key(scalar.value), pageRows: 10) }
    }

    @Test func `submitting starts a run and records the prompt`() {
        var controller = ScreenController(label: "m")
        type("fix it", into: &controller)
        #expect(controller.handle(key(0x0D), pageRows: 10) == [.startRun("fix it")])
        #expect(controller.state.running)
        #expect(controller.state.transcript.items == [.user("fix it")])
    }

    @Test func `a second prompt while a turn runs is visibly queued instead of refused`() {
        var controller = ScreenController(label: "m")
        type("one", into: &controller)
        _ = controller.handle(key(0x0D), pageRows: 10)
        type("two", into: &controller)
        #expect(controller.handle(key(0x0D), pageRows: 10) == [.queuePrompt(id: 0, text: "two", followUp: false)])
        guard case .notice(let text, false) = controller.state.transcript.items.last else {
            Issue.record("expected a notice")
            return
        }
        #expect(text.contains("Queued steering"))
    }

    @Test func `Ctrl-C stops a running turn, Ctrl-D quits only when idle, and Escape does neither`() {
        var controller = ScreenController(label: "m")
        #expect(controller.handle(key(0x1B), pageRows: 10).isEmpty)
        type("go", into: &controller)
        _ = controller.handle(key(0x0D), pageRows: 10)
        #expect(controller.handle(key(0x1B), pageRows: 10).isEmpty, "Escape does not stop a turn")
        #expect(controller.state.running)
        #expect(controller.handle(key(0x03), pageRows: 10) == [.cancelRun])
        #expect(controller.handle(key(0x04), pageRows: 10).isEmpty, "Ctrl-D does not quit mid-turn")
        controller.handle(.runEnded)
        #expect(!controller.state.running)
        #expect(controller.handle(key(0x04), pageRows: 10) == [.quit])
    }

    @Test func `conversation updates build the transcript`() {
        var controller = ScreenController(label: "m")
        controller.handle(.assistantText("Read"))
        controller.handle(.assistantText("ing."))
        controller.handle(.toolStarted(name: "read", summary: "a.swift"))
        controller.handle(.toolFinished(.succeeded))
        controller.handle(.notice("done", isError: false))
        #expect(
            controller.state.transcript.items == [
                .assistant("Reading."), .tool(name: "read", summary: "a.swift", status: .succeeded, output: ""),
                .notice("done", isError: false)
            ])
    }

    @Test func `page keys scroll, and submitting returns to the bottom`() {
        var controller = ScreenController(label: "m")
        _ = controller.handle(key(Key.pageUp.rawValue), pageRows: 7)
        _ = controller.handle(key(Key.pageUp.rawValue), pageRows: 7)
        #expect(controller.state.scrollback == 14)
        _ = controller.handle(key(Key.pageDown.rawValue), pageRows: 7)
        #expect(controller.state.scrollback == 7)
        type("x", into: &controller)
        _ = controller.handle(key(0x0D), pageRows: 7)
        #expect(controller.state.scrollback == 0)
    }

    @Test func `a resumed session's prompts show as the user's, without starting a run`() {
        var controller = ScreenController(label: "m")
        controller.handle(.userPrompt("fix it"))
        controller.handle(.assistantText("Fixed."))
        #expect(controller.state.transcript.items == [.user("fix it"), .assistant("Fixed.")])
        #expect(!controller.state.running)
    }

    @Test func `a status update shows at the right of the status line`() {
        var controller = ScreenController(label: "m")
        controller.handle(.status("↑2.1k ↓55"))
        var buffer = ScreenBuffer(columns: 60, rows: 3)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        let statusRow = String((0 ..< 60).map { buffer[2, $0].character })
        #expect(statusRow.hasPrefix("m · ↑2.1k ↓55"))
    }

    @Test func `a paste lands in the editor`() {
        var controller = ScreenController(label: "m")
        _ = controller.handle(.paste("a\nb"), pageRows: 10)
        #expect(controller.state.editor.text == "a\nb")
    }
}
