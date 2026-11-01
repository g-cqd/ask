import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

// How much of the screen the picker takes, and what takes the keys before it; apart from
// CompletionPickerControllerTests.swift to keep each file under the 250-line ceiling.
extension CompletionPickerControllerTests {
    @Test func `a screen too small to show it does not take the keys`() {
        var screen = controller()
        type("/co", into: &screen, pageRows: 4)
        #expect(screen.state.picker == nil)
        let effects = press(Key.enter.rawValue, into: &screen, pageRows: 4)
        #expect(effects.isEmpty && screen.state.transcript.items.contains(.user("/co")))
    }

    @Test func `how many rows it may list follows the screen`() {
        #expect(CompletionPicker.capacity(screenRows: 12) == 3)
        #expect(CompletionPicker.capacity(screenRows: 20) == 7)
        #expect(CompletionPicker.capacity(screenRows: 80) == 7)
    }

    @Test func `an approval question takes the keys before the picker`() {
        var screen = controller()
        type("/co", into: &screen)
        screen.handle(.askApproval(id: 7, question: "bash wants network any. Allow it?"))
        #expect(type("y", into: &screen).isEmpty, "the letter checks; Enter confirms (roadmap 0116)")
        #expect(press(0x0D, into: &screen) == [.answerApproval(id: 7, .once)])
        #expect(screen.state.editor.text == "/co")
    }

    @Test func `moving past the visible window scrolls it, and the choice is always inside it`() throws {
        let many = (0 ..< 12).map { SlashCommand(name: "cmd\($0)", summary: "Command \($0).") }
        var screen = ScreenController(label: "m", commands: many, options: .legacy)
        type("/cmd", into: &screen, pageRows: 17)
        for _ in 0 ..< 9 { press(Key.down.rawValue, into: &screen, pageRows: 17) }
        let picker = try #require(screen.state.picker)
        #expect(picker.matches.first?.isHeading == true, "the group's heading takes the first row")
        #expect(picker.selected == 10 && picker.visible.contains { $0.label == "/cmd9" })
        #expect(picker.visible.count == 7 && picker.firstVisible == 4)
    }
}
