import AemiTesting
import AskAI
import AskAgentCore
import Darwin
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// bash: real child processes, a virtual clock for timeouts, and kqueue to watch descendants die.
@Suite("bash runs commands, reports how they ended, and stops whole process groups")
struct BashToolTests {
    private let root: URL
    private let context: ToolContext

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ask-bash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        context = ToolContext(workingDirectory: root.path)
    }

    private func command(_ text: String, timeout: Int? = nil) -> JSONObject {
        var object = #"{"command":"# + Self.quoted(text)
        if let timeout { object += #","timeout_seconds":\#(timeout)"# }
        return try! JSONObject(validating: Array((object + "}").utf8))
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    @Test func `a command's combined output and exit status come back`() async {
        let output = await BashTool().run(command("echo out; echo err >&2; pwd"), in: context)
        // The physical path: /var is a symlink to /private/var, and Foundation's resolver keeps the /var form.
        let physical = String(cString: unsafe realpath(root.path, nil))
        #expect(output == ToolOutput("out\nerr\n\(physical)\n[exit 0]"))
    }

    @Test func `a failing command is an error output with its status`() async {
        let output = await BashTool().run(command("echo nope; exit 3"), in: context)
        #expect(output == .error("nope\n[exit 3]"))
    }

    @Test func `standard input is closed, so a reader ends instead of hanging`() async {
        let output = await BashTool().run(command("cat; echo done"), in: context)
        #expect(output == ToolOutput("done\n[exit 0]"))
    }

    @Test func `huge output keeps the head and the tail`() async {
        let output = await BashTool()
            .run(command("head -c 3000000 /dev/zero | tr '\\0' 'x'; echo; echo END"), in: context)
        #expect(output.content.hasPrefix("xxxx"))
        #expect(output.content.contains("bytes omitted"))
        #expect(output.content.hasSuffix("END\n[exit 0]"))
        #expect(output.content.utf8.count < 2 * BashTool.keptBytes + 200)
    }

    @Test func `a timeout stops the command and every process it started`() async throws {
        let clock = TestClock()
        let started = Started()
        let tool = BashTool(clock: clock) { event in
            if case .output(let bytes) = event { started.received(bytes) }
        }
        let task = Task { await tool.run(command("sleep 300 & echo \"child $!\"; wait", timeout: 5), in: context) }
        let child = try await started.child()
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(5))
        let output = await task.value
        #expect(output.isError && output.content.contains("timed out after 5 s"))
        #expect(try await ProcessExit.observed(child), "the backgrounded child must die with the group")
    }

    @Test func `aborting the run stops the command and its children`() async throws {
        let started = Started()
        let tool = BashTool(clock: TestClock()) { event in
            if case .output(let bytes) = event { started.received(bytes) }
        }
        let task = Task { await tool.run(command("sleep 300 & echo \"child $!\"; wait"), in: context) }
        let child = try await started.child()
        task.cancel()
        let output = await task.value
        #expect(output.isError && output.content.contains("aborted"))
        #expect(try await ProcessExit.observed(child))
    }

    /// Resolves once the command has printed `child <pid>`.
    private final class Started: Sendable {
        private let state = Mutex<(text: String, waiter: CheckedContinuation<pid_t, any Error>?, pid: pid_t?)>(
            ("", nil, nil))

        func received(_ bytes: [UInt8]) {
            let ready: (CheckedContinuation<pid_t, any Error>, pid_t)? = state.withLock { state in
                state.text += String(decoding: bytes, as: UTF8.self)
                guard state.pid == nil,
                    let line = state.text.split(separator: "\n").first(where: { $0.hasPrefix("child ") }),
                    let pid = pid_t(line.dropFirst(6))
                else { return nil }
                state.pid = pid
                return state.waiter.take().map { ($0, pid) }
            }
            if let (waiter, pid) = ready { waiter.resume(returning: pid) }
        }

        func child() async throws -> pid_t {
            try await withCheckedThrowingContinuation { continuation in
                let pid: pid_t? = state.withLock { state in
                    if state.pid == nil { state.waiter = continuation }
                    return state.pid
                }
                if let pid { continuation.resume(returning: pid) }
            }
        }
    }

    /// Waits for a process that is not our child to exit, with kqueue: an event, not a poll.
    private enum ProcessExit {
        struct Failed: Error {}

        static func observed(_ pid: pid_t) async throws -> Bool {
            let queue = kqueue()
            guard queue >= 0 else { throw Failed() }
            defer { close(queue) }
            var change = kevent(
                ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT), fflags: NOTE_EXIT,
                data: 0, udata: nil)
            var event = kevent()
            // Registering fails with ESRCH when the process is already gone, which is the answer.
            let registered = unsafe kevent(queue, &change, 1, nil, 0, nil)
            if registered < 0 { return errno == ESRCH }
            var deadline = timespec(tv_sec: 10, tv_nsec: 0)
            let count = unsafe kevent(queue, nil, 0, &event, 1, &deadline)
            return count == 1 && event.fflags & NOTE_EXIT != 0
        }
    }
}
