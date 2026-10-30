internal import TerminalKitCodecs
internal import TerminalKitInput
internal import Testing

@testable import AskTUI

/// Up and Down browse what was sent (roadmap 0111): prompts and `/` commands, the newest first; the draft being typed comes back at the
/// newest end; once a recalled prompt is edited, Down goes no further, and the edited text is the draft from then on.
@Suite("Prompt history with Up and Down")
struct PromptHistoryTests {
    private let up = InputEvent.key(KeyEvent(keyCode: Key.up.rawValue))
    private let down = InputEvent.key(KeyEvent(keyCode: Key.down.rawValue))

    private func controller(sent: [String]) -> ScreenController {
        var controller = ScreenController(label: "m", options: .legacy)
        for line in sent { controller.handle(.userPrompt(line)) }
        return controller
    }

    private mutating func type(_ text: String, into controller: inout ScreenController) {
        for character in text {
            _ = controller.handle(
                .key(KeyEvent(keyCode: character.unicodeScalars.first!.value)), pageRows: 10, columns: 60)
        }
    }

    private func press(_ event: InputEvent, _ controller: inout ScreenController, times: Int = 1) {
        for _ in 0 ..< times { _ = controller.handle(event, pageRows: 10, columns: 60) }
    }

    @Test func `Up recalls the newest first, and Down comes back to the draft`() {
        var screen = controller(sent: ["first", "second"])
        var copy = self
        copy.type("draft", into: &screen)
        press(up, &screen)
        #expect(screen.state.editor.text == "second")
        press(up, &screen)
        #expect(screen.state.editor.text == "first")
        press(up, &screen)
        #expect(screen.state.editor.text == "first", "nothing older")
        press(down, &screen, times: 2)
        #expect(screen.state.editor.text == "draft")
        press(down, &screen)
        #expect(screen.state.editor.text == "draft", "nothing newer than the draft")
    }

    @Test func `what was sent from the editor is recalled, commands included`() {
        var screen = controller(sent: [])
        var copy = self
        copy.type("/help", into: &screen)
        press(.key(KeyEvent(keyCode: 0x0D)), &screen)
        copy.type("hello", into: &screen)
        press(.key(KeyEvent(keyCode: 0x0D)), &screen)
        press(up, &screen)
        #expect(screen.state.editor.text == "hello")
        press(up, &screen)
        #expect(screen.state.editor.text == "/help")
    }

    @Test func `after an edit, Down goes no further, and the edit is kept as the draft`() {
        var screen = controller(sent: ["one", "two", "three"])
        press(up, &screen, times: 2)
        #expect(screen.state.editor.text == "two")
        var copy = self
        copy.type("!", into: &screen)
        press(down, &screen)
        #expect(screen.state.editor.text == "two!", "no newer entry once edited")
        press(up, &screen)
        #expect(screen.state.editor.text == "one")
        press(down, &screen, times: 2)
        #expect(screen.state.editor.text == "three", "unedited entries go on to newer ones")
        press(down, &screen)
        #expect(screen.state.editor.text == "two!", "the edited text came back as the draft, at the newest end")
    }

    @Test func `in a multi-line input the arrows move between its lines first`() {
        var screen = controller(sent: ["old"])
        screen.state.editor.restore("line one\nline two")
        press(up, &screen)
        #expect(screen.state.editor.text == "line one\nline two", "the cursor went up a line")
        press(up, &screen)
        #expect(screen.state.editor.text == "old", "from the first line, Up recalls")
    }

    @Test func `a recalled command does not open the picker in the way of the next Up`() {
        var screen = controller(sent: ["older", "/model", "/he"])
        press(up, &screen)
        #expect(screen.state.editor.text == "/he")
        press(up, &screen)
        #expect(screen.state.editor.text == "/model")
        press(up, &screen)
        #expect(screen.state.editor.text == "older")
    }

    @Test func `the history skips empty lines and a repeat of the last entry`() {
        var history = PromptHistory()
        for line in ["a", "  ", "a", "b"] { history.record(line) }
        #expect(history.entries == ["a", "b"])
    }
}
