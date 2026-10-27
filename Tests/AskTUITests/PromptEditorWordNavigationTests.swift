import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

@Suite("Prompt editor Alt word jumping and selection")
struct PromptEditorWordNavigationTests {
    @Test func `Shift Alt arrows extend and shrink the word selection from a fixed anchor`() {
        var controller = ScreenController(label: "test")
        _ = controller.handle(.paste("alpha beta gamma"), pageRows: 10)
        let left = KeyEvent(keyCode: Key.left.rawValue, modifiers: [.alt, .shift])
        let right = KeyEvent(keyCode: Key.right.rawValue, modifiers: [.alt, .shift])
        _ = controller.handle(.key(left), pageRows: 10)
        #expect(controller.state.inputSelection == 11 ..< 16)
        _ = controller.handle(.key(left), pageRows: 10)
        #expect(controller.state.inputSelection == 6 ..< 16)
        _ = controller.handle(.key(right), pageRows: 10)
        #expect(controller.state.inputSelection == 11 ..< 16)
        _ = controller.handle(.key(right), pageRows: 10)
        #expect(controller.state.inputSelection == nil)
    }

    @Test func `Alt Left and Alt Right jump words`() {
        var editor = PromptEditor()
        editor.paste("hello world, again")
        #expect(editor.cursor == 18)

        let altLeft = KeyEvent(keyCode: Key.left.rawValue, modifiers: .alt)
        let altRight = KeyEvent(keyCode: Key.right.rawValue, modifiers: .alt)

        _ = editor.apply(altLeft)
        #expect(editor.cursor == 13)  // start of "again"

        _ = editor.apply(altLeft)
        #expect(editor.cursor == 6)  // start of "world"

        _ = editor.apply(altRight)
        #expect(editor.cursor == 13)  // start of "again"

        _ = editor.apply(altRight)
        #expect(editor.cursor == 18)  // end of string
    }

    @Test func `Alt b and Alt f readline keys jump words`() {
        var editor = PromptEditor()
        editor.paste("alpha beta")
        let altB = KeyEvent(keyCode: 0x62, modifiers: .alt)
        let altF = KeyEvent(keyCode: 0x66, modifiers: .alt)

        _ = editor.apply(altB)
        #expect(editor.cursor == 6)

        _ = editor.apply(altB)
        #expect(editor.cursor == 0)

        _ = editor.apply(altF)
        #expect(editor.cursor == 6)
    }
}
