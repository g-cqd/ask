internal import TerminalKitText
internal import Testing

@testable import AskTUI

@Suite("Monotonic block status")
struct BlockProgressTests {
    @Test func `elapsed time freezes on completion and only live revisions animate`() {
        let start = ContinuousClock.now
        var transcript = Transcript()
        transcript.startTool(name: "bash", summary: "long", at: start)
        transcript.advanceProgress(at: start.advanced(by: .seconds(3661)))
        #expect(transcript.progress[0]?.duration == "01:01:01")
        let frame = transcript.progress[0]?.indicator
        #expect(frame != "|")
        #expect(UnicodeWidth.displayWidth(of: frame ?? "") == 1)
        transcript.finishTool(.succeeded, at: start.advanced(by: .seconds(3662)))
        let revisions = transcript.revisions
        transcript.advanceProgress(at: start.advanced(by: .seconds(9999)))
        #expect(transcript.progress[0]?.duration == "01:01:02")
        #expect(transcript.revisions == revisions)
        #expect(!transcript.hasLiveProgress)
    }

    @Test func `thinking stops on an answer or run end and clearing forgets timers`() {
        var controller = ScreenController(label: "test")
        controller.handle(.thinkingText("why"))
        #expect(controller.hasLiveProgress)
        controller.handle(.assistantText("answer"))
        #expect(!controller.hasLiveProgress)
        controller.handle(.thinkingText("more"))
        controller.handle(.runEnded)
        #expect(!controller.hasLiveProgress)
        controller.state.transcript.removeAll()
        #expect(controller.state.transcript.progress.isEmpty)
    }
    @Test func `an interrupted tool cannot leave a permanent running indicator`() {
        var controller = ScreenController(label: "test")
        controller.handle(.toolStarted(name: "bash", summary: "read"))
        controller.handle(.runEnded)
        #expect(!controller.hasLiveProgress)
        guard case .tool(_, _, .failed, _) = controller.state.transcript.items[0] else {
            Issue.record("a tool without a result was marked successful or left running")
            return
        }
    }
}
