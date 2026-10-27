import TerminalKitInput
import Testing

@testable import AskTUI

@Suite("Slash command choices triggered on enter")
struct SlashCommandChoiceTriggerTests {
    @Test func `enter on a choice command without arguments opens its picker immediately`() {
        let modelCmd = SlashCommand(name: "model", summary: "Choose model", takesChoices: true)
        var controller = ScreenController(label: "test", commands: [modelCmd])
        controller.setScreenRows(20)

        // Submit "/model"
        let effects = controller.submit("/model", followUp: false)
        #expect(controller.state.editor.text == "/model ")
        #expect(effects.contains(.listChoices(command: "model")))
        #expect(controller.state.picker != nil)
    }
}
