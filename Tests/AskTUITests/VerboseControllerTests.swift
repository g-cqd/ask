import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Details (ADR-0119): what ask did on its own account is shown with `--verbose` and held back otherwise, so `/verbose` can show what it missed.
@Suite("Details are shown only when asked for, and kept for when they are")
struct VerboseControllerTests {
    private func texts(_ screen: ScreenController) -> [String] {
        screen.state.transcript.items.compactMap { item -> String? in
            if case .notice(let text, _) = item { return text }
            return nil
        }
    }

    @Test func `a detail is not shown by default`() {
        var screen = ScreenController(label: "m")
        screen.handle(.detail("The sandbox is off."))
        screen.handle(.notice("A real warning.", isError: false))
        #expect(texts(screen) == ["A real warning."])
    }

    @Test func `with verbose on it is shown as it arrives`() {
        var screen = ScreenController(label: "m", options: ScreenOptions(verbose: true))
        screen.handle(.detail("The sandbox is off."))
        #expect(texts(screen) == ["The sandbox is off."])
    }

    @Test func `the slash command shows what was held, in order, and a second one hides again`() {
        var screen = ScreenController(label: "m")
        screen.handle(.detail("one"))
        screen.handle(.detail("two"))
        for scalar in "/verbose".unicodeScalars {
            _ = screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30)
        }
        _ = screen.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 30)
        #expect(texts(screen).suffix(3) == ["Details are shown.", "one", "two"])
        screen.handle(.detail("three"))
        #expect(texts(screen).last == "three")
        for scalar in "/verbose".unicodeScalars {
            _ = screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30)
        }
        _ = screen.handle(.key(KeyEvent(keyCode: 0x0D)), pageRows: 30)
        screen.handle(.detail("four"))
        #expect(
            !texts(screen).contains("four") && texts(screen).contains("Details are hidden. /verbose shows them again."))
    }

    @Test func `only the latest few are held`() {
        var screen = ScreenController(label: "m")
        for index in 0 ..< 80 { screen.handle(.detail("d\(index)")) }
        #expect(
            screen.state.heldDetails.count == ScreenController.heldDetailLimit
                && screen.state.heldDetails.first == "d30")
    }
}
