import TerminalKitCodecs
import TerminalKitInput
import TerminalKitStyle
import Testing

@testable import AskTUI

/// A turn the person stops adds no block (roadmap 0142): the blocks still going when they stopped it turn orange, the interruption colour,
/// distinct from a failure's red; results already known are kept.
@Suite("An interruption is a colour, not a block")
struct InterruptionColourTests {
    private let ctrlC = InputEvent.key(KeyEvent(keyCode: 3))

    private func running() -> ScreenController {
        var controller = ScreenController(label: "test", options: ScreenOptions())
        _ = controller.begin(.startRun("go"))
        return controller
    }

    private func tools(_ controller: ScreenController) -> [(status: Transcript.ToolStatus, output: String)] {
        controller.state.transcript.items.compactMap { item in
            if case .tool(_, _, let status, let output, _) = item { return (status, output) }
            return nil
        }
    }

    @Test func `stopping a turn adds no block, and the running tool turns orange at once`() {
        var controller = running()
        _ = controller.apply(.toolStarted(name: "shell", summary: "sleep 9", id: "a"))
        let before = controller.state.transcript.items.count
        #expect(controller.handle(ctrlC, pageRows: 12).contains(.cancelRun))
        #expect(controller.state.transcript.items.count == before, "no Stopping… block")
        #expect(tools(controller).first?.status == .interrupted)
        _ = controller.apply(.runEnded)
        #expect(controller.state.transcript.items.count == before, "nothing added when the turn ends either")
    }

    @Test func `the tool's late result is kept, and it stays orange unless it succeeded`() {
        var controller = running()
        _ = controller.apply(.toolStarted(name: "shell", summary: "a", id: "a"))
        _ = controller.apply(.toolStarted(name: "read", summary: "b", id: "b"))
        _ = controller.handle(ctrlC, pageRows: 12)
        _ = controller.apply(.toolFinished(.failed("cancelled"), output: "partial output", id: "a"))
        _ = controller.apply(.toolFinished(.succeeded, output: "whole file", id: "b"))
        _ = controller.apply(.runEnded)
        let shown = tools(controller)
        #expect(shown.first?.status == .interrupted && shown.first?.output == "partial output")
        #expect(shown.last?.status == .succeeded && shown.last?.output == "whole file")
    }

    @Test func `older finished blocks keep their colours, and a failure stays red`() {
        var controller = running()
        _ = controller.apply(.toolStarted(name: "shell", summary: "a", id: "a"))
        _ = controller.apply(.toolFinished(.failed("[exit 1]"), output: "no", id: "a"))
        _ = controller.apply(.toolStarted(name: "shell", summary: "b", id: "b"))
        _ = controller.handle(ctrlC, pageRows: 12)
        #expect(tools(controller).map(\.status) == [.failed("[exit 1]"), .interrupted])
    }

    @Test func `a thinking block still going is drawn on the interruption tint`() {
        var controller = running()
        _ = controller.apply(.thinkingText("weighing the options"))
        _ = controller.handle(ctrlC, pageRows: 12)
        let transcript = controller.state.transcript
        let index = transcript.items.count - 1
        #expect(transcript.interrupted.contains(index))
        let theme = controller.state.blocks.theme
        let rows = ScreenComposer.lines(in: transcript, at: index, columns: 60, style: controller.state.blocks)
        #expect(!rows.isEmpty && rows.allSatisfy { $0.style.bg == theme.interrupted })
    }

    @Test func `the interruption tint is its own, orange, kept to the page's contrast with the others`() {
        for theme in [ScreenTheme(page: .light), ScreenTheme(page: .dark)] {
            #expect(theme.tints.contains(theme.interrupted))
            #expect(theme.interrupted != theme.failure && theme.interrupted != theme.system)
            #expect(
                theme.tint(for: .tool(name: "shell", summary: "", status: .interrupted, output: ""))
                    == theme.interrupted)
        }
        #expect(ScreenComposer.toolStatusStyle(.interrupted) != ScreenComposer.toolStatusStyle(.failed("x")))
        let metadata = ScreenComposer.blockMetadata(status: .interrupted, output: "", progress: nil)
        #expect(
            metadata.hasSuffix("⊘"),
            "a mark of its own, not the failure's ✗, for a person who cannot tell the colours apart")
    }
}
