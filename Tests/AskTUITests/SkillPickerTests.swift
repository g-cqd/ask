import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Skills in the `/` picker (roadmap 0061, phase 3): asked for once, on the first slash and never before, listed after the commands with a skill tag,
/// and chosen into the draft like a command.
@Suite("The command picker lists skills after the commands, asking for them once")
struct SkillPickerTests {
    private static let skills = [
        SlashCommand(name: "skill:code-review", summary: "skill · Reviews a diff.", category: .tools),
        SlashCommand(name: "skill:debugging", summary: "skill · Finds a bug.", category: .tools)
    ]

    private func controller() -> ScreenController {
        ScreenController(
            label: "m", commands: [SlashCommand(name: "config", summary: "Show the settings.")], options: .legacy)
    }

    @discardableResult
    private func type(_ text: String, into screen: inout ScreenController) -> [ScreenController.Effect] {
        var effects: [ScreenController.Effect] = []
        for scalar in text.unicodeScalars {
            effects += screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30)
        }
        return effects
    }

    private func labels(_ screen: ScreenController) -> [String] {
        screen.state.picker?.matches.filter { !$0.isHeading }.map(\.label) ?? []
    }

    @Test func `the first slash asks for the skills and later keys do not`() {
        var screen = controller()
        var other = controller()
        #expect(type("hello there", into: &other).isEmpty)
        let first = type("/", into: &screen)
        let more = type("co", into: &screen)
        #expect(first == [.listSkills])
        #expect(more.isEmpty)
    }

    @Test func `skills arrive after the commands and are shown with their tag`() {
        var screen = controller()
        type("/", into: &screen)
        screen.handle(.skills(Self.skills))
        let all = labels(screen)
        #expect(all.first == "/help")
        #expect(
            all == [
                "/help", "/quit", "/continue", "/follow-up", "/jobs", "/config", "/sidebar", "/verbose",
                "/skill:code-review", "/skill:debugging"
            ], "session commands, then the tools, skills last")
        #expect(screen.state.picker?.matches.last?.detail.hasPrefix("skill · ") == true)
        #expect(
            screen.state.picker?.matches.filter { $0.isHeading }.map { $0.detail } == ["session", "tools"],
            "the skills group under the tools heading, as the conversation categorises them")
    }

    @Test func `typing skill and a colon narrows to skills, and a name typed in full closes the picker`() {
        var screen = controller()
        screen.handle(.skills(Self.skills))
        type("/skill:d", into: &screen)
        #expect(labels(screen) == ["/skill:debugging"])
        type("ebugging", into: &screen)
        #expect(screen.state.picker == nil)
    }

    @Test func `a skill is chosen into the draft with Tab and nothing is sent`() {
        var screen = controller()
        screen.handle(.skills(Self.skills))
        type("/skill:cod", into: &screen)
        let effects = screen.handle(.key(KeyEvent(keyCode: 9)), pageRows: 30)
        #expect(effects.isEmpty)
        #expect(screen.state.editor.text.hasPrefix("/skill:code-review"))
    }

    @Test func `a skill list that arrives while the picker is open refreshes it`() {
        var screen = controller()
        type("/skill", into: &screen)
        #expect(screen.state.picker == nil)
        screen.handle(.skills(Self.skills))
        #expect(labels(screen) == ["/skill:code-review", "/skill:debugging"])
    }

    @Test func `a submitted skill line is a prompt for the conversation, not an unknown command`() {
        var screen = controller()
        screen.handle(.skills(Self.skills))
        type("/skill:debugging find it", into: &screen)
        let effects = screen.handle(.key(KeyEvent(keyCode: 13)), pageRows: 30)
        #expect(effects.contains(.startRun("/skill:debugging find it")))
    }
}
