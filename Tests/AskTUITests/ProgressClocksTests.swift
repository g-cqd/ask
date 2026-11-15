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

    /// The clocks answer as one dictionary of them would, whatever is done to them and in whatever order: started, ticked, ended,
    /// started again where one had ended (a job's block), removed, cleared. The steps come from a fixed sequence, so a failure
    /// is the same failure every run.
    @Test func `whatever is done to them, the clocks answer as one dictionary would`() {
        var clocks = ProgressClocks()
        var model: [Int: BlockProgress] = [:]
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let start = ContinuousClock.now
        for step in 0 ..< 4_000 {
            let index = next(40)
            let instant = start + .milliseconds(step)
            switch next(10) {
                case 0, 1, 2:
                    clocks[index] = BlockProgress(at: instant)
                    model[index] = BlockProgress(at: instant)
                case 3, 4:
                    clocks[index]?.ended = instant
                    model[index]?.ended = instant
                case 5, 6, 7:
                    clocks[index]?.sampled = instant
                    clocks[index]?.frame += 1
                    model[index]?.sampled = instant
                    model[index]?.frame += 1
                case 8:
                    clocks[index] = nil
                    model[index] = nil
                default:
                    guard next(40) == 0 else { continue }
                    clocks.removeAll(keepingCapacity: true)
                    model.removeAll()
            }
            #expect(clocks[index] == model[index], "step \(step)")
            #expect(clocks.live == Set(model.filter { $0.value.ended == nil }.keys), "step \(step)")
            #expect(clocks.isEmpty == model.isEmpty, "step \(step)")
        }
        for index in 0 ..< 40 { #expect(clocks[index] == model[index], "clock \(index)") }
        #expect(clocks.values.count == model.count)
    }

    /// What a tick touches (diary 2026-11-15-12): the render thread holds the last frame's state, so a clock that changes copies
    /// the store it is in. The clocks that have ended are in a store of their own, which a tick leaves alone.
    @Test func `a tick changes only the clocks that run, and an ended clock is not among them`() {
        var clocks = ProgressClocks()
        let now = ContinuousClock.now
        for index in 0 ..< 100 {
            clocks[index] = BlockProgress(at: now)
            clocks[index]?.ended = now
        }
        clocks[100] = BlockProgress(at: now)
        #expect(clocks.running.count == 1 && clocks.ended.count == 100)
        clocks[100]?.frame += 1
        #expect(clocks.running[100]?.frame == 1 && clocks.ended.count == 100)
        // A clock that ends moves; one started again where one had ended moves back.
        clocks[100]?.ended = now
        #expect(clocks.running.isEmpty && clocks.ended.count == 101)
        clocks[7] = BlockProgress(at: now)
        #expect(clocks.running.keys.sorted() == [7] && clocks.ended.count == 100 && clocks.live == [7])
    }
}
