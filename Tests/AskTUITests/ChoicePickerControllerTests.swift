import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A command's list in the screen's state machine (ADR-0117): `/model ` asks for the models once, lists them as they arrive, narrows as
/// the person types, and Enter runs the command with the row's arguments at once.
@Suite("A command's list is asked for, narrowed by typing, and a choice runs the command at once")
struct ChoicePickerControllerTests {
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

    @Test func `a command typed in full without a choice still runs as it did`() {
        var screen = controller()
        type("/model", into: &screen)
        #expect(press(Key.enter.rawValue, into: &screen) == [.runCommand(name: "model", arguments: "")])
    }

    @Test func `a list that has aged is asked for again`() {
        var screen = controller()
        type("/model ", into: &screen)
        screen.handle(.choices(command: "model", rows: Self.models))
        screen.state.choices["model"] = ChoiceList(rows: Self.models, at: .now - .seconds(60))
        #expect(type("c", into: &screen) == [.listChoices(command: "model")])
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
