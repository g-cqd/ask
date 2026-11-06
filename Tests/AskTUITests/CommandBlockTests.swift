import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// A command leaves no block when what it did shows by itself (note n28): `/sidebar` toggles the sidebar, which is its answer; a model
/// and a thinking level chosen from their lists leave one summary at the end, not the command's line, a notice, the next command's
/// line and another notice.
@Suite("A command leaves a block only when the screen does not already say what it did")
struct CommandBlockTests {
    private static let models = [
        ChoiceRow(label: "anthropic/claude-sonnet-5-5", arguments: "anthropic claude-sonnet-5-5", isCurrent: true),
        ChoiceRow(label: "anthropic/claude-opus-5-5", arguments: "anthropic claude-opus-5-5")
    ]
    private static let efforts = [
        ChoiceRow(label: "high", arguments: "high"), ChoiceRow(label: "low", arguments: "low")
    ]

    private func controller() -> ScreenController {
        var screen = ScreenController(
            label: "m",
            commands: [
                SlashCommand(name: "model", summary: "Choose a model.", takesChoices: true, summarises: true),
                SlashCommand(
                    name: "thinking",
                    summary: "Choose how hard it thinks.",
                    takesChoices: true,
                    summarises: true
                )
            ]
        )
        screen.setScreenRows(30)
        _ = screen.handle(.choices(command: "model", rows: Self.models))
        _ = screen.handle(.choices(command: "thinking", rows: Self.efforts))
        return screen
    }

    @discardableResult
    private func type(_ text: String, into screen: inout ScreenController) -> [ScreenController.Effect] {
        text.unicodeScalars.flatMap { screen.handle(.key(KeyEvent(keyCode: $0.value)), pageRows: 30) }
    }

    @discardableResult
    private func enter(_ screen: inout ScreenController) -> [ScreenController.Effect] {
        screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
    }

    private func texts(_ screen: ScreenController) -> [String] {
        screen.state.transcript.items.compactMap { item in
            switch item {
                case .notice(let text, _), .user(let text): text
                default: nil
            }
        }
    }

    @Test func `a model then a thinking level chosen from their lists leave one summary, the last`() {
        var screen = controller()
        type("/model", into: &screen)
        enter(&screen)
        type("opus", into: &screen)
        #expect(enter(&screen) == [.runCommand(name: "model", arguments: "anthropic claude-opus-5-5")])
        _ = screen.handle(.choiceSummary("For this run: claude-opus-5-5 on anthropic."))
        _ = screen.handle(.runEnded)
        _ = screen.handle(.fillDraft("/thinking "))
        #expect(enter(&screen) == [.runCommand(name: "thinking", arguments: "high")])
        _ = screen.handle(.choiceSummary("For this run: claude-opus-5-5 on anthropic, thinking high."))
        _ = screen.handle(.runEnded)
        #expect(texts(screen) == ["For this run: claude-opus-5-5 on anthropic, thinking high."], "\(texts(screen))")
    }

    @Test func `a summary after something else is a block of its own`() {
        var screen = controller()
        _ = screen.handle(.choiceSummary("For this run: claude-opus-5-5 on anthropic."))
        _ = screen.handle(.notice("Something else.", isError: false))
        _ = screen.handle(.choiceSummary("For this run: claude-opus-5-5 on anthropic, thinking low."))
        #expect(
            texts(screen) == [
                "For this run: claude-opus-5-5 on anthropic.", "Something else.",
                "For this run: claude-opus-5-5 on anthropic, thinking low."
            ]
        )
    }

    @Test func `the sidebar's command leaves no block: the sidebar is its answer`() {
        var screen = ScreenController(label: "m", options: ScreenOptions(prompt: "ask> "))
        screen.setScreenRows(30)
        screen.frame.columns = 160
        type("/sidebar", into: &screen)
        enter(&screen)
        #expect(screen.state.sidebarOpen)
        #expect(texts(screen).isEmpty, "\(texts(screen))")
    }
}
