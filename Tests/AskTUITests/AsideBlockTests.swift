import TerminalKitCodecs
import TerminalKitInput
import TerminalKitStyle
import Testing

@testable import AskTUI

/// `/btw` (roadmap 0194): an aside is a block of its own colour, headed by the question, open onto its answer at full brightness, and
/// no part of the run: neither the run's end nor the person stopping it touches it.
@Suite("An aside is its own block, beside the run")
struct AsideBlockTests {
    private let ctrlC = InputEvent.key(KeyEvent(keyCode: 3))

    private func running() -> ScreenController {
        var controller = ScreenController(label: "m", options: ScreenOptions())
        _ = controller.begin(.startRun("go"))
        return controller
    }

    private func rows(_ controller: ScreenController, at index: Int) -> [ScreenComposer.Line] {
        ScreenComposer.lines(in: controller.state.transcript, at: index, columns: 70, style: controller.state.blocks)
    }

    private func aside(_ controller: ScreenController) -> Transcript.ToolStatus? {
        for item in controller.state.transcript.items {
            if case .tool("btw", _, let status, _, _) = item { return status }
        }
        return nil
    }

    @Test func `it is headed by the question, open onto the answer, not dim, and in the aside's colour`() throws {
        var controller = running()
        _ = controller.apply(.asideStarted(id: "b", question: "what is X?"))
        _ = controller.apply(.asideFinished(id: "b", .succeeded, answer: "X is **the thing**."))
        let index = try #require(
            controller.state.transcript.items.lastIndex { if case .tool = $0 { true } else { false } }
        )
        #expect(!controller.state.transcript.isFolded(index), "an aside opens, unlike a compaction's summary")
        let lines = rows(controller, at: index)
        #expect(lines.contains { $0.text.contains("btw") && $0.text.contains("what is X?") })
        let answer = try #require(lines.first { $0.text.contains("X is the thing.") })
        #expect(!answer.style.dim)
        #expect(answer.style.bg == controller.state.theme.aside)
        #expect(
            controller.state.theme.aside != controller.state.theme.success
                && controller.state.theme.aside != controller.state.theme.system
        )
    }

    @Test func `the run's end and the person stopping it leave a running aside alone`() {
        var controller = running()
        _ = controller.apply(.asideStarted(id: "b", question: "q"))
        _ = controller.handle(ctrlC, pageRows: 12)
        #expect(aside(controller) == .running, "stopping the turn does not stop the aside")
        _ = controller.apply(.runEnded)
        #expect(aside(controller) == .running, "the turn's end does not end it either")
        _ = controller.apply(.asideFinished(id: "b", .succeeded, answer: "a"))
        #expect(aside(controller) == .succeeded)
    }
}
