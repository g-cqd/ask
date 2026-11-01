import TerminalKitCodecs
import TerminalKitInput
import Testing

@testable import AskTUI

/// Roadmap 0185: a `/` that starts a later word of the draft opens the picker on the skills alone; the commands stay first-word only.
@Suite("A slash mid-draft offers the skills, and only at the start of a word")
struct InlineSkillPickerTests {
    private func screen(_ draft: String) -> ScreenController {
        var screen = ScreenController(label: "m", commands: [SlashCommand(name: "model", summary: "Choose a model.")])
        screen.setScreenRows(30)
        _ = screen.handle(
            .skills([
                SlashCommand(name: "skill:debugging", summary: "Finds why something fails."),
                SlashCommand(name: "skill:review", summary: "Reviews a diff.")
            ])
        )
        for scalar in draft.unicodeScalars { _ = screen.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30) }
        return screen
    }

    private func labels(_ screen: ScreenController) -> [String] {
        screen.state.picker?.matches.filter { !$0.isHeading }.map(\.label) ?? []
    }

    @Test func `a slash starting a later word lists the skills, not the commands, and choosing one puts it in place`() {
        var screen = screen("fix it with /deb")
        #expect(labels(screen) == ["/skill:debugging"])
        _ = screen.handle(.key(KeyEvent(keyCode: Key.enter.rawValue)), pageRows: 30)
        #expect(screen.state.editor.text == "fix it with /skill:debugging ")
        #expect(labels(self.screen("then /mod")).isEmpty)
    }

    @Test func `a slash inside a word, a path, or the first word's own picker are left as they were`() {
        #expect(labels(screen("see src/deb")).isEmpty)
        #expect(labels(screen("open /usr/bin")).isEmpty)
        #expect(labels(screen("/mod")) == ["/model"])
        var resume = ScreenController(
            label: "m",
            commands: [SlashCommand(name: "resume", summary: "r", takesChoices: true)]
        )
        resume.setScreenRows(30)
        _ = resume.handle(.skills([SlashCommand(name: "skill:tmp", summary: "t")]))
        _ = resume.handle(
            .choices(
                command: "resume",
                rows: [ChoiceRow(label: "s", detail: "/tmp/s.jsonl", arguments: "/tmp/s.jsonl")]
            )
        )
        for scalar in "/resume /tm".unicodeScalars {
            _ = resume.handle(.key(KeyEvent(keyCode: scalar.value)), pageRows: 30)
        }
        #expect(resume.state.picker?.kind != .commands, "a command's argument keeps the command's list")
    }
}
