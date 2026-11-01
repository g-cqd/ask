import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A draft to edit (roadmap 0180): `/ideas i1 TEXT` in the input with the list closed, since the idea's own words match its row and an
/// open list would take Enter.
@Suite
struct EditDraftTests {
    private func screen() -> ScreenController {
        var screen = ScreenController(
            label: "m",
            commands: [SlashCommand(name: "ideas", summary: "Show the ideas.", takesChoices: true)]
        )
        screen.setScreenRows(30)
        _ = screen.handle(
            .choices(command: "ideas", rows: [ChoiceRow(label: "i1", detail: "keep it", arguments: "i1")])
        )
        return screen
    }

    @Test func `a draft to edit leaves the list closed while it is typed in, and Enter runs it`() {
        var screen = screen()
        _ = screen.handle(.editDraft("/ideas i1 keep it"))
        #expect(screen.state.picker == nil && screen.state.editor.text == "/ideas i1 keep it")
        // Words the row holds too, so a list open again would match it and take Enter.
        for scalar in " it".unicodeScalars { _ = screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30) }
        #expect(screen.state.picker == nil)
        let effects = screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        #expect(effects.contains(.runCommand(name: "ideas", arguments: "i1 keep it it")))
    }

    @Test func `the same draft filled as usual opens the list, which is why editing needs its own`() {
        var screen = screen()
        _ = screen.handle(.fillDraft("/ideas i1 keep it"))
        #expect(screen.state.picker?.matches.map(\.label) == ["i1"])
    }

    @Test func `once the edit is kept, the list opens again with the new words`() {
        var screen = screen()
        _ = screen.handle(.editDraft("/ideas i1 keep it"))
        for scalar in " more".unicodeScalars { _ = screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30) }
        _ = screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        _ = screen.handle(
            .choices(command: "ideas", rows: [ChoiceRow(label: "i1", detail: "keep it more", arguments: "i1")])
        )
        _ = screen.handle(.fillDraft("/ideas "))
        _ = screen.handle(.notice("Edited i1.", isError: false))
        _ = screen.handle(.runEnded)
        #expect(screen.state.editor.text == "/ideas ")
        #expect(screen.state.picker?.matches.map(\.detail) == ["keep it more"])
    }
}
