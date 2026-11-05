import TerminalKitRender
import Testing

@testable import AskTUI

/// The sidebar in the bottom band (notes n39, n40; `ui.sidebarLayout`): beside the input, the transcript keeping the whole width. The
/// band is six rows, more when the sidebar needs them, up to a third of the screen; the status line's counts sit at its trailing edge,
/// under the sidebar. `adaptive` takes the band where the full-height sidebar would leave the transcript under 100 columns.
@Suite("The sidebar can share the bottom band with the input")
struct SidebarBandTests {
    private func rig(
        columns: Int = 120,
        rows: Int = 40,
        layout: SidebarLayout = .bottom,
        runners: [RunnerInfo] = []
    ) -> PointerRig {
        var options = ScreenOptions(sidebar: true, prompt: "ask> ", tint: false, separator: true, padding: false)
        options.sidebarLayout = layout
        var rig = PointerRig(columns: columns, rows: rows, options: options, lines: ["short"])
        rig.controller.handle(.runners(runners))
        rig.draw()
        return rig
    }

    private func threads(_ count: Int) -> [RunnerInfo] {
        (1 ... count).map { RunnerInfo(name: "thread-\($0)", detail: "task \($0)", id: "thread-\($0)", kind: .agent) }
    }

    /// The divider's column on `row`, if the sidebar is drawn there.
    private func divider(_ rig: PointerRig, row: Int) -> Int? {
        (0 ..< rig.buffer.columns).first { rig.buffer[row, $0].character == "│" }
    }

    @Test func `the transcript keeps the whole width, and the input and the sidebar share six rows`() {
        let rig = rig()
        let frame = rig.controller.frame
        #expect(frame.transcriptColumns == 120, "no column given up beside the transcript")
        #expect(divider(rig, row: 0) == nil)
        let band = (0 ..< 40).filter { divider(rig, row: $0) == 89 }
        #expect(
            band.count == 6 && band.first == frame.promptRow,
            "six rows, from the input's first, behind a divider at 89"
        )
        #expect(frame.transcriptRows == 40 - 6 - 1 - 2, "the band, the status line and the two rules")
        #expect(band.contains { rig.text(row: $0).contains("◆ main") })
    }

    @Test func `it grows when the sidebar needs more rows, up to a third of the screen`() {
        let rig = rig(runners: threads(12))
        let band = (0 ..< 40).filter { divider(rig, row: $0) != nil }
        #expect(band.count == 13, "a third of 40, though the sidebar would take 14")
        #expect(rig.controller.frame.transcriptRows == 40 - 13 - 1 - 2)
    }

    @Test func `a click on a runner in the band opens its lane`() throws {
        var rig = rig(runners: threads(2))
        let shown = rig
        let row = try #require((0 ..< 40).first { shown.text(row: $0).contains("thread-2 task 2") })
        _ = rig.click(row: row, col: 96)
        #expect(rig.controller.state.lane?.id == "thread-2")
    }

    @Test func `adaptive takes the band where the full sidebar would leave the transcript under 100 columns`() {
        #expect(rig(columns: 120, layout: .adaptive).controller.frame.transcriptColumns == 120)
        #expect(rig(columns: 160, layout: .adaptive).controller.frame.transcriptColumns == 160 - 36 - 1)
        #expect(rig(columns: 120, layout: .full).controller.frame.transcriptColumns == 120 - 30 - 1)
    }

    @Test func `the status line's counts sit at its trailing edge, under the sidebar`() {
        let rig = rig(runners: [RunnerInfo(name: "job-1", detail: "npm run dev")])
        let status = rig.text(row: rig.controller.frame.statusRow)
        #expect(status.trimmingTrailing().hasSuffix("1 job"), "\(status)")
        #expect(rig.controller.frame.runnerColumns.map { $0.lowerBound >= 89 } == true)
        let band = (0 ..< 40).filter { divider(rig, row: $0) != nil }
        // Moved, not repeated: the band has no counts row.
        #expect(!band.contains { rig.text(row: $0).contains("running") })
    }
}

extension String {
    fileprivate func trimmingTrailing() -> Substring {
        var text = Substring(self)
        while text.last == " " { text.removeLast() }
        return text
    }
}
