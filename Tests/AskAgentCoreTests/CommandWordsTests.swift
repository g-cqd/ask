import Testing

@testable import AskAgentCore

/// What a session grant for a command names (roadmap 0134): the program and its subcommand (`git status`), and the program alone (`git`),
/// for every command a line runs. A line whose commands cannot all be known (a substitution) is never covered by a grant.
@Suite("The words a command's grant names")
struct CommandWordsTests {
    @Test func `a program and its subcommand, without options, paths or variables`() {
        let words = CommandWords("git status -s")
        #expect(words.phrases == ["git status"] && words.programs == ["git"] && words.coverable)
        #expect(CommandWords("FOO=1 /usr/bin/swift build -c release").phrases == ["swift build"])
        #expect(CommandWords("FOO=1 /usr/bin/swift build -c release").programs == ["swift"])
        #expect(CommandWords("rm -rf build").phrases == ["rm"], "an option is not a subcommand")
        #expect(CommandWords("cat notes.txt").phrases == ["cat"], "a file is not a subcommand")
    }

    @Test func `every command of a line is named`() {
        let words = CommandWords("git add . && git commit -m x; swift test | tail -3")
        #expect(words.phrases == ["git add", "git commit", "swift test", "tail"])
        #expect(words.programs == ["git", "swift", "tail"])
        #expect(words.coverable)
    }

    @Test func `a substitution or a backquote makes the line uncoverable`() {
        #expect(!CommandWords("echo $(rm -rf x)").coverable)
        #expect(!CommandWords("echo `id`").coverable)
        #expect(!CommandWords("").coverable)
    }
}
