import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A draft to edit (roadmap 0180): `/notes:edit n1 TEXT` in the input with the list closed, since the note's own words match its row and an
/// open list would take Enter.
@Suite
struct EditDraftTests {
    private func screen() -> ScreenController {
        var screen = ScreenController(
            label: "m",
            commands: [SlashCommand(name: "notes", summary: "Show the notes.", takesChoices: true)]
        )
        screen.setScreenRows(30)
        _ = screen.handle(
            .choices(command: "notes", rows: [ChoiceRow(label: "n1", detail: "keep it", arguments: "n1")])
        )
        _ = screen.handle(
            .choices(command: "notes:edit", rows: [ChoiceRow(label: "n1", detail: "keep it", arguments: "n1")])
        )
        return screen
    }

    @Test func `a draft to edit leaves the list closed while it is typed in, and Enter runs it`() {
        var screen = screen()
        _ = screen.handle(.editDraft("/notes:edit n1 keep it"))
        #expect(screen.state.picker == nil && screen.state.editor.text == "/notes:edit n1 keep it")
        // Words the row holds too, so a list open again would match it and take Enter.
        for scalar in " it".unicodeScalars { _ = screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30) }
        #expect(screen.state.picker == nil)
        let effects = screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        #expect(effects.contains(.runCommand(name: "notes:edit", arguments: "n1 keep it it")))
    }

    @Test func `the same draft filled as usual opens the list, which is why editing needs its own`() {
        var screen = screen()
        _ = screen.handle(.fillDraft("/notes:edit n1 keep it"))
        #expect(screen.state.picker?.matches.map(\.label) == ["n1"])
    }

    @Test func `once the edit is kept, the list opens again with the new words`() {
        var screen = screen()
        _ = screen.handle(.editDraft("/notes:edit n1 keep it"))
        for scalar in " more".unicodeScalars { _ = screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30) }
        _ = screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        _ = screen.handle(
            .choices(command: "notes", rows: [ChoiceRow(label: "n1", detail: "keep it more", arguments: "n1")])
        )
        _ = screen.handle(.fillDraft("/notes "))
        _ = screen.handle(.notice("Edited n1.", isError: false))
        _ = screen.handle(.runEnded)
        #expect(screen.state.editor.text == "/notes ")
        #expect(screen.state.picker?.matches.map(\.detail) == ["keep it more"])
    }
}
