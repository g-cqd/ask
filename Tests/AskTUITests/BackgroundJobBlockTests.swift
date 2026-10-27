import TerminalKitStyle
import TerminalKitText
import Testing

@testable import AskTUI

@Suite("A yielded job continues in its original foldable tool block")
struct BackgroundJobBlockTests {
    private let start = ContinuousClock.now

    private func controller() -> ScreenController {
        var controller = ScreenController(label: "test")
        controller.handle(.toolStarted(name: "bash", summary: "build", id: "tool-a"))
        #expect(
            controller.handle(.toolFinished(.succeeded, output: "initial", id: "tool-a", backgroundJob: "job-1"))
                == [.watchJob(id: "job-1")])
        return controller
    }

    private func snapshot(_ status: Transcript.ToolStatus = .running) -> JobUpdate {
        JobUpdate(
            id: "job-1", label: "#7a2f", output: "initial\nnew output", status: status,
            startedAt: start, endedAt: status == .running ? nil : start + .seconds(12), lines: 45)
    }

    @Test func `updates replace the originating tool without touching a newer call or its folds`() {
        var controller = controller()
        controller.state.transcript.toggleFold(0)
        controller.handle(.assistantText("answer"))
        controller.handle(.toolStarted(name: "read", summary: "next", id: "tool-b"))
        controller.handle(.jobOutput(snapshot()))
        #expect(
            controller.state.transcript.items[0]
                == .tool(
                    name: "bash", summary: "[#7a2f] build", status: .running, output: "initial\nnew output"))
        #expect(
            controller.state.transcript.items[2] == .tool(name: "read", summary: "next", status: .running, output: ""))
        #expect(!controller.state.transcript.isFolded(0))
        controller.handle(.toolFinished(.succeeded, output: "read done", id: "tool-b"))
        controller.handle(.runEnded)
        #expect(controller.state.transcript.progress[0]?.ended == nil)
        #expect(controller.hasLiveProgress)
    }

    @Test func `focused output and main job updates are independent`() {
        var controller = controller()
        controller.handle(.runners([RunnerInfo(name: "job-1", detail: "build")]))
        _ = controller.enterLane(RunnerInfo(name: "job-1", detail: "build"))
        controller.handle(.runnerOutput(id: "job-1", text: "lane text"))
        controller.handle(.jobOutput(snapshot()))
        #expect(controller.state.transcript.items == [.notice("lane text", isError: false)])
        controller.leaveLane()
        #expect(controller.state.transcript.contentText(at: 0).contains("[#7a2f]"))
        #expect(controller.state.transcript.isFolded(0))
    }

    @Test func `completion appends one faint italic block with right aligned metadata and freezes time`() throws {
        var controller = controller()
        let ending = snapshot(.failed("[exit 7]"))
        controller.handle(.jobOutput(ending))
        controller.handle(.jobOutput(ending))
        let transcript = controller.state.transcript
        try #require(transcript.items.count == 2)
        #expect(transcript.items[1] == .jobEnded(label: "[#7a2f] ended", status: .failed("[exit 7]"), lines: 45))
        let style = BlockStyle(padded: false, theme: ScreenTheme(), localizedDurations: false)
        let rows = ScreenComposer.lines(
            for: transcript.items[1], block: 1, columns: 70,
            style: style, progress: transcript.progress[1])
        #expect(rows[0].style.dim && rows[0].style.italic)
        #expect(rows[0].text.hasPrefix("[#7a2f] ended    "))
        #expect(rows[0].text.hasSuffix("12 · 45 lines · [7] ✗"))
        #expect(UnicodeWidth.displayWidth(of: rows[0].text) == 70)
        controller.advanceProgress(at: start + .seconds(99))
        #expect(controller.state.transcript.progress[1] == transcript.progress[1])
    }

    @Test func `unknown and cleared jobs cannot modify another transcript`() {
        var controller = ScreenController(label: "test")
        controller.handle(.jobOutput(snapshot()))
        #expect(controller.state.transcript.items.isEmpty)
        controller = self.controller()
        controller.handle(.clearConversation)
        controller.handle(.jobOutput(snapshot(.succeeded)))
        #expect(controller.state.transcript.items.isEmpty)
    }

    @Test func `job snapshots stay bounded and keep copy provenance on updated body rows`() {
        var controller = controller()
        controller.state.transcript.toggleFold(0)
        let output = (0 ..< 600).map { "line \($0)" }.joined(separator: "\n")
        controller.handle(
            .jobOutput(JobUpdate(id: "job-1", label: "#7a2f", output: output, status: .running, startedAt: start)))
        let transcript = controller.state.transcript
        #expect(transcript.contentText(at: 0).contains("… 200 more lines not shown"))
        let rows = ScreenComposer.lines(for: transcript.items[0], columns: 80)
        #expect(rows[2].source?.col == 0 && rows[2].source?.text == "line 0")
    }
}
