import TerminalKitCodecs
import TerminalKitInput
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

    @Test func `a second prompt while a turn runs is refused with a notice, not queued silently`() {
        var controller = ScreenController(label: "m")
        type("one", into: &controller)
        _ = controller.handle(key(0x0D), pageRows: 10)
        type("two", into: &controller)
        #expect(controller.handle(key(0x0D), pageRows: 10).isEmpty)
        guard case .notice(let text, false) = controller.state.transcript.items.last else {
            Issue.record("expected a notice")
            return
        }
        #expect(text.contains("Esc"))
    }

    @Test func `escape and Ctrl-C abort a running turn; idle, Ctrl-C and Ctrl-D quit`() {
        var controller = ScreenController(label: "m")
        #expect(controller.handle(key(0x1B), pageRows: 10).isEmpty)
        type("go", into: &controller)
        _ = controller.handle(key(0x0D), pageRows: 10)
        #expect(controller.handle(key(0x1B), pageRows: 10) == [.cancelRun])
        #expect(controller.handle(key(0x03), pageRows: 10) == [.cancelRun])
        #expect(controller.handle(key(0x04), pageRows: 10).isEmpty, "Ctrl-D does not quit mid-turn")
        controller.handle(.runEnded)
        #expect(!controller.state.running)
        #expect(controller.handle(key(0x03), pageRows: 10) == [.quit])
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
                .assistant("Reading."), .tool(name: "read", summary: "a.swift", status: .succeeded),
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

    @Test func `a paste lands in the editor`() {
        var controller = ScreenController(label: "m")
        _ = controller.handle(.paste("a\nb"), pageRows: 10)
        #expect(controller.state.editor.text == "a b")
    }
}
