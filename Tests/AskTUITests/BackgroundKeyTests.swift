import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Roadmap 0173: while a command runs in the turn, Ctrl+B (or Ctrl+Enter where the terminal reports it) asks for it to go to the
/// background; otherwise Ctrl+B keeps its editing meaning.
@Suite("Ctrl+B sends a running command to the background, and only then")
struct BackgroundKeyTests {
    private func screen(command: Bool) -> ScreenController {
        var screen = ScreenController(label: "m", commands: [])
        _ = screen.handle(.paste("go"), pageRows: 10)
        _ = screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 10)
        screen.handle(.toolStarted(name: "bash", summary: "sleep 30", id: "t", command: command ? ToolCommand() : nil))
        return screen
    }

    @Test func `while a command runs, Ctrl+B and Ctrl+Enter ask for the background`() {
        var screen = screen(command: true)
        #expect(screen.handle(.key(KeyEvent(keyCode: 0x02)), pageRows: 10) == [.sendCommandToBackground])
        #expect(
            screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue, modifiers: .ctrl)), pageRows: 10) == [
                .sendCommandToBackground
            ]
        )
    }

    @Test func `with no command running, Ctrl+B moves the cursor as before`() {
        var screen = screen(command: false)
        _ = screen.handle(.paste("ab"), pageRows: 10)
        #expect(screen.handle(.key(KeyEvent(keyCode: 0x02)), pageRows: 10).isEmpty)
        #expect(screen.state.editor.cursor == 1)
        var idle = ScreenController(label: "m", commands: [])
        _ = idle.handle(.paste("ab"), pageRows: 10)
        _ = idle.handle(.key(KeyEvent(keyCode: 0x02)), pageRows: 10)
        #expect(idle.state.editor.cursor == 1)
    }

    @Test func `a finished command no longer takes the key`() {
        var screen = screen(command: true)
        screen.handle(.toolFinished(.succeeded, output: "done", id: "t"))
        _ = screen.handle(.paste("ab"), pageRows: 10)
        #expect(screen.handle(.key(KeyEvent(keyCode: 0x02)), pageRows: 10).isEmpty)
    }
}
