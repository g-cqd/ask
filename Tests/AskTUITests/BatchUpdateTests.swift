import Testing

@testable import AskTUI

/// A conversation rebuilt at once, as `/rewind` rebuilds it (roadmap 0160), reaches the screen as one update: applied in order, drawn
/// once, not one frame per item.
@Suite("A batch of updates is applied as one")
struct BatchUpdateTests {
    @Test func `a batch applies every update in order, and as if each came alone`() {
        var controller = ScreenController(label: "m", options: .legacy)
        controller.handle(.notice("before", isError: false))
        _ = controller.handle(
            .batch([.clearConversation, .userPrompt("one"), .assistantText("reply"), .fillDraft("again")]))
        #expect(controller.state.transcript.items == [.user("one"), .assistant("reply")])
        #expect(controller.state.editor.text == "again")
    }
}
