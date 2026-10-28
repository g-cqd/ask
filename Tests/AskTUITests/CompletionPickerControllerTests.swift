import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// The `/` picker in the screen's state machine (roadmap 0048). The rules under test: it opens only for a command in the first word,
/// Enter inserts and never sends, Esc closes and keeps the text, an exact name or no match leaves Enter as it was, and a screen
/// too small to show it does not take the keys.
@Suite("The command picker inserts and never sends")
struct CompletionPickerControllerTests {
    private static let commands = commandTable(
        """
        config | Show the settings.
        compact | Compact the conversation.
        reload | Reload the binary.
        """)

    private func controller() -> ScreenController {
        ScreenController(label: "m", commands: Self.commands, options: .legacy)
    }

    @discardableResult
    private func type(_ text: String, into controller: inout ScreenController, pageRows: Int = 30) -> [ScreenController
        .Effect]
    {
        var effects: [ScreenController.Effect] = []
        for scalar in text.unicodeScalars {
            effects += controller.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: pageRows)
        }
        return effects
    }

    @discardableResult
    private func press(
        _ code: UInt32, _ modifiers: KeyModifiers = [], into controller: inout ScreenController, pageRows: Int = 30
    ) -> [ScreenController.Effect] {
        controller.handle(.key(KeyEvent(keyCode: code, modifiers: modifiers)), pageRows: pageRows)
    }

    private func names(_ controller: ScreenController) -> [String] {
        controller.state.picker?.matches.filter { !$0.isHeading }.map { String($0.label.dropFirst()) } ?? []
    }

    /// The headings the picker draws, in order.
    private func headings(_ controller: ScreenController) -> [String] {
        controller.state.picker?.matches.filter { $0.isHeading }.map { $0.detail } ?? []
    }

    @Test func `a slash at the start of a prompt opens every command`() {
        var screen = controller()
        type("/", into: &screen)
        #expect(
            Set(names(screen)) == Set((ScreenController.builtIn + Self.commands).map(\.name)),
            "the screen's own and the conversation's, headings aside")
        #expect(
            names(screen)
                == [
                    "help", "quit", "continue", "follow-up", "tasks", "config", "compact", "reload", "sidebar",
                    "verbose"
                ],
            "the session commands, then the tools")
        #expect(headings(screen) == ["session", "tools"], "commands group under their categories")
        #expect(screen.state.picker?.selected == 1, "the first command follows the first heading")
    }

    @Test func `typing narrows it with prefix matches first`() {
        var screen = controller()
        type("/co", into: &screen)
        #expect(names(screen) == ["continue", "config", "compact", "help"], "prefix matches first, then the summary's")
        #expect(headings(screen) == ["session"])
    }

    @Test func `Enter inserts the choice and never sends it`() {
        var screen = controller()
        type("/co", into: &screen)
        press(Key.down.rawValue, into: &screen)
        let effects = press(Key.enter.rawValue, into: &screen)
        #expect(effects.isEmpty)
        #expect(screen.state.editor.text == "/config " && screen.state.editor.cursor == 8)
        #expect(screen.state.picker == nil && !screen.state.running && screen.state.transcript.items.isEmpty)
    }

    @Test func `Tab completes exactly as Enter does`() {
        var screen = controller()
        type("/re", into: &screen)
        #expect(press(Key.tab.rawValue, into: &screen).isEmpty)
        #expect(screen.state.editor.text == "/reload ")
    }

    @Test func `a second Enter then runs what was inserted`() {
        var screen = controller()
        type("/rel", into: &screen)
        press(Key.enter.rawValue, into: &screen)
        #expect(press(Key.enter.rawValue, into: &screen) == [.runCommand(name: "reload", arguments: "")])
    }

    @Test func `Up and Down move through the list and wrap, and typing starts again at the top`() {
        var screen = controller()
        type("/", into: &screen)
        press(Key.down.rawValue, into: &screen)
        #expect(screen.state.picker?.selected == 2)
        press(Key.up.rawValue, into: &screen)
        press(Key.up.rawValue, into: &screen)
        #expect(
            screen.state.picker?.selected == screen.state.picker!.choiceIndexes.last,
            "Up from the first wraps to the last")
        press(Key.down.rawValue, into: &screen)
        #expect(screen.state.picker?.selected == 1, "Down from the last wraps to the first")
        press(Key.down.rawValue, into: &screen)
        type("c", into: &screen)
        #expect(screen.state.picker?.selected == 1, "typing starts again at the first command under its heading")
    }

    @Test func `Escape closes it and keeps what was typed, and more typing does not reopen it`() {
        var screen = controller()
        type("/co", into: &screen)
        #expect(press(0x1B, into: &screen).isEmpty)
        #expect(screen.state.picker == nil && screen.state.editor.text == "/co")
        type("n", into: &screen)
        #expect(screen.state.picker == nil && screen.state.editor.text == "/con")
    }

    @Test func `a fresh slash after the draft was cleared opens it again`() {
        var screen = controller()
        type("/co", into: &screen)
        press(0x1B, into: &screen)
        press(UInt32(Character("x").asciiValue!), .ctrl, into: &screen)
        #expect(screen.state.editor.text.isEmpty)
        type("/", into: &screen)
        #expect(screen.state.picker != nil)
    }

    @Test func `Escape closes the picker and never stops a running turn`() {
        var screen = controller()
        type("a prompt", into: &screen)
        press(Key.enter.rawValue, into: &screen)
        #expect(screen.state.running)
        type("/co", into: &screen)
        #expect(press(0x1B, into: &screen).isEmpty, "the first Escape only closes the picker")
        #expect(!press(0x1B, into: &screen).contains(.cancelRun), "the second Escape only arms the interruption")
        #expect(screen.state.running)
    }

    @Test func `an exact command name closes it, so Enter still runs it`() {
        var screen = controller()
        type("/config", into: &screen)
        #expect(screen.state.picker == nil)
        #expect(press(Key.enter.rawValue, into: &screen) == [.runCommand(name: "config", arguments: "")])
    }

    @Test func `no match leaves Enter as it was, so an unknown command and a path behave as before`() {
        var screen = controller()
        type("/zzz", into: &screen)
        #expect(screen.state.picker == nil)
        #expect(press(Key.enter.rawValue, into: &screen).isEmpty)
        #expect(
            screen.state.transcript.items.contains(
                .notice("There is no command /zzz; /help lists them.", isError: true)))
        var path = controller()
        type("/etc/hosts: what is this", into: &path)
        #expect(path.state.picker == nil)
        #expect(press(Key.enter.rawValue, into: &path) == [.startRun("/etc/hosts: what is this")])
    }

    @Test func `a doubled slash is a prompt, not a command word`() {
        var screen = controller()
        type("//co", into: &screen)
        #expect(screen.state.picker == nil)
        #expect(press(Key.enter.rawValue, into: &screen) == [.startRun("/co")])
    }

    @Test func `an escaped slash that names a command is still a prompt, not something to complete`() {
        // "/follow-up" appears in follow-up's own summary, so only the command-shaped rule keeps this word out of the picker.
        var screen = controller()
        type("//follow-up", into: &screen)
        #expect(screen.state.picker == nil)
        #expect(press(Key.enter.rawValue, into: &screen) == [.startRun("/follow-up")])
    }

    @Test func `a command is offered only as the first word, after any leading space`() {
        var middle = controller()
        type("please /co", into: &middle)
        #expect(middle.state.picker == nil)
        var spaced = controller()
        type(" /co", into: &spaced)
        #expect(spaced.state.picker != nil)
    }

    @Test func `accepting replaces the whole word and does not double a space that is already there`() {
        var screen = controller()
        type("/co now", into: &screen)
        for _ in 0 ..< 4 { press(Key.left.rawValue, into: &screen) }
        #expect(screen.state.picker?.trigger.query == "co")
        press(Key.enter.rawValue, into: &screen)
        #expect(screen.state.editor.text == "/continue now" && screen.state.editor.cursor == 10)
    }

    @Test func `while a turn runs Enter inserts and does not queue a steering message`() {
        var screen = controller()
        type("a prompt", into: &screen)
        press(Key.enter.rawValue, into: &screen)
        type("/co", into: &screen)
        #expect(press(Key.enter.rawValue, into: &screen).isEmpty)
        #expect(screen.state.editor.text == "/continue ")
    }

    @Test func `a paste that makes a command word opens it`() {
        var screen = controller()
        _ = screen.handle(.paste("/co"), pageRows: 30)
        #expect(screen.state.picker != nil)
    }

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
        #expect(type("y", into: &screen) == [.answerApproval(id: 7, .once)])
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
