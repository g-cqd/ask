import AemiTesting
import Darwin
import Foundation
import Testing

@testable import AskTools

/// The self-check against real programs standing in for a new build: one that passes, one that fails, one that
/// cannot start, one that hangs.
@Suite("A new build is run with --self-check before anything switches to it", .timeLimit(.minutes(1)))
struct SelfCheckTests {
    /// What a check gets in these tests, which are about its outcome, not its time limit: a loaded CI runner took more than the
    /// 10 s a real check gets to start a one-line script (2026-11-04). The limit itself is the hanging build's test, on a test clock.
    private static let patience = Duration.seconds(45)
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-selfcheck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// A shell script standing in for a build; it sees `--self-check` as its first argument.
    private func build(_ body: String, executable: Bool = true) throws -> String {
        let url = directory.appending(path: "ask")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url.path
    }

    @Test func `a build that checks itself and exits 0 passes, and says what it printed`() async throws {
        let path = try build(#"[ "$1" = "--self-check" ] && echo "ask self-check ok" || exit 9"#)
        #expect(await SelfCheck.run(path, timeout: Self.patience) == .passed("ask self-check ok"))
    }

    @Test func `the arguments a reload will pass are the arguments the check runs with`() async throws {
        let path = try build(
            #"[ "$1 $2 $3 $4 $5" = "--self-check --selected-provider local --selected-model a/b:c" ] && echo "ask self-check ok" || exit 9"#
        )
        let outcome = await SelfCheck.run(
            path,
            arguments: ["--selected-provider", "local", "--selected-model", "a/b:c"],
            timeout: Self.patience
        )
        #expect(outcome == .passed("ask self-check ok"))
        #expect(
            await SelfCheck.run(path, timeout: Self.patience) == .failed("it exited 9"),
            "without them the same build fails"
        )
    }

    @Test func `the check runs with the environment it is given, not the one this process holds`() async throws {
        let path = try build(#"[ "$1" = "--self-check" ] && echo "key=[$SELFCHECK_PROBE_KEY] home=[$HOME]""#)
        setenv("SELFCHECK_PROBE_KEY", "", 1)  // as ask's own copy is once its credentials are blanked (ADR-0113)
        defer { unsetenv("SELFCHECK_PROBE_KEY") }
        let given = ["SELFCHECK_PROBE_KEY": "launch-value", "HOME": "/given"]
        #expect(
            await SelfCheck.run(path, environment: given, timeout: Self.patience)
                == .passed("key=[launch-value] home=[/given]")
        )
        guard case .passed(let inherited) = await SelfCheck.run(path, timeout: Self.patience) else {
            Issue.record("the default run did not pass")
            return
        }
        #expect(inherited.hasPrefix("key=[] "), "with none given, the child inherits this process's")
    }

    @Test func `reload checks the new build in its captured workspace and refuses a missing one`() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = directory.appending(path: "project with spaces", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let path = try build("/bin/pwd -P")
        let outcome = await SelfCheck.run(path, workingDirectory: workspace.path, timeout: Self.patience)
        guard case .passed(let observed) = outcome else {
            Issue.record("workspace self-check failed: \(outcome)")
            return
        }
        #expect(URL(fileURLWithPath: observed).resolvingSymlinksInPath() == workspace.resolvingSymlinksInPath())
        guard
            case .failed = await SelfCheck.run(
                path,
                workingDirectory: workspace.appending(path: "missing").path,
                timeout: Self.patience
            )
        else {
            Issue.record("a missing reload workspace must not fall back to the parent's cwd")
            return
        }
    }

    @Test func `a build that exits non-zero fails, with its code and what it said on standard error`() async throws {
        let path = try build(#"echo "config.json:3:13: unexpected ']'" >&2; exit 78"#)
        #expect(
            await SelfCheck.run(path, timeout: Self.patience)
                == .failed("it exited 78: config.json:3:13: unexpected ']'")
        )
    }

    @Test func `a build that dies by a signal fails, and says which`() async throws {
        let path = try build("kill -SEGV $$")
        #expect(await SelfCheck.run(path, timeout: Self.patience) == .failed("it was killed by signal 11"))
    }

    @Test func `a file that is not executable, or not there, fails to start rather than throwing`() async throws {
        let notExecutable = try build("exit 0", executable: false)
        guard case .failed(let reason) = await SelfCheck.run(notExecutable, timeout: Self.patience) else {
            Issue.record("a file without the execute bit passed")
            return
        }
        #expect(reason.hasPrefix("it could not start"))
        guard case .failed = await SelfCheck.run(directory.appending(path: "absent").path, timeout: Self.patience)
        else {
            Issue.record("a missing file passed")
            return
        }
    }

    @Test func `a build that hangs is stopped at the timeout, with its children`() async throws {
        let pidFile = directory.appending(path: "child.pid").path
        // The test waits for the pid file, an event, not for time: the build wrote it once its child was running.
        // Both the build and its child ignore SIGTERM, as a stubborn program might, so only SIGKILL to the whole
        // group ends them: that is the step under test.
        let path = try build("trap '' TERM; (trap '' TERM; exec sleep 300) & echo $! > '\(pidFile)'; wait")
        let clock = TestClock()
        async let outcome = SelfCheck.run(path, timeout: .seconds(10), clock: clock)
        try await clock.waitForSleepers(count: 1)
        _ = await FileWait.until(exists: pidFile)
        clock.advance(by: .seconds(10))
        #expect(await outcome == .failed("it did not finish within 10 s, so it was stopped"))
        let child = try #require(
            pid_t(String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        )
        #expect(try await ProcessExit.observed(child), "the build's child must die with it")
    }
}
