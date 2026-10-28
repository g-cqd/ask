internal import TerminalKitStyle
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// A dropped connection is said by the status bar, not by a block in the conversation.
@Suite("The status bar says Reconnecting...")
struct ReconnectingStatusTests {
    private func reconnecting() -> ScreenController {
        var controller = ScreenController(label: "model")
        controller.state.running = true
        controller.handle(.userPrompt("go"))
        controller.handle(.reconnecting(true))
        controller.state.statusFrame = 0
        return controller
    }

    private func status(_ controller: ScreenController) -> ScreenComposer.Line {
        ScreenComposer.status(for: controller.state, columns: 80).line
    }

    @Test
    func
        `while reconnecting, the mark is the spinner and the word in the warning colour, and nothing is added to the conversation`()
        throws
    {
        let controller = reconnecting()
        let frame = try #require(controller.state.transcript.spinnerStyle.frames.first)
        let line = status(controller)
        #expect(line.text.hasPrefix(frame + " Reconnecting... · model"))
        #expect(line.accents.first?.style == StatusLeadingMark.warning)
        #expect(line.accents.first?.columns == 0 ..< UnicodeWidth.displayWidth(of: frame + " Reconnecting..."))
        #expect(controller.state.transcript.items == [.user("go")], "no block says the connection dropped")
        #expect(controller.hasLiveProgress)
    }

    @Test func `the model answering again, or the run ending, puts the usual mark back`() {
        for back: ConversationUpdate in [.assistantText("hi"), .thinkingText("hm"), .status("↑1 ↓2"), .runEnded] {
            var controller = reconnecting()
            controller.handle(back)
            #expect(!controller.state.reconnecting, "\(back)")
            #expect(!status(controller).text.contains("Reconnecting"), "\(back)")
        }
    }

    @Test func `something else arriving meanwhile does not end it`() {
        var controller = reconnecting()
        controller.handle(.runners([]))
        #expect(controller.state.reconnecting)
    }

    @Test func `a compaction under way is what the mark says`() {
        var controller = reconnecting()
        controller.handle(.compacting(true))
        #expect(status(controller).text.contains("Compacting...") && !status(controller).text.contains("Reconnecting"))
    }
}
