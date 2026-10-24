internal import Foundation
internal import Testing

@testable import AskTUI

/// The host command is run for real: a copy is finished when the command has exited with status 0, not when it started.
@Suite("The host pasteboard command's exit decides whether a copy worked", .timeLimit(.minutes(1)))
struct HostPasteboardTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-pb-\(UUID().uuidString)")

    private func run(_ text: String, _ executable: String, _ arguments: [String] = [], timeout: Duration = .seconds(20))
        async
        -> PasteboardResult
    {
        await HostPasteboard.run(text, executable: executable, arguments: arguments, timeout: timeout)
    }

    @Test func `a command that exits 0 after reading the text is a copy, and it received exactly the text`()
        async throws
    {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "out").path
        let text = "héllo\nwörld 日本"
        let result = await run(text, "/bin/sh", ["-c", "cat > \"$0\"", file])
        #expect(result == .copied)
        #expect(try String(contentsOfFile: file, encoding: .utf8) == text)
    }

    @Test func `a large text goes through the pipe whole`() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "big").path
        let text = String(repeating: "0123456789abcdef", count: 100_000)
        let result = await run(text, "/bin/sh", ["-c", "cat > \"$0\"", file])
        #expect(result == .copied)
        #expect(try Data(contentsOf: URL(fileURLWithPath: file)).count == text.utf8.count)
    }

    @Test func `a command that exits non-zero is a failure that names its status`() async {
        #expect(await run("x", "/usr/bin/false") == .failed("false exited with status 1"))
    }

    @Test func `a command that is not there is a failure to start`() async {
        #expect(await run("x", "/nonexistent/pbcopy") == .failed("pbcopy could not start"))
    }

    @Test func `a command that hangs is stopped at the deadline and reported`() async {
        let started = ContinuousClock.now
        let result = await run("x", "/bin/sleep", ["30"], timeout: .milliseconds(300))
        #expect(result == .failed("sleep did not finish in time"))
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func `a command that exits before reading is a result, not a hang or a crash`() async {
        let text = String(repeating: "x", count: 1_000_000)
        let result = await run(text, "/usr/bin/true")
        #expect(result == .copied)
    }
}
