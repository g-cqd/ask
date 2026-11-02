import TerminalKitStyle
import TerminalKitText
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
            in: controller.state.transcript,
            at: index,
            columns: columns,
            style: controller.state.blocks
        )
        .map(\.text)
    }

    @Test func `while compacting, it is a running block with a spinner, and the status bar says so as well`() throws {
        let controller = controller([.userPrompt("go"), .compacting(true)])
        guard case .tool(let name, _, .running, _, _) = controller.state.transcript.items.last else {
            Issue.record("expected a running block")
            return
        }
        #expect(name == "compaction")
        let frame = try #require(controller.state.transcript.spinnerStyle.frames.first)
        let header = try #require(rows(controller, at: 1).first { $0.contains("compaction") })
        #expect(header.contains("earlier messages") && header.hasSuffix(frame))
        #expect(controller.state.compacting && controller.hasLiveProgress)
    }

    @Test func `done, it is folded to a header with the summary's size, and opens onto the summary`() throws {
        var controller = controller([
            .userPrompt("go"), .compacting(true),
            .compactionFinished(
                .succeeded,
                text: "The user asked for X.\nWe did Y.\nZ remains.",
                tokens: "182k → 3.1k tokens"
            )
        ])
        #expect(!controller.state.compacting)
        let folded = rows(controller, at: 1)
        #expect(folded.contains { $0.contains("compaction · 182k → 3.1k tokens") && $0.hasSuffix("3 lines · ✓") })
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
        #expect(rows(controller, at: 1).contains { $0.contains("compaction · earlier messages") && $0.hasSuffix("✗") })
        controller.state.transcript.toggleFold(1)
        #expect(rows(controller, at: 1).contains { $0.contains("the summary request was refused") })
    }

    @Test func `a resumed session shows its compaction as a done block, without a running phase`() {
        let controller = controller([.userPrompt("go"), .compactionFinished(.succeeded, text: "Summary.")])
        guard case .tool(let name, _, .succeeded, let output, _) = controller.state.transcript.items.last else {
            Issue.record("expected a done block")
            return
        }
        #expect(name == "compaction" && output == "Summary." && !controller.hasLiveProgress)
    }

    @Test func `a second compaction is a second block`() {
        let controller = controller([
            .compacting(true), .compactionFinished(.succeeded, text: "One."),
            .compacting(true), .compactionFinished(.succeeded, text: "Two.")
        ])
        #expect(controller.state.transcript.items.count == 2)
        #expect(
            controller.state.transcript.contentText(at: 1).hasSuffix("Two.")
                || controller.state.transcript.contentText(at: 1).contains("compaction")
        )
    }

    @Test func `opened, the summary is drawn as Markdown and dim, and copies as written`() throws {
        var controller = controller([
            .userPrompt("go"), .compacting(true),
            .compactionFinished(.succeeded, text: "## Goal\n\n- **Ship** the parser", tokens: "9k → 1k tokens")
        ])
        controller.state.transcript.toggleFold(1)
        let lines = ScreenComposer.lines(
            in: controller.state.transcript,
            at: 1,
            columns: 70,
            style: controller.state.blocks
        )
        let heading = try #require(lines.first { $0.text.contains("Goal") })
        #expect(!heading.text.contains("##"), "the heading's marks are drawn, not shown")
        let item = try #require(lines.first { $0.text.contains("Ship") })
        #expect(!item.text.contains("**"))
        #expect(item.style.dim, "the summary reads as secondary text, as reasoning does")
        // A selection maps rows to the block's text: line 0 is the header, the summary starts at line 1.
        let summaryRows = lines.drop { !$0.text.contains("Goal") }
        #expect(heading.segments.first.map { $0.line == 1 } ?? (heading.source?.line == 1))
        #expect(
            summaryRows.allSatisfy { row in row.segments.allSatisfy { $0.line >= 1 } && (row.source?.line ?? 1) >= 1 }
        )
        #expect(
            item.segments.contains { $0.line == 3 } || item.source?.line == 3,
            "the list item is the summary's third line"
        )
        #expect(controller.state.transcript.contentText(at: 1).hasSuffix("- **Ship** the parser"))
    }

    @Test func `with Markdown off, the summary is shown as written`() {
        var options = ScreenOptions()
        options.markdown = false
        var controller = ScreenController(label: "m", options: options)
        for update: ConversationUpdate in [.compacting(true), .compactionFinished(.succeeded, text: "## Goal")] {
            controller.handle(update)
        }
        controller.state.transcript.toggleFold(0)
        #expect(rows(controller, at: 0).contains { $0.contains("## Goal") })
    }

    @Test func `a compaction the person interrupts ends orange, as other interrupted blocks do`() {
        var controller = controller([.userPrompt("go"), .compacting(true)])
        controller.state.transcript.interruptRunning()
        guard case .tool(_, _, .interrupted, _, _) = controller.state.transcript.items.last else {
            Issue.record("expected an interrupted block")
            return
        }
    }

    /// Like a thinking block, whatever tools do (the owner's choice, 2026-11-02): the summary is long and read rarely.
    @Test func `it starts folded even when tool blocks start open, and still opens`() {
        var controller = controller([.userPrompt("go")])
        controller.state.transcript.setToolsFoldedByDefault(false)
        controller.handle(.compacting(true))
        controller.handle(
            .compactionFinished(.succeeded, text: "The user asked for X.\nWe did Y.", tokens: "182k → 3.1k tokens")
        )
        let index = controller.state.transcript.items.count - 1
        #expect(controller.state.transcript.isFolded(index))
        #expect(!rows(controller, at: index).contains { $0.contains("We did Y.") })
        controller.state.transcript.toggleFold(index)
        #expect(!controller.state.transcript.isFolded(index))
        controller.state.transcript.setToolsFoldedByDefault(true)
        #expect(!controller.state.transcript.isFolded(index), "a new tools default leaves the choice made on it")
    }
}
