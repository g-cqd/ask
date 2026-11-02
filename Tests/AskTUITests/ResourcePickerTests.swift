import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Roadmap 0067: after `@server:` the `@` picker lists that server's resources, which the conversation gives as the choices of
/// `@server`; choosing one puts `@server:uri` in place. A file's `@path` and `@file:12-30` keep the file picker.
@Suite("An @server: word offers the server's resources")
struct ResourcePickerTests {
    private static let rows = [
        ChoiceRow(
            label: "@docs:docs://framework/swiftui",
            detail: "SwiftUI",
            arguments: "@docs:docs://framework/swiftui"
        ),
        ChoiceRow(label: "@docs:docs://framework/uikit", detail: "UIKit", arguments: "@docs:docs://framework/uikit")
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

    @Test func `the colon asks the server once, its resources narrow as typed, and a choice is put in place`() {
        var screen = screen()
        let effects = type("see @docs:d", into: &screen)
        #expect(effects.filter { $0 == .listChoices(command: "@docs") }.count == 1)
        _ = screen.handle(.choices(command: "@docs", rows: Self.rows))
        #expect(screen.state.picker?.kind == .resources(server: "docs"))
        #expect(screen.state.picker?.matches.count == 2)
        _ = screen.handle(.key(KeyEvent(keyCode: Key.backspace.rawValue)), pageRows: 30)
        _ = type("uik", into: &screen)
        #expect(screen.state.picker?.matches.map(\.label) == ["@docs:docs://framework/uikit"])
        _ = screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        #expect(screen.state.editor.text.hasPrefix("see @docs:docs://framework/uikit"))
        #expect(screen.state.picker == nil)
    }

    /// A template is shown whole; choosing it writes its fixed part, for the person to finish, and nothing after it.
    @Test func `a template's choice puts the URI up to its first variable in place, to be finished`() {
        var screen = screen()
        _ = type("see @docs:docs://p", into: &screen)
        let template = ChoiceRow(
            label: "@docs:docs://page/{+key}",
            detail: "page · template",
            arguments: "@docs:docs://page/",
            completes: true
        )
        _ = screen.handle(.choices(command: "@docs", rows: Self.rows + [template]))
        #expect(screen.state.picker?.matches.map(\.label) == ["@docs:docs://page/{+key}"])
        _ = screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        #expect(screen.state.editor.text == "see @docs:docs://page/")
        _ = type("swiftui", into: &screen)
        #expect(screen.state.editor.text == "see @docs:docs://page/swiftui", "typed on where the choice ended")
        #expect(screen.state.picker == nil, "not offered again while it is finished")
    }

    @Test func `while the server is asked, a URI being typed says so`() {
        var screen = screen()
        _ = type("@docs:docs:", into: &screen)
        #expect(screen.state.picker?.kind == .resources(server: "docs"))
        #expect(screen.state.picker?.caption.contains("docs") == true)
    }

    @Test func `a file's line range is the file picker's, and asks no server`() {
        var screen = screen()
        _ = type("@notes:", into: &screen)
        let effects = type("12", into: &screen)
        #expect(!effects.contains { if case .listChoices = $0 { true } else { false } })
        #expect(screen.state.picker?.kind == .files)
        #expect(screen.state.picker?.kind != .resources(server: "notes"))
    }

    @Test func `a name that is no server with resources leaves the file picker`() {
        var screen = screen()
        _ = type("@notes:", into: &screen)
        #expect(screen.state.picker?.kind == .files, "the file picker, while the server is asked")
        _ = screen.handle(.choices(command: "@notes", rows: []))
        #expect(screen.state.picker?.kind == .files)
        _ = type("x", into: &screen)
        #expect(screen.state.picker?.kind == .files)
    }

    @Test func `a path before a colon is no server's name`() {
        var screen = screen()
        let effects = type("@a/b:x", into: &screen)
        #expect(!effects.contains { if case .listChoices = $0 { true } else { false } })
    }
}
