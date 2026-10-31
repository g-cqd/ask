import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Commands while a turn runs (roadmap 0113): one that applies at once runs beside the turn, which goes on; one that needs the turn's
/// end waits for it, shown as waiting, and follows the queued messages' rules when the turn is stopped; one refused stays refused.
@Suite("Commands typed during a turn run beside it, or wait for its end")
struct CommandsDuringTurnTests {
    private let model = SlashCommand(name: "model", summary: "Choose a model.", duringTurn: .atOnce)
    private let login = SlashCommand(name: "login", summary: "Sign in.", duringTurn: .atOnce)
    private let compact = SlashCommand(name: "compact", summary: "Compact now.", duringTurn: .afterTurn)
    private let new = SlashCommand(name: "new", summary: "A new session.", duringTurn: .afterTurn)
    private let other = SlashCommand(name: "other", summary: "Refused while a turn runs.")
    private let ctrlC = InputEvent.key(KeyEvent(keyCode: 3))

    private func submit(_ line: String, to controller: inout ScreenController) -> [ScreenController.Effect] {
        for scalar in line.unicodeScalars { _ = controller.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 10) }
        return controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
    }

    private func running(_ options: ScreenOptions = .legacy) -> ScreenController {
        var controller = ScreenController(label: "m", commands: [model, login, compact, new, other], options: options)
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

    @Test func `a command refused during a turn is still refused`() {
        var controller = running()
        #expect(submit("/other", to: &controller).isEmpty)
        #expect(
            controller.state.transcript.items.contains(
                .notice("A turn is still running; press Ctrl+C to stop it first.", isError: false)))
    }

    @Test func `a command that needs the turn's end waits for it, shown as waiting, then runs`() {
        var controller = running()
        #expect(submit("/compact", to: &controller).isEmpty, "nothing runs while the turn does")
        #expect(controller.state.transcript.items.contains(.queued("/compact")))
        #expect(controller.handle(.runEnded) == [.runCommand(name: "compact", arguments: "")])
        #expect(controller.state.running, "the command is now the screen's run")
        #expect(
            controller.state.transcript.items.contains(.user("/compact"))
                && !controller.state.transcript.items.contains(.queued("/compact")))
    }

    @Test func `waiting commands run in order, before a message queued after them`() {
        var controller = running()
        _ = submit("/compact", to: &controller)
        _ = submit("/new fresh", to: &controller)
        _ = controller.queue("then this", followUp: true)
        #expect(controller.handle(.runEnded) == [.runCommand(name: "compact", arguments: "")])
        #expect(controller.handle(.runEnded) == [.runCommand(name: "new", arguments: "fresh")])
        guard case .startRun("then this") = controller.handle(.runEnded).first else {
            Issue.record("the follow-up starts after the commands")
            return
        }
    }

    @Test func `stopped with queuedOnStop none, a waiting command returns to the input and does not run`() {
        var controller = running(ScreenOptions(interruptSendsQueued: .none))
        _ = submit("/compact", to: &controller)
        _ = controller.handle(ctrlC, pageRows: 10)
        #expect(controller.handle(.runEnded).isEmpty)
        #expect(controller.state.editor.text == "/compact")
    }

    @Test func `a question asked by a command beside the turn outlives the turn's end`() {
        var controller = running()
        #expect(submit("/login claude", to: &controller) == [.runCommandBeside(name: "login", arguments: "claude")])
        _ = controller.handle(.askInput(id: 7, prompt: "Paste the code", secret: false))
        _ = controller.handle(.runEnded)
        #expect(controller.state.pendingInput?.id == 7, "the turn ended, the sign-in did not")
        _ = controller.handle(.besideEnded)
        #expect(controller.state.pendingInput == nil, "the command's end takes its question away")
    }

    @Test func `a queued message the conversation refuses goes back to the input, no longer waiting`() {
        var controller = running()
        _ = controller.queue("/skill:missing do it", followUp: false)
        let id = try! #require(controller.pending.first?.id)
        _ = controller.handle(.promptRefused(id: id))
        #expect(controller.pending.isEmpty)
        #expect(controller.state.editor.text == "/skill:missing do it")
        #expect(!controller.state.transcript.items.contains(.queued("/skill:missing do it")))
    }
}
