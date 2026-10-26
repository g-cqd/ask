import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import Testing

@testable import AskTUI

@Suite("A session switch clears only the conversation and cannot steal in-flight input")
struct SessionSwitchControllerTests {
    private func submit(_ text: String, to controller: inout ScreenController) -> [ScreenController.Effect] {
        _ = controller.handle(.paste(text), pageRows: 10)
        return controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
    }

    @Test func `clearing a conversation keeps the draft and the active command while removing old display state`() {
        var controller = ScreenController(
            label: "model", commands: [SlashCommand(name: "new", summary: "New")], options: .legacy)
        controller.handle(.userPrompt("Old"))
        controller.handle(.assistantText("Old answer"))
        controller.handle(.status("old usage"))
        _ = submit("/new", to: &controller)
        _ = controller.handle(.key(KeyEvent(keyCode: Key.pageUp.rawValue)), pageRows: 10)
        _ = controller.handle(.paste("typed while the command runs"), pageRows: 10)
        controller.handle(.clearConversation)
        #expect(controller.state.transcript.items.isEmpty)
        #expect(controller.state.detail.isEmpty)
        #expect(controller.state.scrollback == 0)
        #expect(controller.state.editor.text == "typed while the command runs")
        #expect(controller.state.running)
        #expect(controller.state.label == "model")
    }

    @Test func `a coalesced clear and new notice cannot reuse the old layout's revisions`() {
        var controller = ScreenController(label: "m", options: .legacy)
        controller.handle(.notice("Old notice", isError: false))
        var buffer = ScreenBuffer(columns: 30, rows: 4)
        var composer = ScreenComposer()
        _ = composer.compose(controller.state, into: &buffer)
        controller.handle(.clearConversation)
        controller.handle(.notice("New notice", isError: false))
        // The renderer may skip the intermediate empty state.
        _ = composer.compose(controller.state, into: &buffer)
        let line = String((0 ..< buffer.columns).map { buffer[1, $0].character })
        #expect(line.hasPrefix("New notice"))
    }

    @Test(arguments: ["new", "resume", "model"])
    func `a switch command cannot run while a turn and queued input are active`(name: String) {
        var controller = ScreenController(
            label: "m", commands: [SlashCommand(name: name, summary: "Switch")], options: .legacy)
        _ = submit("Start", to: &controller)
        _ = submit("Queued", to: &controller)
        #expect(submit("/" + name, to: &controller).isEmpty)
        #expect(controller.state.running)
        #expect(
            controller.handle(.runEnded) == [.startRun("Queued")], "the refused command did not remove pending input")
    }
}
