import AemiTesting
import Darwin
import Foundation
import Testing

@testable import AskTools

/// An opener's command (ADR-0148) against scripts standing in for an editor: run with its arguments as they are, no shell, no input.
@Suite("An opener's command runs as its arguments say, with no shell", .timeLimit(.minutes(1)))
struct OpenerLaunchTests {
    private let directory: URL
    private var environment: [String: String] { ["PATH": directory.path + ":/usr/bin:/bin", "MARK": "kept"] }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-opener-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// A script named `name` in the directory, which is first on the PATH these tests give.
    @discardableResult
    private func tool(_ body: String, named name: String = "tool") throws -> String {
        let url = directory.appending(path: name)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func read(_ name: String) -> String? {
        try? String(contentsOf: directory.appending(path: name), encoding: .utf8)
    }

    @Test func `the arguments reach the program as written: nothing in them is read by a shell`() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try tool(#"printf '%s|' "$#" "$@" > out; printf '%s' "$MARK" > mark; pwd -P > where"#)
        let hostile = ["a b; touch pwned", "$(touch pwned)", "`touch pwned`", "x > pwned", "*"]
        let outcome = await OpenerLaunch.run(
            ["tool"] + hostile,
            environment: environment,
            workingDirectory: directory.path
        )
        #expect(outcome == .finished)
        #expect(read("out") == "5|" + hostile.map { $0 + "|" }.joined())
        #expect(read("pwned") == nil)
        #expect(read("mark") == "kept", "the environment it is given, not this process's")
        #expect(read("where")?.hasSuffix(directory.lastPathComponent + "\n") == true)
    }

    @Test func `a program is found on the given PATH or by its path, and one that is not there is said`() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try tool("exit 0")
        #expect(await OpenerLaunch.run([path], environment: [:], workingDirectory: directory.path) == .finished)
        #expect(
            await OpenerLaunch.run(["no-such-tool-1234"], environment: environment, workingDirectory: directory.path)
                == .failed("no-such-tool-1234 is not on your PATH")
        )
        #expect(
            await OpenerLaunch.run(
                [directory.path + "/absent"],
                environment: environment,
                workingDirectory: directory.path
            )
                == .failed("\(directory.path)/absent is not a program that can be run")
        )
        #expect(
            await OpenerLaunch.run([], environment: environment, workingDirectory: directory.path)
                == .failed("no program")
        )
    }

    @Test func `it has no input to wait for, and a status that is not 0 is reported`() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try tool("read line; exit 3")
        #expect(
            await OpenerLaunch.run(["tool"], environment: environment, workingDirectory: directory.path) == .exited(3)
        )
    }

    @Test func `a program that stays open is left running`() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appending(path: "pid").path
        try tool("echo $$ > '\(pidFile)'; exec sleep 300")
        let clock = TestClock()
        async let outcome = OpenerLaunch.run(
            ["tool"],
            environment: environment,
            workingDirectory: directory.path,
            patience: .seconds(2),
            clock: clock
        )
        try await clock.waitForSleepers(count: 1)
        _ = await FileWait.until(exists: pidFile)
        clock.advance(by: .seconds(2))
        #expect(await outcome == .running)
        let pid = try #require(
            pid_t(String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        )
        #expect(kill(pid, 0) == 0, "still running after the wait")
        kill(pid, SIGKILL)
    }
}
