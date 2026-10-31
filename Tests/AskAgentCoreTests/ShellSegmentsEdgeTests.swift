import Testing

@testable import AskAgentCore

/// The edges of `ShellSegments` that mutation testing found untested (roadmap 0166): escapes outside quotes and telling `<<` from `<<<`,
/// each pinned by the exact segments, so a changed bound or offset shows.
@Suite("Shell segments at escapes and redirections")
struct ShellSegmentsEdgeTests {
    @Test func `a backslash ending the line is dropped, and nothing is read past the end`() {
        #expect(ShellSegments.split("ls \\") == ["ls "])
        #expect(ShellSegments.split("\\") == [""])
    }

    @Test func `a backslash before a line end continues the command with a space`() {
        #expect(ShellSegments.split("echo a\\\nrm x") == ["echo a rm x"])
    }

    @Test func `an escaped character is kept once, and the one after it is read normally`() {
        #expect(ShellSegments.split("echo a\\; rm x") == ["echo a; rm x"])
        #expect(ShellSegments.split("echo \\ab;ls") == ["echo ab", "ls"])
        #expect(ShellSegments.split("a\\\\;b") == ["a\\", "b"])
    }

    @Test func `a here-string is not a heredoc`() {
        #expect(ShellSegments.split("cat <<< x\nrm y") == ["cat <<< x", "rm y"])
        #expect(ShellSegments.split("cat <<<") == ["cat <<<"])
    }

    @Test func `a heredoc marker at the end of the line opens nothing to read`() {
        #expect(ShellSegments.split("cat <<") == ["cat  <<"])
        #expect(ShellSegments.split("cat <<E") == ["cat  <<E"])
    }

    @Test func `a single redirection is not a heredoc`() {
        #expect(ShellSegments.split("sort < in") == ["sort < in"])
        #expect(ShellSegments.split("sort <") == ["sort <"])
        #expect(ShellSegments.split("a <b\nc") == ["a <b", "c"])
    }
}
