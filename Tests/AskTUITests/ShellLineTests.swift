internal import TerminalKitCodecs
internal import TerminalKitInput
internal import Testing

@testable import AskTUI

/// `!` and `!!` in the input (note n56; the owner's answers of 2026-11-11): a shell line runs at once, beside a turn, and `!!`'s result
/// is sent as a message.
@Suite("A line starting with ! runs in your shell")
struct ShellLineTests {
    @Test(arguments: [
        ("!ls -la", SlashInput.shell("ls -la", sends: false)), ("!!git status", .shell("git status", sends: true)),
        ("  !echo hi  ", .shell("echo hi", sends: false)), ("! ls", .shell("ls", sends: false)),
        ("!!", .shell("", sends: true)), (#"\!important"#, .prompt("!important")), ("hi !ls", .prompt("hi !ls"))
    ])
    func `a line is read`(line: String, read: SlashInput) {
        #expect(SlashInput(line) == read, "\(line)")
    }

    private func typed(_ line: String, running: Bool = false) -> (ScreenController, [ScreenController.Effect]) {
        var controller = ScreenController(label: "m", options: .legacy)
        controller.state.running = running
        controller.state.editor.paste(line)
        let effects = controller.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
        return (controller, effects)
    }

    @Test func `it runs at once, idle or during a turn, and is not shown as a message`() {
        for running in [false, true] {
            let (controller, effects) = typed("!!git status", running: running)
            #expect(effects == [.runShell("git status", sends: true)], "running: \(running)")
            #expect(!controller.state.transcript.items.contains { if case .user = $0 { true } else { false } })
            #expect(controller.state.editor.text.isEmpty)
        }
    }

    @Test func `with no command, it says so and runs nothing`() {
        let (controller, effects) = typed("!")
        #expect(effects.isEmpty)
        #expect(
            controller.state.transcript.items.last
                == .notice("Give a command after !, or !! to send its result.", isError: true)
        )
    }

    @Test func `a message the conversation writes is sent as if typed: a turn, or queued behind one`() {
        var idle = ScreenController(label: "m", options: .legacy)
        #expect(idle.handle(.submitPrompt("result")) == [.startRun("result")])
        #expect(idle.state.transcript.items.last == .user("result"))
        var busy = ScreenController(label: "m", options: .legacy)
        _ = busy.handle(.key(KeyEvent(keyCode: 0x61)), pageRows: 10)
        _ = busy.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
        let queued = busy.handle(.submitPrompt("result"))
        #expect(queued.count == 1)
        if case .queuePrompt(_, let text, _)? = queued.first {
            #expect(text == "result")
        } else {
            Issue.record("\(queued)")
        }
    }

    /// The note asked to see the output: a `!` block starts open, whatever `ui.foldTools` says for the model's tools.
    @Test func `a ! command's block starts open, the model's tools as configured`() {
        var controller = ScreenController(label: "m", options: ScreenOptions())
        for (name, id) in [("!", "p"), ("bash", "m")] {
            controller.handle(.toolStarted(name: name, summary: "", id: id, fullInput: "ls", command: ToolCommand()))
            controller.handle(.toolFinished(.succeeded, output: "a\nb\n[exit 0]", id: id))
        }
        #expect(!controller.state.transcript.isFolded(0) && controller.state.transcript.isFolded(1))
        controller.handle(.clearConversation)
        controller.handle(.toolStarted(name: "bash", summary: "", id: "x", fullInput: "ls", command: ToolCommand()))
        controller.handle(.toolFinished(.succeeded, output: "a", id: "x"))
        #expect(
            controller.state.transcript.isFolded(0),
            "a cleared conversation forgets which blocks were the person's"
        )
    }
}
