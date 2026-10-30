internal import TerminalKitStyle
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// With the network gone, the status bar says ask is waiting for it (roadmap 0141), not a block; the model answering again or the run
/// ending puts the usual mark back.
@Suite("The status bar says Offline")
struct OfflineStatusTests {
    private func offline() -> ScreenController {
        var controller = ScreenController(label: "model")
        controller.state.running = true
        controller.handle(.userPrompt("go"))
        controller.handle(.waitingForNetwork)
        controller.state.statusFrame = 0
        return controller
    }

    @Test func `while offline, the mark is the spinner and the words in the warning colour, and no block is added`()
        throws
    {
        let controller = offline()
        let frame = try #require(controller.state.transcript.spinnerStyle.frames.first)
        let line = ScreenComposer.status(for: controller.state, columns: 80).line
        #expect(line.text.hasPrefix(frame + " Offline, waiting for the network... · model"))
        #expect(line.accents.first?.style == StatusLeadingMark.warning)
        #expect(controller.state.transcript.items == [.user("go")])
    }

    @Test func `the next attempt, the model answering, or the run ending clears it`() {
        for back: ConversationUpdate in [.reconnecting(true), .assistantText("hi"), .runEnded] {
            var controller = offline()
            controller.handle(back)
            #expect(!controller.state.waitingForNetwork, "\(back)")
        }
    }
}
