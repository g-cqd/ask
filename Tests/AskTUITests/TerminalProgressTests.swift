internal import Testing

@testable import AskTUI

/// Progress for the terminal (notes n59 and n61; the owner's answers of 2026-11-11): only once a turn, a compaction or a command has
/// run five seconds, as OSC 9;4 where the terminal is known to read it, and as a spinner in the tab's title everywhere.
@Suite("A long action shows in the terminal's tab")
struct TerminalProgressTests {
    @Test(arguments: [
        (["TERM_PROGRAM": "iTerm.app", "TERM_PROGRAM_VERSION": "3.6.0"], true),
        (["TERM_PROGRAM": "iTerm.app", "TERM_PROGRAM_VERSION": "3.10.2"], true),
        (["TERM_PROGRAM": "iTerm.app", "TERM_PROGRAM_VERSION": "3.5.14"], false),
        (["TERM_PROGRAM": "iTerm.app"], false),
        (["TERM_PROGRAM": "ghostty", "TERM_PROGRAM_VERSION": "1.2.0"], true),
        (["TERM_PROGRAM": "ghostty", "TERM_PROGRAM_VERSION": "1.1.3"], false),
        (["TERM_PROGRAM": "Apple_Terminal", "TERM_PROGRAM_VERSION": "455"], false),
        (["TERM_PROGRAM": "WezTerm", "TERM_PROGRAM_VERSION": "20240203-110809-5046fc22"], false),
        (["TERM_PROGRAM": "ghostty", "TERM_PROGRAM_VERSION": "1.2.0", "TMUX": "/tmp/tmux"], false),
        ([:], false)
    ])
    func `OSC 9;4 goes only where it is read as progress, not as a notification`(
        environment: [String: String],
        reads: Bool
    ) {
        #expect(TerminalProgress.isRead(environment: environment) == reads, "\(environment)")
    }

    @Test func `the sequences`() {
        #expect(TerminalProgress.working == Array("\u{1B}]9;4;3\u{1B}\\".utf8))
        #expect(TerminalProgress.done == Array("\u{1B}]9;4;0\u{1B}\\".utf8))
    }

    @Test func `an action is long after five seconds of it, and a new one counts anew`() {
        var action = LongAction()
        let start = ContinuousClock.now
        #expect(action.update(working: false, at: start) == nil)
        #expect(action.update(working: true, at: start) == .zero)
        #expect(action.update(working: true, at: start + .milliseconds(4_999)).map(LongAction.isLong) == false)
        #expect(action.update(working: true, at: start + .seconds(5)).map(LongAction.isLong) == true)
        #expect(action.update(working: false, at: start + .seconds(6)) == nil)
        #expect(action.update(working: true, at: start + .seconds(7)) == .zero)
    }

    @Test func `the tab's spinner steps four times a second, and leads the title`() {
        let frames = ["a", "b", "c"]
        #expect(TerminalProgress.frame(after: .seconds(5), of: frames) == "a")
        #expect(TerminalProgress.frame(after: .milliseconds(5_250), of: frames) == "b")
        #expect(TerminalProgress.frame(after: .milliseconds(5_750), of: frames) == "a")
        #expect(TabTitle.text(name: "login fix", workspace: nil, spinner: "⠋") == "⠋ ask · login fix")
        #expect(TabTitle.text(name: "login fix", workspace: nil, spinner: nil) == "ask · login fix")
    }

    @Test func `working is a turn, a compaction, or a command in the foreground, and not a background job`() {
        var controller = ScreenController(label: "m", options: .legacy)
        #expect(!controller.isWorking)
        controller.state.running = true
        #expect(controller.isWorking)
        controller.state.running = false
        controller.state.compacting = true
        #expect(controller.isWorking)
        controller.state.compacting = false
        controller.handle(.toolStarted(name: "!", summary: "", id: "p", fullInput: "make", command: ToolCommand()))
        #expect(controller.isWorking, "your ! command, outside any turn")
        controller.handle(.toolFinished(.succeeded, output: "started", id: "p", backgroundJob: "job-1"))
        #expect(!controller.isWorking, "once it is a job, it is no longer the action")
    }
}
