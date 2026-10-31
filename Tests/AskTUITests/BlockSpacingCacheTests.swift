import Testing

@testable import AskTUI

/// A block's blank row above depends on the block before it, so a block changed in place must lay its follower out again: a queued
/// message sent while a tool ran below it becomes the user's message, and the tool must then be set apart from it as from any other.
@Suite("A block changed in place re-spaces the block after it")
struct BlockSpacingCacheTests {
    private func window(_ composer: inout ScreenComposer, _ state: ScreenState) -> [ScreenComposer.Line] {
        composer.transcriptWindow(state.transcript, columns: 60, style: state.blocks, rows: 40, rowsFromEnd: 0)
    }

    @Test func `a queued message sent after a tool started below it leaves a blank row between them`() {
        var controller = ScreenController(label: "test")
        _ = controller.begin(.startRun("initial"))
        _ = controller.queue("next action", followUp: false)
        controller.handle(.toolStarted(name: "bash", summary: "ls"))
        controller.handle(.toolFinished(.succeeded, output: "a"))
        var cached = ScreenComposer()
        _ = window(&cached, controller.state)
        controller.handle(.promptAccepted(id: 0, text: "next action"))
        var fresh = ScreenComposer()
        let expected = window(&fresh, controller.state)
        #expect(window(&cached, controller.state) == expected)
    }
}
