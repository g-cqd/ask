import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A command's list in the screen's state machine (ADR-0117): `/model ` asks for the models once, lists them as they arrive, narrows as
/// the person types, and Enter runs the command with the row's arguments at once.
@Suite("A command's list is asked for, narrowed by typing, and a choice runs the command at once")
struct ChoicePickerControllerTests {
    @Test func `startup can open preloaded session choices before any key is pressed`() {
        var screen = ScreenController(
            label: "m", commands: [SlashCommand(name: "resume", summary: "Choose a session.", takesChoices: true)])
        screen.setScreenRows(30)
        let rows = [ChoiceRow(label: "session", detail: "first prompt", arguments: "/tmp/session.jsonl")]
        #expect(screen.handle(.choices(command: "resume", rows: rows)).isEmpty)
        #expect(screen.handle(.fillDraft("/resume ")).isEmpty)
        #expect(labels(screen) == ["session"])
        #expect(
            press(Key.enter.rawValue, into: &screen) == [.runCommand(name: "resume", arguments: "/tmp/session.jsonl")])
    }

    private static let models = [
        ChoiceRow(label: "codex/gpt-6-sol", detail: "272k ctx", arguments: "codex gpt-6-sol", isCurrent: true),
        ChoiceRow(label: "codex/gpt-6-astra", detail: "272k ctx", arguments: "codex gpt-6-astra"),
        ChoiceRow(label: "apple/on-device", detail: "4k ctx", arguments: "apple on-device")
    ]

    private func controller() -> ScreenController {
        ScreenController(
            label: "m",
            commands: [
                SlashCommand(name: "model", summary: "Choose a model.", takesChoices: true),
                SlashCommand(name: "config", summary: "Show the settings.")
            ])
    }

    /// What typing asked the driver for, without the skills' listing a first `/` always asks for.
    @discardableResult
    private func type(_ text: String, into screen: inout ScreenController) -> [ScreenController.Effect] {
        var effects: [ScreenController.Effect] = []
        for scalar in text.unicodeScalars {
            effects += screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30)
        }
        return effects.filter { $0 != .listSkills }
    }

    @discardableResult
    private func press(_ code: UInt32, into screen: inout ScreenController) -> [ScreenController.Effect] {
        screen.handle(.key(KeyEvent(keyCode: code)), pageRows: 30)
    }

    private func labels(_ screen: ScreenController) -> [String] { screen.state.picker?.matches.map(\.label) ?? [] }

    @Test func `choosing a command that takes a list inserts it with its space, so the list opens`() {
        var screen = controller()
        type("/mod", into: &screen)
        press(Key.enter.rawValue, into: &screen)
        #expect(screen.state.editor.text == "/model ")
    }

    @Test func `the command's name and a space ask for the list once`() {
        var screen = controller()
        #expect(type("/model ", into: &screen) == [.listChoices(command: "model")])
        #expect(type("co", into: &screen).isEmpty, "already asked for")
        #expect(screen.state.picker?.matches.isEmpty == true && screen.state.picker?.caption == "looking…")
    }

    @Test func `the list arriving fills the picker and typing narrows it`() {
        var screen = controller()
        type("/model ", into: &screen)
        screen.handle(.choices(command: "model", rows: Self.models))
        #expect(labels(screen) == ["codex/gpt-6-sol ●", "codex/gpt-6-astra", "apple/on-device"])
        type("astra", into: &screen)
        #expect(labels(screen) == ["codex/gpt-6-astra"])
    }

    @Test func `Enter runs the command with the row's arguments and clears the draft`() {
        var screen = controller()
        type("/model ", into: &screen)
        screen.handle(.choices(command: "model", rows: Self.models))
        press(Key.down.rawValue, into: &screen)
        let effects = press(Key.enter.rawValue, into: &screen)
        #expect(effects == [.runCommand(name: "model", arguments: "codex gpt-6-astra")])
        #expect(screen.state.editor.text.isEmpty && screen.state.picker == nil && screen.state.running)
    }

    @Test func `Escape closes the list and keeps what was typed`() {
        var screen = controller()
        type("/model ap", into: &screen)
        screen.handle(.choices(command: "model", rows: Self.models))
        #expect(press(0x1B, into: &screen).isEmpty)
        #expect(screen.state.picker == nil && screen.state.editor.text == "/model ap")
    }

    @Test func `a command typed in full without a choice opens its choices`() {
        var screen = controller()
        type("/model", into: &screen)
        #expect(press(Key.enter.rawValue, into: &screen) == [.listChoices(command: "model")])
        #expect(screen.state.editor.text == "/model ")
    }

    @Test func `a list that has aged is asked for again`() {
        var screen = controller()
        type("/model ", into: &screen)
        screen.handle(.choices(command: "model", rows: Self.models))
        screen.state.choices["model"] = ChoiceList(rows: Self.models, at: .now - .seconds(60))
        #expect(type("c", into: &screen) == [.listChoices(command: "model")])
    }

    /// A prompt or a command can change a list: `/tree` gains the prompt just sent, `/resume` the session, `/logout` the account. The probe
    /// found `/tree` still offering two prompts after a third was sent (roadmap 0131): the held list was under 30 s old.
    @Test func `a list held across a finished run is asked for again, and shown meanwhile`() {
        var screen = ScreenController(
            label: "m", commands: [SlashCommand(name: "tree", summary: "Go back.", takesChoices: true)])
        screen.setScreenRows(30)
        screen.handle(.choices(command: "tree", rows: [ChoiceRow(label: "1", detail: "first", arguments: "1")]))
        screen.handle(.runEnded)
        #expect(type("/tree ", into: &screen) == [.listChoices(command: "tree")])
        #expect(labels(screen) == ["1"])
        screen.handle(
            .choices(
                command: "tree",
                rows: [
                    ChoiceRow(label: "2", detail: "second", arguments: "2"),
                    ChoiceRow(label: "1", detail: "first", arguments: "1")
                ]))
        #expect(labels(screen) == ["2", "1"])
        #expect(type("x", into: &screen).isEmpty, "fresh again until the next run ends")
    }

    /// The probe found `/resume` in a project with no sessions doing nothing at all: the empty list closed the picker, and Enter only opened
    /// it again (roadmap 0131).
    @Test func `an empty list says there is nothing to choose, and Enter then runs the bare command`() {
        var screen = ScreenController(
            label: "m", commands: [SlashCommand(name: "resume", summary: "Choose a session.", takesChoices: true)])
        screen.setScreenRows(30)
        type("/resume", into: &screen)
        #expect(press(Key.enter.rawValue, into: &screen) == [.listChoices(command: "resume")])
        screen.handle(.choices(command: "resume", rows: []))
        #expect(screen.state.picker?.matches.isEmpty == true && screen.state.picker?.caption == "nothing to choose")
        #expect(press(Key.enter.rawValue, into: &screen) == [.runCommand(name: "resume", arguments: "")])
    }

    @Test func `a row that needs more words is written in the draft, and the list stays closed`() {
        var screen = ScreenController(
            label: "m", commands: [SlashCommand(name: "login", summary: "Sign in.", takesChoices: true)])
        type("/login ", into: &screen)
        screen.handle(
            .choices(
                command: "login",
                rows: [ChoiceRow(label: "custom NAME URL", arguments: "custom", completes: true)]))
        #expect(press(Key.enter.rawValue, into: &screen).isEmpty)
        #expect(screen.state.editor.text == "/login custom ")
        #expect(screen.state.picker == nil)
    }

    @Test func `a model choice that offers efforts fills the draft and opens that list at once`() {
        var screen = ScreenController(
            label: "m", commands: [SlashCommand(name: "thinking", summary: "Effort.", takesChoices: true)])
        _ = screen.handle(.key(KeyEvent(keyCode: 0x61)), pageRows: 30)
        _ = screen.handle(.key(KeyEvent(keyCode: 0x7F)), pageRows: 30)
        #expect(screen.handle(.fillDraft("/thinking ")) == [.listChoices(command: "thinking")])
        #expect(screen.state.editor.text == "/thinking ")
    }

    @Test func `a screen too short for a list leaves the keys alone`() {
        var screen = controller()
        for scalar in "/model ".unicodeScalars { _ = screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 4) }
        #expect(screen.state.picker == nil)
    }
}
