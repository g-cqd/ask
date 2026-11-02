internal import TerminalKitRender
internal import Testing

@testable import AskTUI

/// Roadmap 0067, phase 4: what a running tool says of how far it has got is shown on its header's right, before its time and spinner,
/// and goes when the tool ends.
@Suite("A running tool's progress is shown on its header until it ends")
struct ToolProgressNoteTests {
    private func header(_ rig: PointerRig) -> String {
        (0 ..< rig.buffer.rows).map { rig.text(row: $0) }.first { $0.contains("index") } ?? ""
    }

    @Test func `a report shows on the running block's header, and the end clears it`() {
        var rig = PointerRig(
            columns: 60,
            updates: [.toolStarted(name: "mcp__srv__index", summary: "index", id: "c1")]
        )
        rig.controller.handle(.toolProgress(id: "c1", text: "25% · reading files"))
        rig.draw()
        #expect(header(rig).contains("25% · reading files"), "\(header(rig))")
        rig.controller.handle(.toolProgress(id: "c1", text: "50%"))
        rig.draw()
        #expect(header(rig).contains("50%") && !header(rig).contains("reading"))
        rig.controller.handle(.toolFinished(.succeeded, output: "done", id: "c1"))
        rig.draw()
        #expect(!header(rig).contains("50%"), "\(header(rig))")
    }

    @Test func `a report for a call that is not running, or not there, changes nothing`() {
        var transcript = Transcript()
        transcript.startTool(name: "t", summary: "s", id: "a")
        transcript.finishTool(.succeeded, output: "", id: "a")
        let revision = transcript.revisions
        transcript.noteProgress("late", id: "a")
        transcript.noteProgress("nowhere", id: "b")
        #expect(transcript.revisions == revision && transcript.progress.values.allSatisfy { $0.note == nil })
    }

    @Test func `the same report again is no change, so nothing is drawn again`() {
        var transcript = Transcript()
        transcript.startTool(name: "t", summary: "s", id: "a")
        transcript.noteProgress("10%", id: "a")
        let revision = transcript.revisions
        transcript.noteProgress("10%", id: "a")
        #expect(transcript.revisions == revision)
    }
}
