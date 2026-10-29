import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Commands in the screen: `/help` and `/quit` are the screen's own, others are the conversation's, and a line
/// that is not a command still goes to the model.
@Suite("Slash commands run in the screen, and a prompt still goes to the model")
struct SlashCommandsTests {
    private let config = SlashCommand(name: "config", summary: "Edit settings interactively.", takesChoices: true)

    private func submit(_ line: String, to controller: inout ScreenController, pageRows: Int = 10) -> [ScreenController
        .Effect]
    {
        for scalar in line.unicodeScalars {
            _ = controller.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: pageRows)
        }
        return controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: pageRows)
    }

    private func notices(_ controller: ScreenController) -> [String] {
        controller.state.transcript.items.compactMap {
            if case .notice(let text, _) = $0 { text } else { nil }
        }
    }

    @Test func `a command is shown as typed, runs as a command, and marks the screen busy`() {
        var controller = ScreenController(label: "m", commands: [config], options: .legacy)
        #expect(submit("/config now", to: &controller) == [.runCommand(name: "config", arguments: "now")])
        #expect(controller.state.running)
        #expect(controller.state.transcript.items == [.user("/config now")])
    }

    @Test func `help lists the screen's commands and the conversation's, with their summaries`() {
        var controller = ScreenController(label: "m", commands: [config], options: .legacy)
        #expect(submit("/help", to: &controller).isEmpty)
        #expect(!controller.state.running)
        #expect(
            notices(controller) == [
                [
                    "/help  List commands. Ctrl+C: erase, stop, quit (twice). Ctrl+T/O/G fold. Enter steers.",
                    "/quit  Leave ask, stopping a running turn first.",
                    "/continue  Tell the agent to carry on where it stopped. Also: continue, resume, go ahead, go.",
                    "/follow-up  Queue a message after the agent finishes: /follow-up TEXT.",
                    "/tasks  Show or hide the background jobs that are running.",
                    "/sidebar  Show or hide the runner sidebar (Ctrl+\\). Wide screens only.",
                    "/verbose  Show or hide details: the sandbox, the files read, builds that appeared.",
                    "/config  Edit settings interactively."
                ]
                .joined(separator: "\n")
            ])
        let transcript = controller.state.transcript
        let rows = ScreenComposer.lines(in: transcript, at: 1, columns: 120, style: BlockStyle())
        #expect(rows.count == 11, "eight help entries share two padding rows and the blank row above a tinted block")
        #expect(rows.first?.text == "" && rows.last?.text == "")
    }

    @Test func `quit leaves, and works while a turn is running`() {
        var controller = ScreenController(label: "m", commands: [config], options: .legacy)
        #expect(submit("/quit", to: &controller) == [.quit])
        _ = submit("a prompt", to: &controller)
        #expect(controller.state.running)
        #expect(submit("/quit", to: &controller) == [.quit])
    }

    @Test func `an unknown command is an error notice, not a prompt to the model`() {
        var controller = ScreenController(label: "m", commands: [config], options: .legacy)
        #expect(submit("/confg", to: &controller).isEmpty)
        #expect(!controller.state.running)
        #expect(notices(controller) == ["There is no command /confg; /help lists them."])
    }

    @Test func `a command that is not the screen's own waits for the running turn, as a prompt does`() {
        var controller = ScreenController(label: "m", commands: [config], options: .legacy)
        _ = submit("a prompt", to: &controller)
        #expect(submit("/config now", to: &controller).isEmpty)
        #expect(notices(controller).last?.contains("Ctrl+C") == true)
    }

    @Test func `a bare config command opens its scope choices`() {
        var controller = ScreenController(label: "m", commands: [config], options: .legacy)
        #expect(submit("/config", to: &controller, pageRows: 30) == [.listChoices(command: "config")])
        #expect(controller.state.editor.text == "/config ")
    }

    @Test func `a path or a doubled slash is a prompt`() {
        var controller = ScreenController(label: "m", commands: [config], options: .legacy)
        #expect(submit("/etc/hosts: what is this", to: &controller) == [.startRun("/etc/hosts: what is this")])
        controller.handle(.runEnded)
        #expect(submit("//config is a word", to: &controller) == [.startRun("/config is a word")])
    }
}
