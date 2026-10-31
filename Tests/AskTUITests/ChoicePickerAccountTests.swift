import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Roadmap 0092: a model two accounts serve is one row of `/model`; choosing it writes the model in the draft, and only then are its
/// accounts listed, one row each, for the person to pick.
@Suite("A model of several accounts is one row, whose accounts are listed once it is chosen")
struct ChoicePickerAccountTests {
    private static let models = [
        ChoiceRow(label: "gpt-6", detail: "codex · codex-2", arguments: "gpt-6", completes: true),
        ChoiceRow(label: "gpt-6 · codex", detail: "account", arguments: "codex gpt-6", revealedBy: "gpt-6 "),
        ChoiceRow(label: "gpt-6 · codex-2", detail: "account", arguments: "codex-2 gpt-6", revealedBy: "gpt-6 "),
        ChoiceRow(label: "codex/gpt-6-mini", arguments: "codex gpt-6-mini")
    ]

    private func screen() -> ScreenController {
        var screen = ScreenController(
            label: "m", commands: [SlashCommand(name: "model", summary: "Choose a model.", takesChoices: true)])
        screen.setScreenRows(30)
        _ = screen.handle(.choices(command: "model", rows: Self.models))
        return screen
    }

    private func labels(_ screen: ScreenController) -> [String] { screen.state.picker?.matches.map(\.label) ?? [] }

    @discardableResult
    private func type(_ text: String, into screen: inout ScreenController) -> [ScreenController.Effect] {
        var effects: [ScreenController.Effect] = []
        for scalar in text.unicodeScalars {
            effects += screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30)
        }
        return effects.filter { $0 != .listSkills }
    }

    @Test func `the list shows the shared model once, its accounts hidden`() {
        var screen = screen()
        type("/model ", into: &screen)
        #expect(labels(screen) == ["gpt-6", "codex/gpt-6-mini"])
        type("gpt", into: &screen)
        #expect(labels(screen) == ["gpt-6", "codex/gpt-6-mini"])
    }

    @Test func `choosing the shared model lists its accounts, and choosing one runs it`() {
        var screen = screen()
        type("/model gpt-6", into: &screen)
        #expect(type("\r", into: &screen).isEmpty)
        #expect(screen.state.editor.text == "/model gpt-6 ")
        #expect(labels(screen) == ["gpt-6 · codex", "gpt-6 · codex-2"])
        type("2", into: &screen)
        #expect(labels(screen) == ["gpt-6 · codex-2"])
        #expect(type("\r", into: &screen) == [.runCommand(name: "model", arguments: "codex-2 gpt-6")])
    }

    @Test func `ranking alone keeps a revealed row out until its prefix is typed, whatever the case`() {
        #expect(PickerRanking.rank(Self.models, query: "codex-2").map(\.label) == ["gpt-6"])
        #expect(PickerRanking.rank(Self.models, query: "GPT-6 ").map(\.label) == ["gpt-6 · codex", "gpt-6 · codex-2"])
    }
}
