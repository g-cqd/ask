import TerminalKitText
import Testing

@testable import AskTUI

/// Leaving a lane on a long session (note n29): the main conversation's layout is kept aside while the lane is shown and put back,
/// so coming back lays out what is near the end, not every item of the session (8.6 s for 15,000 items before, in a debug build).
@Suite("Coming back from a lane does not lay out the whole conversation again")
struct LaneLayoutTests {
    private let job = RunnerInfo(name: "job-1", detail: "make", id: "job-1")

    private func longRig() -> PointerRig {
        var updates: [ConversationUpdate] = []
        for turn in 0 ..< 400 {
            updates.append(.userPrompt("question \(turn)"))
            updates.append(.assistantText("An answer to question \(turn), with **some** Markdown in it."))
        }
        var rig = PointerRig(columns: 100, rows: 30, options: ScreenOptions(prompt: "ask> "), updates: updates)
        rig.controller.handle(.runners([job]))
        rig.draw()
        return rig
    }

    private func shown(_ rig: PointerRig) -> [String] { (0 ..< rig.composer.transcriptRows).map { rig.text(row: $0) } }

    @Test func `the layout near the end is kept across the lane, and the rows come back as they were`() {
        var rig = longRig()
        let before = shown(rig)
        let known = rig.composer.transcriptLines.firstKnown
        #expect(known > 700, "only the end of 800 items is laid out to begin with")
        _ = rig.controller.enterLane(job)
        rig.draw()
        rig.controller.leaveLane()
        rig.draw()
        #expect(rig.composer.transcriptLines.firstKnown >= known, "nothing above what was known before is laid out")
        #expect(shown(rig) == before)
    }

    @Test func `what the conversation received during the lane is there when it comes back`() {
        var rig = longRig()
        _ = rig.controller.enterLane(job)
        rig.draw()
        rig.controller.handle(.assistantText(" And one more thing."))
        rig.controller.leaveLane()
        rig.draw()
        #expect(shown(rig).joined().contains("And one more thing."))
        #expect(rig.composer.transcriptLines.firstKnown > 700)
    }
}
