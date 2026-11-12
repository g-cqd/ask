internal import Testing

@testable import AskTUI

/// A `#123` that resolved when the message was sent is drawn as a token, as `#t3` is (roadmap 0186), whether or not it is open.
@Suite("A resolved #123 is a token")
struct ResolvedReferenceTokenTests {
    @Test func `the names the conversation resolved join the tokens, and stay`() {
        var controller = ScreenController(label: "m")
        #expect(!controller.state.transcript.tokenNames.contains("#5"))
        _ = controller.handle(.referencesResolved(["#5"]))
        #expect(controller.state.transcript.tokenNames.contains("#5"))
        _ = controller.handle(.referencesResolved(["#9"]))
        #expect(controller.state.transcript.tokenNames.isSuperset(of: ["#5", "#9"]))
    }
}
