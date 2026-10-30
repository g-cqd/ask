import Testing

@testable import AskAgentCore

/// A heredoc's body and a quoted newline or separator are data, not commands: the session answers name only the programs a line runs.
/// Every rule leans the safe way: a command after a heredoc is still named, and a body that might have ended has ended.
@Suite("The words of a command with heredocs and quotes")
struct CommandWordsQuotingTests {
    @Test func `a heredoc's body is not commands`() {
        let script = "python3 - <<'PY'\nimport platform\nfor key in ('a', 'b'):\n    print(key)\nPY"
        #expect(CommandWords(script).programs == ["python3"])
        #expect(CommandWords("cat <<EOF > notes\nrm -rf build\nEOF\ngit status").phrases == ["cat", "git status"])
        #expect(CommandWords("cat <<-\"END\"\n\trm x\n\tEND\nls").programs == ["cat", "ls"])
        #expect(CommandWords("cat <<A <<B\nrm a\nA\nrm b\nB\nls").programs == ["cat", "ls"], "two bodies, in order")
    }

    @Test func `what follows a heredoc on its own line still runs`() {
        #expect(CommandWords("cat <<EOF; rm -rf build\nbody\nEOF").programs == ["cat", "rm"])
        #expect(
            CommandWords("cat <<EOF\nbody\nEOF \nrm x").programs == ["cat", "rm"],
            "a terminator with spaces ends it, the safe way")
        #expect(CommandWords("cat <<< \"x\"; ls").programs == ["cat", "ls"], "a here-string has no body")
    }

    @Test func `separators and newlines inside quotes split nothing`() {
        #expect(CommandWords("echo \"a; b | c\" && git status").phrases == ["echo", "git status"])
        #expect(CommandWords("python3 -c 'import os\nprint(1)'").programs == ["python3"])
        #expect(
            CommandWords("echo 'a\\'; rm x").programs == ["echo", "rm"], "a backslash ends nothing in single quotes")
        #expect(
            CommandWords("echo \"a\\\"; rm x\"").programs == ["echo"], "an escaped double quote keeps the string open")
        #expect(CommandWords("echo a\\; rm x").programs == ["echo"], "an escaped separator is a word")
        #expect(CommandWords("git \\\n  status").phrases == ["git status"], "a continued line is one command")
    }
}
