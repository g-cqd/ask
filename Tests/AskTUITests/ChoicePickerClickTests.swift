internal import TerminalKitCodecs
internal import TerminalKitInput
internal import Testing

@testable import AskTUI

/// A click on a row of a command's list is the choice and Enter in one gesture (ADR-0070, ADR-0117): the command runs with that row.
@Suite("A click on a choice runs the command with that row")
struct ChoicePickerClickTests {
    private static let rows = 20

    private func rig() -> PointerRig {
        var rig = PointerRig(columns: 60, rows: Self.rows, lines: ["one", "two"])
        rig.controller = ScreenController(
            label: "m", commands: [SlashCommand(name: "model", summary: "Choose a model.", takesChoices: true)])
        for scalar in "/model ".unicodeScalars {
            _ = rig.controller.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: Self.rows - 3)
        }
        _ = rig.controller.handle(
            .choices(
                command: "model",
                rows: [
                    ChoiceRow(label: "codex/gpt-6-sol", arguments: "codex gpt-6-sol"),
                    ChoiceRow(label: "apple/on-device", arguments: "apple on-device")
                ]))
        rig.draw()
        return rig
    }

    @Test func `clicking a model runs /model with it`() throws {
        var rig = rig()
        let target = try #require((0 ..< Self.rows).first { rig.text(row: $0).hasPrefix("apple/on-device") })
        let effects = rig.click(row: target, col: 5)
        #expect(effects == [.runCommand(name: "model", arguments: "apple on-device")])
        #expect(rig.controller.state.editor.text.isEmpty && rig.controller.state.picker == nil)
    }

    @Test func `a click on the title chooses nothing`() throws {
        var rig = rig()
        let title = try #require((0 ..< Self.rows).first { rig.text(row: $0).hasPrefix("model") })
        #expect(rig.click(row: title, col: 3).isEmpty)
        #expect(rig.controller.state.editor.text == "/model ")
    }
}
