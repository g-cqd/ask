internal import Testing

@testable import AskAgentCore

/// What the model reads of the person's `!` command: the command and its output verbatim, in a code block no output can close.
@Suite("A ! command's result is told to the model verbatim")
struct ShellReportTests {
    @Test func `the command and its output, in a code block`() {
        #expect(
            ShellReport.text(command: "git status", output: "clean\n[exit 0]", job: nil)
                == "I ran this in my shell:\n\n```\n$ git status\nclean\n[exit 0]\n```\n"
        )
    }

    @Test func `output holding a fence gets a longer one, so it cannot end the block`() {
        let text = ShellReport.text(command: "cat a.md", output: "```swift\nx\n````\n[exit 0]", job: nil)
        #expect(text.hasPrefix("I ran this in my shell:\n\n`````\n$ cat a.md\n") && text.hasSuffix("\n`````\n"))
    }

    @Test func `a command left running says which job it is`() {
        #expect(
            ShellReport.text(command: "npm run dev", output: "ready", job: "job-3")
                == "I ran this in my shell; it is still running as job-3:\n\n```\n$ npm run dev\nready\n```\n"
        )
    }
}
