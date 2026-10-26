import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// The `@` picker in the screen's state machine (roadmap 0048): it asks for the project's files once, shows a placeholder until they
/// arrive, then lists them; Enter and Tab insert `@path` and never send; an exact path, no match and a small screen leave the keys alone.
@Suite("The file picker asks for the files, lists them, and inserts without sending")
struct FilePickerControllerTests {
    private static let listing = ProjectFiles(
        paths: ["Package.swift", "README.md", "docs/readme-notes.md", "Sources/AskTUI/Transcript.swift"], hidden: 2)

    private func controller(loaded: Bool = true) -> ScreenController {
        var screen = ScreenController(
            label: "m", commands: [SlashCommand(name: "config", summary: "Show the settings.")])
        if loaded { screen.handle(.files(Self.listing)) }
        return screen
    }

    @discardableResult
    private func type(_ text: String, into screen: inout ScreenController, pageRows: Int = 30) -> [ScreenController
        .Effect]
    {
        var effects: [ScreenController.Effect] = []
        for scalar in text.unicodeScalars {
            effects += screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: pageRows)
        }
        return effects
    }

    @discardableResult
    private func press(_ code: UInt32, into screen: inout ScreenController) -> [ScreenController.Effect] {
        screen.handle(.key(KeyEvent(keyCode: code)), pageRows: 30)
    }

    private func labels(_ screen: ScreenController) -> [String] { screen.state.picker?.matches.map(\.label) ?? [] }

    @Test func `an at sign asks for the files once, however much is typed after it`() {
        var screen = controller(loaded: false)
        #expect(type("@", into: &screen) == [.indexFiles])
        #expect(type("rea", into: &screen).isEmpty, "the listing is already asked for")
        #expect(screen.state.filesLoading)
    }

    @Test func `until the files arrive the picker is a placeholder that takes only Escape`() {
        var screen = controller(loaded: false)
        type("@re", into: &screen)
        #expect(screen.state.picker?.kind == .files && screen.state.picker?.matches.isEmpty == true)
        #expect(screen.state.picker?.caption == "looking for files…")
        #expect(press(0x1B, into: &screen).isEmpty && screen.state.picker == nil)
        var typed = controller(loaded: false)
        type("@re", into: &typed)
        #expect(
            press(Key.enter.rawValue, into: &typed) == [.startRun("@re")],
            "Enter is an ordinary Enter with nothing to choose")
    }

    @Test func `the listing arriving fills the picker the user is waiting at`() {
        var screen = controller(loaded: false)
        type("@read", into: &screen)
        #expect(screen.handle(.files(Self.listing)).isEmpty)
        #expect(labels(screen) == ["README.md", "docs/readme-notes.md"])
        #expect(!screen.state.filesLoading && screen.state.picker?.caption == "2 hidden by the sandbox")
    }

    @Test func `a listing that arrives after the user left the word does nothing`() {
        var screen = controller(loaded: false)
        type("@r done", into: &screen)
        #expect(screen.state.picker == nil)
        #expect(screen.handle(.files(Self.listing)).isEmpty && screen.state.picker == nil)
    }

    @Test func `Enter inserts the chosen path and never sends it, and Tab does the same`() {
        var screen = controller()
        type("@read", into: &screen)
        press(Key.down.rawValue, into: &screen)
        #expect(press(Key.enter.rawValue, into: &screen).isEmpty)
        #expect(
            screen.state.editor.text == "@docs/readme-notes.md " && screen.state.picker == nil && !screen.state.running)
        var tab = controller()
        type("@trans", into: &tab)
        #expect(press(Key.tab.rawValue, into: &tab).isEmpty)
        #expect(tab.state.editor.text == "@Sources/AskTUI/Transcript.swift ")
    }

    @Test func `a line range typed after the path is kept on the path that is chosen`() {
        var screen = controller()
        type("@read:12-30", into: &screen)
        #expect(labels(screen).first == "README.md")
        press(Key.enter.rawValue, into: &screen)
        #expect(screen.state.editor.text == "@README.md:12-30 ")
    }

    @Test func `a name with a space in it is inserted quoted, so the space does not end the word`() {
        var screen = ScreenController(label: "m", commands: [], options: .legacy)
        screen.handle(.files(ProjectFiles(paths: ["My Docs/a b.txt", "plain.txt"])))
        type("@my", into: &screen)
        #expect(labels(screen) == ["My Docs/a b.txt"])
        press(Key.enter.rawValue, into: &screen)
        #expect(screen.state.editor.text == "@\"My Docs/a b.txt\" ")
    }

    @Test func `it opens at the start of any word, not inside one`() {
        var middle = controller()
        type("please read @tran", into: &middle)
        #expect(labels(middle) == ["Sources/AskTUI/Transcript.swift"])
        var address = controller()
        type("me@read", into: &address)
        #expect(address.state.picker == nil, "an address is text")
    }

    @Test func `a path typed in full closes it, so Enter sends the prompt as it always did`() {
        var screen = controller()
        type("@README.md", into: &screen)
        #expect(screen.state.picker == nil)
        #expect(press(Key.enter.rawValue, into: &screen) == [.startRun("@README.md")])
    }

    @Test func `no match, and a project with nothing to list, leave Enter alone`() {
        var none = controller()
        type("@zzz", into: &none)
        #expect(none.state.picker == nil && press(Key.enter.rawValue, into: &none) == [.startRun("@zzz")])
        var empty = controller()
        empty.handle(.files(ProjectFiles()))
        type("@x", into: &empty)
        #expect(empty.state.picker == nil)
    }

    @Test func `Escape closes it and keeps the text, and typing on does not reopen it`() {
        var screen = controller()
        type("@rea", into: &screen)
        #expect(press(0x1B, into: &screen).isEmpty && screen.state.picker == nil && screen.state.editor.text == "@rea")
        type("d", into: &screen)
        #expect(screen.state.picker == nil)
    }

    @Test func `a listing is asked for again only once it is old, and not while one is on its way`() {
        var fresh = controller()
        #expect(type("@", into: &fresh).isEmpty, "a listing from a moment ago is used")
        var old = controller()
        old.state.filesLoadedAt = .now - .seconds(30)
        #expect(type("@", into: &old) == [.indexFiles])
        #expect(type("r", into: &old).isEmpty, "and the old one is listed meanwhile")
        #expect(!labels(old).isEmpty)
    }

    @Test func `a command word and an at word each get their own picker`() {
        var screen = controller()
        type("/co", into: &screen)
        #expect(screen.state.picker?.kind == .commands)
        type("nfig @read", into: &screen)
        #expect(screen.state.picker?.kind == .files, "the cursor is in the second word")
        #expect(labels(screen).first == "README.md")
    }

    @Test func `a slash word in a draft that has an at sign elsewhere is not a file word`() {
        var screen = controller()
        type("@x please /re", into: &screen)  // /re would match README.md if it were taken for a file word
        #expect(screen.state.picker == nil, "a command is only the first word, and a file word starts with an at sign")
    }

    @Test func `a listing that arrives for a screen too small to show it opens nothing`() {
        var screen = controller(loaded: false)
        type("@re", into: &screen, pageRows: 4)
        screen.handle(.files(Self.listing))
        #expect(screen.state.picker == nil)
    }

    @Test func `a screen too small to show it asks for nothing and takes no key`() {
        var screen = controller(loaded: false)
        #expect(type("@re", into: &screen, pageRows: 4).isEmpty)
        #expect(screen.state.picker == nil && !screen.state.filesLoading)
    }
}
