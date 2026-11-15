import Foundation
import Testing

@testable import AskTools

/// What a checked program is given on its input (shellcheck reads the command there), when the program does not read it. Found by
/// the CI runner (run 43660679030): the test process died of SIGPIPE, because a fake shellcheck there ended before its input was
/// written. For ask the same is a shellcheck that fails to start, which would have ended ask.
@Suite("A program that does not read its input neither ends ask nor outlives its deadline", .timeLimit(.minutes(1)))
struct CommandCheckInputTests {
    /// More than a pipe holds (64 KiB), so the write cannot finish unless the program reads or its end of the pipe closes.
    private let input = String(repeating: "x", count: 1 << 20)

    private func program(_ body: String) throws -> String {
        let path = NSTemporaryDirectory() + "ask-input-\(UUID().uuidString)"
        try "#!/bin/sh\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    @Test func `a program that ends without reading its input is reported with its status`() async throws {
        let path = try program("echo said; exit 3")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let outcome = await CommandCheck.run(path, [], input: input, environment: [:], deadline: .seconds(30))
        #expect(outcome == .ran(CommandCheck.Ran(status: 3, output: "said\n", error: "")))
    }

    @Test func `a program that neither reads its input nor ends is stopped at the deadline`() async throws {
        // `exec`, so the signal reaches the program that holds the pipe and not a shell waiting on it.
        let path = try program("exec /bin/sleep 600")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let outcome = await CommandCheck.run(path, [], input: input, environment: [:], deadline: .milliseconds(200))
        #expect(outcome == .late)
    }

    @Test func `a program that reads its input is given all of it`() async throws {
        let path = try program("/usr/bin/wc -c | /usr/bin/tr -d ' '")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let outcome = await CommandCheck.run(path, [], input: input, environment: [:], deadline: .seconds(30))
        #expect(outcome == .ran(CommandCheck.Ran(status: 0, output: "\(1 << 20)\n", error: "")))
    }
}
