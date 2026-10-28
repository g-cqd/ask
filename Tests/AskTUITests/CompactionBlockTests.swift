internal import Testing

@testable import AskTUI

/// A compaction is a block of its own: running with a spinner, then done or failed, folded, opening onto its summary (roadmap 0105).
@Suite("A compaction is a standard block")
struct CompactionBlockTests {
    private func controller(_ updates: [ConversationUpdate]) -> ScreenController {
        var controller = ScreenController(label: "m", options: ScreenOptions())
        for update in updates { controller.handle(update) }
        return controller
    }

    private func rows(_ controller: ScreenController, at index: Int = 0, columns: Int = 70) -> [String] {
        ScreenComposer.lines(
            in: controller.state.transcript, at: index, columns: columns, style: controller.state.blocks
        )
        .map(\.text)
    }

    @Test func `while compacting, it is a running block with a spinner, and the status bar says so as well`() throws {
        let controller = controller([.userPrompt("go"), .compacting(true)])
        guard case .tool(let name, _, .running, _, _) = controller.state.transcript.items.last else {
            Issue.record("expected a running block")
            return
        }
        #expect(name == "compact")
        let frame = try #require(controller.state.transcript.spinnerStyle.frames.first)
        let header = try #require(rows(controller, at: 1).first { $0.contains("compact") })
        #expect(header.contains("earlier messages") && header.hasSuffix(frame))
        #expect(controller.state.compacting && controller.hasLiveProgress)
    }

    @Test func `done, it is folded to a header with the summary's size, and opens onto the summary`() throws {
        var controller = controller([
            .userPrompt("go"), .compacting(true),
            .compactionFinished(.succeeded, text: "The user asked for X.\nWe did Y.\nZ remains.")
        ])
        #expect(!controller.state.compacting)
        let folded = rows(controller, at: 1)
        #expect(folded.contains { $0.contains("compact · earlier messages") && $0.hasSuffix("3 lines · ✓") })
        #expect(!folded.contains { $0.contains("We did Y.") })
        controller.state.transcript.toggleFold(1)
        let open = rows(controller, at: 1)
        #expect(open.contains { $0.contains("We did Y.") }, "the summary is what the block opens onto")
        #expect(controller.state.transcript.contentText(at: 1).contains("Z remains."))
    }

    @Test func `a failed compaction is a failed block that says why when opened, and no notice`() {
        var controller = controller([
            .userPrompt("go"), .compacting(true),
            .compactionFinished(.failed("failed"), text: "the summary request was refused")
        ])
        #expect(controller.state.transcript.items.count == 2, "one block, no extra notice")
        #expect(rows(controller, at: 1).contains { $0.contains("compact") && $0.hasSuffix("✗") })
        controller.state.transcript.toggleFold(1)
        #expect(rows(controller, at: 1).contains { $0.contains("the summary request was refused") })
    }

    @Test func `a resumed session shows its compaction as a done block, without a running phase`() {
        let controller = controller([.userPrompt("go"), .compactionFinished(.succeeded, text: "Summary.")])
        guard case .tool(let name, _, .succeeded, let output, _) = controller.state.transcript.items.last else {
            Issue.record("expected a done block")
            return
        }
        #expect(name == "compact" && output == "Summary." && !controller.hasLiveProgress)
    }

    @Test func `a second compaction is a second block`() {
        let controller = controller([
            .compacting(true), .compactionFinished(.succeeded, text: "One."),
            .compacting(true), .compactionFinished(.succeeded, text: "Two.")
        ])
        #expect(controller.state.transcript.items.count == 2)
        #expect(
            controller.state.transcript.contentText(at: 1).hasSuffix("Two.")
                || controller.state.transcript.contentText(at: 1).contains("compact"))
    }
}
