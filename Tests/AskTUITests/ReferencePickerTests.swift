import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Roadmap 0186: a `#` that starts a word lists the session's tasks and ideas, asked for once and kept fresh as the command lists are;
/// choosing one puts it in place, and a known one is drawn as a token.
@Suite("A # word offers the tasks and ideas, and a known one is a token")
struct ReferencePickerTests {
    private static let rows = [
        ChoiceRow(label: "#t1", detail: "[open] write the parser", arguments: "#t1"),
        ChoiceRow(label: "#i2", detail: "[new] fold the sidebar", arguments: "#i2")
    ]

    private func type(_ text: String, into screen: inout ScreenController) -> [ScreenController.Effect] {
        var effects: [ScreenController.Effect] = []
        for scalar in text.unicodeScalars {
            effects += screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30)
        }
        return effects
    }

    private func screen() -> ScreenController {
        var screen = ScreenController(label: "m", commands: [])
        screen.setScreenRows(30)
        return screen
    }

    @Test func `the first # asks for the list, which then narrows, and a choice is inserted with a space`() {
        var screen = screen()
        #expect(type("see #", into: &screen).contains(.listChoices(command: "#")))
        _ = screen.handle(.choices(command: "#", rows: Self.rows))
        _ = type("t", into: &screen)
        #expect(screen.state.picker?.matches.map(\.label) == ["#t1"])
        _ = screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        #expect(screen.state.editor.text == "see #t1 ")
    }

    @Test func `a # inside a word or a heading mark opens nothing`() {
        var screen = screen()
        _ = screen.handle(.choices(command: "#", rows: Self.rows))
        _ = type("a#t", into: &screen)
        #expect(screen.state.picker == nil)
    }

    @Test func `a known reference is drawn as a token in the sent message, an unknown one is not`() {
        var screen = screen()
        _ = screen.handle(.choices(command: "#", rows: Self.rows))
        #expect(screen.state.transcript.tokenNames.contains("#t1"))
        #expect(SkillTokens.ranges(in: "do #t1 and #t9", known: screen.state.transcript.tokenNames) == [3 ..< 6])
    }
}
