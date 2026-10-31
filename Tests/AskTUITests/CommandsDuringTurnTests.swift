import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Commands while a turn runs (roadmap 0113): a command that applies at once runs beside the turn, which goes on; one that needs the
/// turn's end is refused as before.
@Suite("Commands that apply at once run beside a running turn")
struct CommandsDuringTurnTests {
    private let model = SlashCommand(name: "model", summary: "Choose a model.", duringTurn: .atOnce)
    private let compact = SlashCommand(name: "compact", summary: "Compact now.")

    private func submit(_ line: String, to controller: inout ScreenController) -> [ScreenController.Effect] {
        for scalar in line.unicodeScalars { _ = controller.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 10) }
        return controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
    }

    private func running() -> ScreenController {
        var controller = ScreenController(label: "m", commands: [model, compact], options: .legacy)
        _ = submit("a long task", to: &controller)
        #expect(controller.state.running)
        return controller
    }

    @Test func `a command that applies at once runs beside the turn, which goes on`() {
        var controller = running()
        #expect(submit("/model other", to: &controller) == [.runCommandBeside(name: "model", arguments: "other")])
        #expect(controller.state.running, "the turn is still running")
        #expect(controller.state.transcript.items.contains(.user("/model other")))
    }

    @Test func `idle, the same command runs as before`() {
        var controller = ScreenController(label: "m", commands: [model], options: .legacy)
        #expect(submit("/model other", to: &controller) == [.runCommand(name: "model", arguments: "other")])
    }

    @Test func `a command that needs the turn's end is still refused while it runs`() {
        var controller = running()
        #expect(submit("/compact", to: &controller).isEmpty)
        #expect(
            controller.state.transcript.items.contains(
                .notice("A turn is still running; press Ctrl+C to stop it first.", isError: false)))
    }
}
