import TerminalKitMarkdown
import TerminalKitStyle
import Testing

@testable import AskTUI

/// Roadmap 0185: a known `/skill:name` that starts a word is drawn as a token, in the draft and in the person's sent message; an
/// unknown name, or a `/` inside a word, stays plain.
@Suite("A known skill named in a message is drawn as a token")
struct SkillTokenTests {
    private let known: Set<String> = ["/skill:debugging"]

    @Test func `the scanner finds known names at word starts, without trailing punctuation, and nothing else`() {
        let text = "use /skill:debugging, not a/skill:debugging nor /skill:nothing (/skill:debugging)"
        #expect(SkillTokens.ranges(in: text, known: known) == [4 ..< 20])
        #expect(SkillTokens.ranges(in: "/skill:debugging first", known: known) == [0 ..< 16])
        #expect(SkillTokens.ranges(in: "no skills here", known: known).isEmpty)
    }

    @Test func `the draft draws the token, whether Markdown colouring is on or not`() {
        for markdown in [true, false] {
            var layout = PromptLayout()
            var editor = PromptEditor()
            editor.restore("fix with /skill:debugging now")
            let frame = layout.frame(
                editor,
                prompt: "> ",
                columns: 60,
                screenRows: 20,
                maximumRows: 4,
                markdown: markdown,
                skills: known
            )
            let accents = frame.accents.first ?? []
            #expect(
                accents.contains { $0.columns == 11 ..< 27 && $0.style == SkillTokens.style },
                "markdown \(markdown)"
            )
        }
    }

    @Test func `the sent message draws the token on top of its bold look, Markdown on or off`() {
        for markdown in [true, false] {
            var transcript = Transcript()
            transcript.setMarkdown(markdown)
            transcript.setTokenNames(known)
            transcript.addUser("fix with /skill:debugging now")
            let row = ScreenComposer.lines(in: transcript, at: 0, columns: 60).first { $0.text.contains("/skill:") }
            let accent = row?.accents.first { $0.style.bold && $0.style.fg == SkillTokens.style.fg }
            #expect(accent != nil, "markdown \(markdown)")
            #expect(accent.map { row!.text.dropFirst($0.columns.lowerBound).hasPrefix("/skill:debugging") } == true)
        }
    }
}
