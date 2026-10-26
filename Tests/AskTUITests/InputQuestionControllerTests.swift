import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A line a running command asks for (ADR-0117): typed into a buffer of its own, hidden when it is a secret, sent by Enter and cancelled by
/// Escape, and never in the draft, the transcript or the status line as text.
@Suite("A question a command asks takes the keys, hides a secret, and is answered or cancelled")
struct InputQuestionControllerTests {
    private static let secret = "sk-ant-NEVER-SHOWN"

    private func asking(secret: Bool = true) -> ScreenController {
        var screen = ScreenController(label: "m", commands: [SlashCommand(name: "login", summary: "Sign in.")])
        _ = screen.handle(.paste("/login claude api-key"), pageRows: 10)
        _ = screen.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
        screen.handle(.askInput(id: 3, prompt: "Paste the key:", secret: secret))
        return screen
    }

    private func type(_ text: String, into screen: inout ScreenController) {
        for scalar in text.unicodeScalars { _ = screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 10) }
    }

    @Test func `the question is shown, and what is typed goes to the answer and not the draft`() {
        var screen = asking()
        type("abc", into: &screen)
        #expect(screen.state.pendingInput?.id == 3 && screen.state.inputAnswer.text == "abc")
        #expect(screen.state.editor.text.isEmpty)
    }

    @Test func `Enter sends the answer once and says only that it was received`() {
        var screen = asking()
        type(Self.secret, into: &screen)
        let effects = screen.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 10)
        #expect(effects == [.answerInput(id: 3, text: Self.secret)])
        #expect(screen.state.pendingInput == nil && screen.state.inputAnswer.text.isEmpty)
        let shown = screen.state.transcript.items.map { "\($0)" }.joined()
        #expect(!shown.contains(Self.secret), "a secret is never in the transcript")
        #expect(shown.contains("Received (hidden)."))
    }

    @Test func `a secret is dots and a count in the status line, never text`() {
        var screen = asking()
        type(Self.secret, into: &screen)
        let line = ScreenComposer.status(for: screen.state).line.text
        #expect(!line.contains("sk-ant") && line.contains("•") && line.contains("(\(Self.secret.count))"))
        #expect(line.contains("Paste the key:") && line.contains("Esc cancels"))
    }

    @Test func `a plain answer shows its end, so a pasted address can be checked`() {
        var screen = asking(secret: false)
        type("http://localhost:1455/auth/callback?code=abc", into: &screen)
        #expect(ScreenComposer.status(for: screen.state).line.text.contains("callback?code=abc"))
    }

    @Test func `Escape cancels the question and nothing typed is sent`() {
        var screen = asking()
        type("half", into: &screen)
        #expect(screen.handle(.key(KeyEvent(keyCode: 0x1B)), pageRows: 10) == [.answerInput(id: 3, text: nil)])
        #expect(screen.state.pendingInput == nil && screen.state.inputAnswer.text.isEmpty)
    }

    @Test func `Ctrl+C cancels the question and stops the command`() {
        var screen = asking()
        let effects = screen.handle(.key(KeyEvent(keyCode: 0x03)), pageRows: 10)
        #expect(effects.first == .answerInput(id: 3, text: nil) && effects.contains(.cancelRun))
    }

    @Test func `a paste is the answer, with its line breaks removed`() {
        var screen = asking()
        _ = screen.handle(.paste("abc\ndef\n"), pageRows: 10)
        #expect(screen.state.inputAnswer.text == "abcdef" && screen.state.editor.text.isEmpty)
    }

    @Test func `the command ending takes the question away`() {
        var screen = asking()
        type("x", into: &screen)
        screen.handle(.runEnded)
        #expect(screen.state.pendingInput == nil && screen.state.inputAnswer.text.isEmpty)
    }
}
