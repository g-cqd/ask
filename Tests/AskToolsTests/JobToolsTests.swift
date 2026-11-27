import AemiTesting
import AskAI
import AskAgentCore
import Darwin
import Foundation
import Testing

@testable import AskTools

/// Jobs: a command left running at yield_seconds, then waited on, written to and stopped. Real processes,
/// virtual clocks for every time limit, and output observed through the hook rather than slept for.
@Suite("Long commands run as jobs that can be waited on, written to and stopped", .timeLimit(.minutes(1)))
struct JobToolsTests {
    private let root: URL
    private let context: ToolContext
    private let jobs = JobTable(
        environment: ProcessInfo.processInfo.environment.merging(["SHELL": "/bin/bash"]) { _, shell in shell }
    )

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ask-jobs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        context = ToolContext(workingDirectory: root.path)
    }

    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    /// Starts `command` with yield_seconds 5 and returns once it is a job: after `printed` appeared.
    private func started(_ command: String, printed: String) async throws -> (ToolOutput, Started?) {
        let clock = TestClock()
        let seen = Printed(printed)
        let child = Started()
        let bash = BashTool(jobs: jobs, clock: clock) { event in
            if case .output(let bytes) = event {
                seen.received(bytes)
                child.received(bytes)
            }
        }
        let quoted = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        async let task = bash.run(input(#"{"command":"\#(quoted)","yield_seconds":5}"#), in: context)
        await seen.seen()
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(5))
        return (await task, command.contains("child") ? child : nil)
    }

    @Test func `a command still running at yield_seconds is left running as a job, and takes input`() async throws {
        let (yielded, _) = try await started(#"echo ready; read line; echo "got $line""#, printed: "ready")
        #expect(!yielded.isError)
        #expect(yielded.content.hasPrefix("ready\n[still running as job-1 after 5 s"))
        #expect(jobs.running == ["job-1"])
        let reply = await JobActionTool(jobs: jobs)
            .run(input(#"{"job":"job-1","action":"input","text":"hello\n"}"#), in: context)
        #expect(reply == ToolOutput("[job-1 ended]\ngot hello\n[exit 0]"))
        #expect(jobs.running.isEmpty)
    }

    // MARK: - consolidated job tool (input, stop, status)

    @Test func `job tool actions handle input, status check, and stop`() async throws {
        _ = try await started(#"echo ready; read line; echo "got $line"; read hold"#, printed: "ready")
        let jobTool = JobActionTool(jobs: jobs)

        let statusOutput = await jobTool.run(input(#"{"job":"job-1","action":"status"}"#), in: context)
        #expect(!statusOutput.isError && statusOutput.content.contains("running"))

        let inputReply = await jobTool.run(input(#"{"job":"job-1","action":"input","text":"hello\n"}"#), in: context)
        #expect(!inputReply.isError && inputReply.content.contains("got hello"))

        let stopReply = await jobTool.run(input(#"{"job":"job-1","action":"stop"}"#), in: context)
        #expect(!stopReply.isError && stopReply.content.contains("stopped"))
        #expect(jobs.running.isEmpty)
    }

    @Test func `text split across chunks, some printed before the wait began, is still found`() async throws {
        let clock = TestClock()
        let first = Printed("RE")
        let second = Printed("REA")
        let bash = BashTool(jobs: jobs, clock: clock) { event in
            if case .output(let bytes) = event {
                first.received(bytes)
                second.received(bytes)
            }
        }
        let command = #"printf RE; read a; printf A; read b; printf 'DY\\n'; read c"#
        async let task = bash.run(input(#"{"command":"\#(command)","yield_seconds":5}"#), in: context)
        await first.seen()
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(5))
        _ = await task
        let job = try #require(jobs.job("job-1"))
        async let waiting = job.wait(for: Array("READY".utf8))
        #expect(job.write(Array("1\n".utf8)))
        await second.seen()
        #expect(job.write(Array("2\n".utf8)))
        #expect(await waiting == .found)
        await jobs.stopAll()
    }

    @Test func `a wait that times out says so, and is not an error`() async throws {
        _ = try await started("echo up; read never", printed: "up")
        let clock = TestClock()
        async let waiting = JobActionTool(jobs: jobs, clock: clock)
            .run(input(#"{"job":"job-1","action":"wait","timeout_seconds":7}"#), in: context)
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(7))
        #expect(await waiting == ToolOutput("[nothing happened within 7 s; job-1 still running]"))
        await jobs.stopAll()
    }

    @Test func `a stop ends the job and every process it started`() async throws {
        let (_, started) = try await started(#"sleep 300 & echo "child $!"; wait"#, printed: "child ")
        let child = try await #require(started).child()
        let stopped = await JobActionTool(jobs: jobs).run(input(#"{"job":"job-1","action":"stop"}"#), in: context)
        #expect(!stopped.isError && stopped.content.hasPrefix("[job-1 stopped]"))
        #expect(try await ProcessExit.observed(child), "the backgrounded child must die with the group")
    }

    /// ADR-0160: a stop that happened is the tool succeeding; a stop of what had already been stopped is told as it ended, an error.
    @Test func `stopping a job that was already stopped says so, and is no success`() async throws {
        _ = try await started(#"sleep 300 & echo "child $!"; wait"#, printed: "child ")
        let tool = JobActionTool(jobs: jobs)
        let first = await tool.run(input(#"{"job":"job-1","action":"stop"}"#), in: context)
        #expect(!first.isError && first.content.hasPrefix("[job-1 stopped]"), "\(first)")
        let again = await tool.run(input(#"{"job":"job-1","action":"stop"}"#), in: context)
        #expect(again.isError && again.content.hasPrefix("[job-1 had already ended]"), "\(again)")
    }

    @Test(arguments: [false, true])
    func `ask exiting stops every job, waiting or not`(atOnce: Bool) async throws {
        let (_, started) = try await started(#"sleep 300 & echo "child $!"; wait"#, printed: "child ")
        let child = try await #require(started).child()
        if atOnce { jobs.terminateAllNow() } else { await jobs.stopAll() }
        #expect(try await ProcessExit.observed(child))
    }

    @Test func `bash returns when a local port accepts connections, the command left running`() async throws {
        let port = try #require(Self.freePort())
        #expect(!PortWait.accepts(port), "nothing bound there yet: refused at once")
        let clock = TestClock()
        async let waiting = BashTool(jobs: jobs, clock: clock) { _ in }
            .run(input(#"{"command":"read hold","wait_for_port":\#(port),"timeout_seconds":20}"#), in: context)
        // The timeout and the first backoff are both asleep: the port has been tried once, and refused.
        try await clock.waitForSleepers(count: 2)
        let listener = try #require(Self.listen(on: port))
        defer { close(listener) }
        clock.advance(by: .milliseconds(50))
        let output = await waiting
        await jobs.stopAll()
        #expect(
            output
                == ToolOutput(
                    "[job-1 port \(port) accepts connections; still running]" + BashTool.endNoticeLine,
                    backgroundJob: "job-1"
                )
        )
    }

    /// A port the kernel handed out, released, and that refuses connections now. Anything else on the machine may take
    /// the number between the release and the check, so a port that is not refused is discarded and another tried.
    private static func freePort() -> Int? {
        for _ in 0 ..< 20 {
            guard let socket = listen(on: 0) else { return nil }
            var address = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) == 0 }
            }
            close(socket)
            let port = Int(UInt16(bigEndian: address.sin_port))
            if named, !PortWait.accepts(port) { return port }
        }
        return nil
    }

    /// A socket listening on `port` at 127.0.0.1.
    private static func listen(on port: Int) -> Int32? {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        var reuse: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = PortWait.loopback(port)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard bound, Darwin.listen(socket, 4) == 0 else {
            close(socket)
            return nil
        }
        return socket
    }

    @Test func `a job that is not there is named`() async {
        let tool = JobActionTool(jobs: jobs, clock: TestClock())
        for action in ["wait", "stop", "status", "input"] {
            let reply = await tool.run(input(#"{"job":"job-9","action":"\#(action)"}"#), in: context)
            #expect(reply == .error("No job named job-9."), "\(action)")
        }
    }
}
