internal import TerminalKitStyle
internal import TerminalKitText
internal import Testing

@testable import AskTUI

/// The first turn waits for the MCP servers it connects (roadmap 0143), and the status bar says so, in ask's own purple; nothing is added
/// to the conversation.
@Suite("The status bar says Connecting MCP...")
struct ConnectingMCPStatusTests {
    private func connecting() -> ScreenController {
        var controller = ScreenController(label: "model")
        controller.state.running = true
        controller.handle(.userPrompt("go"))
        controller.handle(.connectingMCP(true))
        controller.state.statusFrame = 0
        return controller
    }

    private func status(_ controller: ScreenController) -> ScreenComposer.Line {
        ScreenComposer.status(for: controller.state, columns: 80).line
    }

    @Test func `while the servers connect, the mark is the spinner and the words in purple, and no block is added`()
        throws
    {
        let controller = connecting()
        let frame = try #require(controller.state.transcript.spinnerStyle.frames.first)
        let line = status(controller)
        #expect(line.text.hasPrefix(frame + " Connecting MCP... · model"))
        #expect(line.accents.first?.style == StatusLeadingMark.compacting)
        #expect(controller.state.transcript.items == [.user("go")])
        #expect(controller.hasLiveProgress)
    }

    @Test func `the servers settling, or the run ending, puts the usual mark back`() {
        for back: ConversationUpdate in [.connectingMCP(false), .runEnded] {
            var controller = connecting()
            controller.handle(back)
            #expect(!controller.state.connectingMCP, "\(back)")
            #expect(!status(controller).text.contains("Connecting"), "\(back)")
        }
    }
}
