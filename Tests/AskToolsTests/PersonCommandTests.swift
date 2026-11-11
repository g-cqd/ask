import AemiTesting
import AskAI
import AskAgentCore
import Darwin
import Foundation
import Testing

@testable import AskTools

/// The person's own `!` command (note n56; the owner's answers of 2026-11-11): their shell, the session's sandbox, never shellcheck's
/// refusal, and a job once it has run a while.
@Suite("Your ! command runs in your shell, in the session's sandbox", .timeLimit(.minutes(1)))
struct PersonCommandTests {
    private let root: URL

    /// A tool on a clock that never moves: a command ends by itself, however slow the machine, and is never left as a job by its
    /// wait running out (the real clock's five seconds ran out on a loaded CI runner).
    private static func tool() -> BashTool {
        BashTool(jobs: JobTable(environment: ["PATH": "/usr/bin:/bin"]), clock: TestClock()) { _ in }
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ask-person-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @Test func `it runs as written, with what shellcheck would refuse, in the shell named`() async {
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = Self.tool()
        // `echo $X` unquoted is what the model's command is refused for once; the person's is not.
        let output = await tool.runForPerson(
            #"X=hi; echo $X "$0""#,
            shell: "/bin/zsh",
            in: ToolContext(workingDirectory: root.path)
        )
        #expect(output == ToolOutput("hi /bin/zsh\n[exit 0]"))
    }

    @Test func `a SHELL that is no shell gives the one the model's commands get`() async {
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = Self.tool()
        for shell in [nil, "/no/such/shell", "zsh"] as [String?] {
            let output = await tool.runForPerson(
                #"echo "$0""#,
                shell: shell,
                in: ToolContext(workingDirectory: root.path)
            )
            #expect(output.content.hasSuffix("bash\n[exit 0]"), "\(shell ?? "nil"): \(output.content)")
        }
    }

    @Test func `the session's sandbox holds`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let protected = root.appending(path: "protected")
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        let rule = SandboxRule(try #require(CanonicalPath.of(protected.path, relativeTo: "/")), .subpath)
        let context = ToolContext(workingDirectory: root.path, sandbox: SandboxPolicy(denyWrite: [rule]))
        let tool = Self.tool()
        let output = await tool.runForPerson("touch inside; touch protected/x", shell: "/bin/sh", in: context)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "inside").path))
        #expect(!FileManager.default.fileExists(atPath: protected.appending(path: "x").path))
        #expect(output.isError, "the refused write is the command's failure: \(output.content)")
        // The same command with no sandbox writes it: the check can fail.
        _ = await tool.runForPerson("touch protected/x", shell: "/bin/sh", in: ToolContext(workingDirectory: root.path))
        #expect(FileManager.default.fileExists(atPath: protected.appending(path: "x").path))
    }

    @Test func `still running after its wait, it goes on as a job`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let jobs = JobTable(environment: ["PATH": "/usr/bin:/bin"])
        let clock = TestClock()
        let tool = BashTool(jobs: jobs, clock: clock) { _ in }
        async let output = tool.runForPerson(
            "echo started; sleep 300",
            shell: "/bin/sh",
            in: ToolContext(workingDirectory: root.path)
        )
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(BashTool.personYield))
        let result = await output
        #expect(result.backgroundJob != nil && jobs.running.count == 1)
        await jobs.stopAll()
    }
}
