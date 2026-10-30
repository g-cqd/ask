import Testing

@testable import AskAgentCore

/// What a session grant covers (roadmap 0134): a subcommand, a program, a file or a tool; a line only when all its commands are.
@Suite("What the person allowed for the session")
struct CallGrantsTests {
    @Test func `a subcommand grant covers that subcommand, not the program's others`() {
        var grants = CallGrants()
        grants.grant(.command(CommandWords("git status -s")))
        #expect(grants.covers(.command(CommandWords("git status"))))
        #expect(!grants.covers(.command(CommandWords("git push"))))
    }

    @Test func `a program grant covers every use of it, and a line needs all its commands covered`() {
        var grants = CallGrants()
        grants.grantPrograms(CommandWords("git status"))
        #expect(grants.covers(.command(CommandWords("git push origin main"))))
        #expect(!grants.covers(.command(CommandWords("git status && rm -rf build"))))
        #expect(!grants.covers(.command(CommandWords("git log $(rm x)"))), "a substitution is never covered")
    }

    @Test func `files and tools are covered by name`() {
        var grants = CallGrants()
        grants.grant(.file("/p/a.swift"))
        grants.grant(.tool("job"))
        #expect(grants.covers(.file("/p/a.swift")) && !grants.covers(.file("/p/b.swift")))
        #expect(grants.covers(.tool("job")) && !grants.covers(.tool("read")))
    }
}
