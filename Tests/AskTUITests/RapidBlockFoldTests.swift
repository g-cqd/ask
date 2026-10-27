import Testing

@testable import AskTUI

@Suite("Rapid fold clicks remain toggles rather than word selections")
struct RapidBlockFoldTests {
    @Test(arguments: [true, false])
    func `rapid consecutive clicks fold and unfold the same block`(thinking: Bool) throws {
        var rig = PointerRig(columns: 80, rows: 20, options: ScreenOptions())
        if thinking {
            rig.controller.handle(.thinkingText("first thought\nsecond thought"))
        } else {
            rig.controller.handle(.toolStarted(name: "bash", summary: "command"))
            rig.controller.handle(.toolFinished(.succeeded, output: "first\nsecond"))
        }
        rig.draw()
        for expected in [false, true, false, true] {
            let row = try #require(rig.controller.frame.foldBlocks.lastIndex { $0 == 0 })
            #expect(rig.click(row: row, col: 1, after: .milliseconds(50)).isEmpty)
            #expect(rig.controller.state.transcript.isFolded(0) == expected)
            #expect(rig.controller.state.selection == nil)
        }
    }
}
