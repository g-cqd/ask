import TerminalKitCodecs
import TerminalKitStyle
import Testing

@testable import AskTUI

/// A colour that tells sessions apart (roadmap 0164): a hue seeded by the session, mixed into the status line's background from the
/// terminal's own page, and nothing at all until the conversation names the session.
@Suite("A session's colour on the status line")
struct SessionColourTests {
    @Test func `the same seed always gives the same hue, and other seeds others`() {
        let one = SessionHue.rgb(seed: "/Users/g/project/20261030T120000Z-1a2b.jsonl")
        #expect(one == SessionHue.rgb(seed: "/Users/g/project/20261030T120000Z-1a2b.jsonl"))
        let hues = Set((0 ..< 50).map { SessionHue.degrees(seed: "/p/session-\($0).jsonl") / 30 })
        #expect(hues.count >= 8, "seeds spread over the wheel: \(hues.sorted())")
    }

    @Test func `the status line takes the colour when the session is named, and drops it when not`() {
        var controller = ScreenController(label: "m", options: .legacy)
        let plain = ScreenComposer.status(for: controller.state).line
        #expect(plain.style.bg == .default)
        controller.handle(.sessionIdentity("/p/a.jsonl"))
        let coloured = ScreenComposer.status(for: controller.state).line
        #expect(coloured.style.bg != .default && coloured.text == plain.text)
        #expect(coloured.style.bg == controller.state.blocks.theme.sessionTint(seed: "/p/a.jsonl"))
        #expect(coloured.accents.allSatisfy { $0.style.bg == coloured.style.bg }, "the mark sits on the colour too")
        controller.handle(.sessionIdentity(nil))
        #expect(ScreenComposer.status(for: controller.state).line.style.bg == .default)
    }
}
