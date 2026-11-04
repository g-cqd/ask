import Testing

@testable import AskTUI

/// The blocks a thread leaves in the conversation it was forked from (roadmap 0195): where it started, open and in the aside's colour,
/// and where it merged, folded until opened onto its summary; and how the sidebar marks a thread held, merging or merged.
@Suite("A thread marks where it started and where it merged")
struct ThreadBlocksTests {
    private func controller() -> ScreenController {
        var controller = ScreenController(label: "m", options: .legacy)
        controller.setScreenRows(30)
        return controller
    }

    @Test func `where it started is an open block of its own colour, saying how to follow it`() throws {
        var controller = controller()
        _ = controller.handle(.threadStarted(id: "fork-thread-1", name: "thread-1", prompt: "look into X"))
        let transcript = controller.state.transcript
        let index = try #require(transcript.items.indices.last)
        guard case .tool(let name, let summary, _, let output, _) = transcript.items[index] else {
            Issue.record("not a block")
            return
        }
        #expect(name == "thread-1" && summary == "started here · look into X")
        #expect(output.contains("Open it from the sidebar"))
        #expect(transcript.asideBlocks.contains(index) && !transcript.isFolded(index))
    }

    @Test func `where it merged is a folded block that opens onto its summary, in main or in a parent thread`() throws {
        var controller = controller()
        _ = controller.handle(
            .threadMerged(id: "merge-thread-1", name: "thread-1", prompt: "look into X", summary: "It is fine.")
        )
        let transcript = controller.state.transcript
        let index = try #require(transcript.items.indices.last)
        guard case .tool(_, let summary, _, let output, _) = transcript.items[index] else {
            Issue.record("not a block")
            return
        }
        #expect(summary == "merged · look into X" && output == "It is fine.")
        #expect(transcript.summaryBlocks.contains(index) && transcript.isFolded(index))
        _ = controller.handle(.runners([RunnerInfo(name: "thread-1", detail: "x", id: "thread-1", kind: .agent)]))
        _ = controller.handle(
            .thread(id: "thread-1", .threadMerged(id: "merge-thread-2", name: "thread-2", prompt: "y", summary: "z"))
        )
        #expect(
            controller.state.transcript.items.count == transcript.items.count,
            "a parent thread's merge is drawn in its lane"
        )
        #expect(controller.state.threads["thread-1"]?.transcript.items.count == 1)
    }

    @Test func `the sidebar marks a held, a merging and a merged thread`() {
        var rig = PointerRig(columns: 100, rows: 20, options: ScreenOptions(sidebar: true, prompt: "ask> "))
        rig.controller.handle(
            .runners([
                RunnerInfo(name: "thread-1", detail: "a", id: "thread-1", kind: .agent, state: .held),
                RunnerInfo(name: "thread-2", detail: "b", id: "thread-2", kind: .agent, state: .merged)
            ])
        )
        rig.draw()
        let text = (0 ..< 6).map { rig.text(row: $0) }.joined(separator: "\n")
        #expect(text.contains("├ ◌ thread-1 a") && text.contains("└ ✓ thread-2 b"))
        #expect(rig.text(row: rig.composer.transcriptRows - 1).hasSuffix("Nothing running"), "neither is running")
    }
}
