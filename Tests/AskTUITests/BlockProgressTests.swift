internal import Foundation
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
        #expect(
            transcript.progress[0]?.duration(localized: true, locale: Locale(identifier: "en_US"))
                == "1 hr, 1 min, 1 sec")
        let frame = transcript.progress[0]?.indicator
        #expect(frame != "|")
        #expect(UnicodeWidth.displayWidth(of: frame ?? "") == 1)
        transcript.finishTool(.succeeded, at: start.advanced(by: .seconds(3662)))
        let revisions = transcript.revisions
        transcript.advanceProgress(at: start.advanced(by: .seconds(9999)))
        #expect(
            transcript.progress[0]?.duration(localized: true, locale: Locale(identifier: "en_US"))
                == "1 hr, 1 min, 2 sec")
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
        guard case .tool(_, _, .failed, _, _) = controller.state.transcript.items[0] else {
            Issue.record("a tool without a result was marked successful or left running")
            return
        }
    }
    @Test func `elapsed labels appear only above one second and omit empty units`() {
        let start = ContinuousClock.now
        var progress = BlockProgress(at: start)
        for milliseconds in [0, 999, 1000] {
            progress.sampled = start.advanced(by: .milliseconds(milliseconds))
            let label: String? = progress.duration
            #expect(label == nil)
        }
        for (milliseconds, expected) in [
            (1001, "1 sec"), (2000, "2 sec"), (60000, "1 min"), (61000, "1 min, 1 sec"),
            (3_600_000, "1 hr"), (3_661_000, "1 hr, 1 min, 1 sec")
        ] {
            progress.sampled = start.advanced(by: .milliseconds(milliseconds))
            #expect(progress.duration(localized: true, locale: Locale(identifier: "en_US")) == expected)
        }
    }

    @Test func `model answers never acquire tool status or elapsed labels`() {
        let rows = ScreenComposer.lines(for: .assistant("An answer"), columns: 60)
        #expect(rows.map(\.text) == ["An answer"])
        #expect(ScreenComposer.blockMetadata(status: .succeeded, output: "", progress: nil) == "✓")
    }

    /// The write and edit tools answer in one sentence; counting it as `1 line` reads as the file's size (roadmap 0078).
    @Test func `a write or an edit acknowledgement shows no line count`() {
        for tool in ["write", "edit"] {
            let said = ScreenComposer.blockMetadata(
                status: .succeeded, output: "Replaced 1 occurrence in a.txt.", progress: nil, toolName: tool)
            #expect(said == "✓", "\(tool)")
        }
        let read = ScreenComposer.blockMetadata(status: .succeeded, output: "one\ntwo", progress: nil, toolName: "read")
        #expect(read == "2 lines · ✓")
    }

    @Test func `clock alternative and locale choice use the same elapsed duration`() {
        let start = ContinuousClock.now
        var progress = BlockProgress(at: start)
        progress.sampled = start.advanced(by: .seconds(6030))
        #expect(progress.duration(localized: false) == "1:40:30")
        #expect(progress.duration(localized: true, locale: Locale(identifier: "en_US")) == "1 hr, 40 min, 30 sec")
        #expect(
            progress.duration(localized: true, locale: Locale(identifier: "fr_FR"))
                != progress.duration(localized: true, locale: Locale(identifier: "en_US")))
        progress.sampled = start.advanced(by: .seconds(61))
        #expect(progress.duration(localized: false) == "1:01")
        progress.sampled = start.advanced(by: .seconds(2))
        #expect(progress.duration(localized: false) == "2")
        let state = ScreenState(label: "m", options: ScreenOptions(localizedDurations: false))
        #expect(!state.blocks.localizedDurations)
    }
}
