import Testing

@testable import AskTUI

/// The live clocks are kept as they change (note n55), so a long session answers "is anything live" and "which tool runs last"
/// from the few live blocks; the answers are those a scan of every block gave.
@Suite("Progress clocks keep the live blocks")
struct ProgressClocksTests {
    @Test func `a clock is live from its start until it ends, is removed or is cleared`() {
        var clocks = ProgressClocks()
        let now = ContinuousClock.now
        clocks[3] = BlockProgress(at: now)
        clocks[7] = BlockProgress(at: now)
        #expect(clocks.live == [3, 7])
        clocks[3]?.ended = now
        #expect(clocks.live == [7])
        #expect(clocks[3]?.ended == now, "an ended clock is kept")
        clocks[7] = nil
        #expect(clocks.live.isEmpty)
        clocks[9] = BlockProgress(at: now)
        clocks.removeAll()
        #expect(clocks.live.isEmpty && clocks.isEmpty)
    }

    @Test func `the transcript's last running tool and live progress come from the live clocks`() {
        var transcript = Transcript()
        for index in 0 ..< 200 {
            transcript.startTool(name: "bash", summary: "step \(index)", id: "t\(index)")
            transcript.finishTool(.succeeded, output: "ok", id: "t\(index)")
        }
        #expect(!transcript.hasLiveProgress)
        #expect(transcript.latestForegroundTool == nil)
        transcript.startTool(name: "bash", summary: "one", id: "a")
        transcript.startTool(name: "read", summary: "two", id: "b")
        #expect(transcript.hasLiveProgress)
        #expect(transcript.latestForegroundTool == transcript.items.count - 1)
        transcript.finishTool(.succeeded, output: "ok", id: "b")
        #expect(transcript.latestForegroundTool == transcript.items.count - 2)
        transcript.finishRunProgress()
        #expect(!transcript.hasLiveProgress && transcript.latestForegroundTool == nil)
    }
}
