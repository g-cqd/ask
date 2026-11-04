import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import Testing

@testable import AskTUI

/// Roadmap 0172: what a click acts on brightens under the pointer: a foldable block's header, a job's row in the strip or sidebar, and
/// a picker row. The terminal reports motion only with `ui.hover`; a report that does not change what is hovered draws nothing new.
@Suite("What a click acts on brightens under the pointer")
struct HoverTests {
    private func rig(hover: Bool = true, columns: Int = 60, rows: Int = 14) -> PointerRig {
        var options = ScreenOptions.legacy
        options.hover = hover
        var rig = PointerRig(
            columns: columns,
            rows: rows,
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
        (0 ..< rig.buffer.rows).first { rig.text(row: $0).contains(text) }
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

    @Test func `sidebar rows and picker rows brighten under the pointer`() throws {
        var rig = rig(columns: 90, rows: 16)
        rig.controller.state.runnersOpen = false
        rig.controller.state.sidebarOpen = true
        rig.controller.setScreenRows(16)
        _ = rig.controller.handle(.key(KeyEvent(keyCode: UInt32(UnicodeScalar("/").value))), pageRows: 16)
        rig.draw()
        // On the job's name: the panel is 22 wide, and its text starts after the divider and a space.
        let sidebarCol = 90 - 22 + 2
        // The toggle, main, a gap and the Jobs heading come first; the job is row 4.
        #expect(!rig.buffer[4, sidebarCol].style.bold)
        rig.mouse(.release, .motion, row: 4, col: sidebarCol)
        rig.draw()
        #expect(rig.controller.state.hover == .job("job-1"))
        #expect(!rig.buffer[4, sidebarCol].style.dim && rig.buffer[4, sidebarCol].style.bold)

        let quitRow = try #require(row(containing: "/quit", in: rig))
        #expect(!rig.buffer[quitRow, 1].style.bold)
        rig.mouse(.release, .motion, row: quitRow, col: 2)
        rig.draw()
        if case .picker = rig.controller.state.hover {
            #expect(rig.buffer[quitRow, 1].style.bold)
        } else {
            Issue.record("expected .picker hover, got \(String(describing: rig.controller.state.hover))")
        }
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
