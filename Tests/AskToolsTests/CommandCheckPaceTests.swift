import Foundation
import Synchronization
import Testing

@testable import AskTools

/// What the check before a command costs (diary 2026-11-14-07): shellcheck's start is 21 ms and the shell's parse up to 10, on every
/// command, so they run side by side.
///
/// The two programs here are closures, not processes. The first versions of these tests ran scripts that waited on one another:
/// a waiting script holds the thread its `Process` call runs on, the tasks of every test share those threads, and on a CI runner
/// with few of them the whole test process stood still until other suites hit their time limits (diary 2026-11-15-02).
@Suite("The check before a command runs its two parts together", .timeLimit(.minutes(1)))
struct CommandCheckPaceTests {
    private static let clean = CommandCheck.Outcome.ran(CommandCheck.Ran(status: 0, output: "", error: ""))

    @Test func `shellcheck starts while the shell parses, not after it`() async throws {
        let fixture = try CheckFixture(shellcheck: "exit 0")
        defer { fixture.remove() }
        // The parse here ends only once shellcheck has started: run one after the other, it would not end before the time limit.
        let (started, start) = AsyncStream<Void>.makeStream()
        let runner: CommandCheck.Runner = { executable, _, _, _, _ in
            if executable.hasSuffix("/shellcheck") {
                start.finish()
            } else {
                for await _ in started {}
            }
            return Self.clean
        }
        let checked = await CommandCheck.check("echo hi", shell: "/bin/bash", path: fixture.path, run: runner)
        #expect(checked == CommandCheck.Result(), "parsed, and nothing found")
    }

    @Test func `a command that does not parse is told so without waiting for shellcheck`() async throws {
        let fixture = try CheckFixture(shellcheck: "exit 0")
        defer { fixture.remove() }
        // A shellcheck that ends only when the test lets it, which is after the answer. An answer that waited for it would come
        // only when the time limit cancels the test, which lets it go and fails the test by that limit.
        let (released, release) = AsyncStream<Void>.makeStream()
        let runner: CommandCheck.Runner = { executable, _, _, _, _ in
            guard executable.hasSuffix("/shellcheck") else {
                return .ran(CommandCheck.Ran(status: 2, output: "", error: "unexpected EOF\n"))
            }
            for await _ in released {}
            return .ran(CommandCheck.Ran(status: 1, output: "-:1:1: warning: too late to matter [SC2164]\n", error: ""))
        }
        let checked = await withTaskCancellationHandler {
            await CommandCheck.check(#"echo "open"#, shell: "/bin/bash", path: fixture.path, run: runner)
        } onCancel: {
            release.finish()
        }
        release.finish()
        #expect(checked.syntaxError == "unexpected EOF")
        #expect(!checked.unchecked && checked.findings.isEmpty)
    }

    @Test func `each part is run with its own arguments, the command, the PATH alone and the deadline`() async throws {
        let fixture = try CheckFixture(shellcheck: "exit 0")
        defer { fixture.remove() }
        let calls = Mutex<[String]>([])
        let runner: CommandCheck.Runner = { executable, arguments, input, environment, deadline in
            let name = (executable as NSString).lastPathComponent
            calls.withLock { $0.append("\(name) \(arguments) input \(input ?? "none") \(environment) \(deadline)") }
            return name == "bash"
                ? Self.clean : .ran(CommandCheck.Ran(status: 1, output: "-:1:1: note: x [SC1]\n", error: ""))
        }
        let checked = await CommandCheck.check(
            "echo hi",
            shell: "/bin/bash",
            path: fixture.path,
            deadline: .seconds(7),
            run: runner
        )
        let path = #"["PATH": "\#(fixture.path)"]"#
        #expect(
            calls.withLock { $0 }.sorted() == [
                #"bash ["-n", "-c", "echo hi"] input none \#(path) 7.0 seconds"#,
                #"shellcheck ["--norc", "-s", "bash", "-S", "warning", "-f", "gcc", "-"] input echo hi \#(path) 7.0 seconds"#
            ]
        )
        #expect(checked.findings == ["1:1: note: x [SC1]"], "what shellcheck printed, without its name for its input")
    }

    @Test(arguments: ["bash", "shellcheck"])
    func `a part that ran past its deadline leaves the command unchecked, whichever it was`(late: String) async throws {
        let fixture = try CheckFixture(shellcheck: "exit 0")
        defer { fixture.remove() }
        let runner: CommandCheck.Runner = { executable, _, _, _, _ in
            executable.hasSuffix("/" + late) ? .late : Self.clean
        }
        let checked = await CommandCheck.check("echo hi", shell: "/bin/bash", path: fixture.path, run: runner)
        #expect(checked.unchecked && checked.syntaxError == nil && checked.findings.isEmpty)
    }
}
