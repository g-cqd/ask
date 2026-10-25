import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A prompt put back for editing after going back to before it (`/tree N`, ADR-0093): into an empty editor, and never over a draft.
@Suite("A prompt put back in the editor fills an empty one and never overwrites a draft")
struct FillDraftTests {
    @Test func `an empty editor gets the prompt, with the cursor at its end`() {
        var controller = ScreenController(label: "m")
        controller.handle(.fillDraft("fix the parser\nthen the lexer"))
        #expect(controller.state.editor.text == "fix the parser\nthen the lexer")
        #expect(controller.state.editor.cursor == "fix the parser\nthen the lexer".count)
    }

    @Test func `a draft the person has written stays, and the prompt is shown to them instead`() {
        var controller = ScreenController(label: "m")
        _ = controller.handle(.paste("half a thought"), pageRows: 10)
        controller.handle(.fillDraft("the old prompt"))
        #expect(controller.state.editor.text == "half a thought")
        let notices = controller.state.transcript.items.compactMap { item -> String? in
            if case .notice(let text, _) = item { text } else { nil }
        }
        #expect(notices.contains { $0.contains("draft was kept") && $0.contains("the old prompt") })
    }

    @Test func `a draft of only spaces counts as empty`() {
        var controller = ScreenController(label: "m")
        _ = controller.handle(.paste("  \n "), pageRows: 10)
        controller.handle(.fillDraft("the old prompt"))
        #expect(controller.state.editor.text == "the old prompt")
    }
}
