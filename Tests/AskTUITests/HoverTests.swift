import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import Testing

@testable import AskTUI

/// Roadmap 0172: what a click acts on brightens under the pointer: a foldable block's header, a job's row. The terminal reports motion
/// only with `ui.hover`; a report that does not change what is hovered draws nothing new.
@Suite("What a click acts on brightens under the pointer")
struct HoverTests {
    private func rig(hover: Bool = true) -> PointerRig {
        var options = ScreenOptions.legacy
        options.hover = hover
        var rig = PointerRig(
            columns: 60,
            rows: 14,
            options: options,
            updates: [
                .toolStarted(name: "bash", summary: "make test", id: "t", command: ToolCommand()),
                .toolFinished(.succeeded, output: "one\ntwo", id: "t")
            ]
        )
        rig.controller.handle(.runners([RunnerInfo(name: "job-1", detail: "sleep 9", id: "job-1")]))
        rig.controller.state.runnersOpen = true
        rig.draw()
        return rig
    }

    private func row(containing text: String, in rig: PointerRig) -> Int? {
        (0 ..< 14).first { rig.text(row: $0).contains(text) }
    }

    private func dim(_ rig: PointerRig, row: Int) -> Bool {
        (0 ..< 8).allSatisfy { rig.buffer[row, $0].style.dim || rig.buffer[row, $0].character == " " }
    }

    @Test func `a block's header and a job's row brighten while the pointer is on them, and dim again when it leaves`()
        throws
    {
        var rig = rig()
        let header = try #require(row(containing: "bash ·", in: rig))
        let job = try #require(row(containing: "job-1", in: rig))
        #expect(dim(rig, row: header) && dim(rig, row: job))
        rig.mouse(.release, .motion, row: header, col: 10)
        rig.draw()
        #expect(!dim(rig, row: header) && dim(rig, row: job))
        rig.mouse(.release, .motion, row: job, col: 3)
        rig.draw()
        #expect(dim(rig, row: header) && !dim(rig, row: job))
        rig.mouse(.release, .motion, row: 0, col: 40)
        rig.draw()
        #expect(rig.controller.state.hover == nil && dim(rig, row: header) && dim(rig, row: job))
    }

    @Test func `motion selects nothing and clicks still work`() throws {
        var rig = rig()
        let header = try #require(row(containing: "bash ·", in: rig))
        rig.mouse(.release, .motion, row: header, col: 10)
        #expect(rig.controller.state.selection == nil)
        rig.draw()
        let folded = rig.controller.state.transcript.isFolded(0)
        rig.click(row: header, col: 10)
        #expect(
            rig.controller.state.transcript.isFolded(0) != folded,
            "the click after hovering still toggles the block"
        )
    }

    @Test func `with ui.hover off the terminal is not asked for motion, and nothing brightens`() throws {
        #expect(modes(for: ScreenOptions.legacy).mouseMotion == ScreenOptions.legacy.mouse)
        var options = ScreenOptions.legacy
        options.hover = false
        #expect(!modes(for: options).mouseMotion)
        var rig = rig(hover: false)
        let header = try #require(row(containing: "bash ·", in: rig))
        rig.mouse(.release, .motion, row: header, col: 10)
        rig.draw()
        #expect(rig.controller.state.hover == nil && dim(rig, row: header))
    }
}
