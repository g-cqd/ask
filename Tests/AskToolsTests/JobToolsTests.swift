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
    private let jobs = JobTable()

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
        let reply = await JobInputTool(jobs: jobs, clock: TestClock())
            .run(input(#"{"job":"job-1","text":"hello\n"}"#), in: context)
        #expect(reply == ToolOutput("[job-1 ended]\ngot hello\n[exit 0]"))
        #expect(jobs.running.isEmpty)
    }

    @Test func `wait returns when the job prints the text, with what it printed`() async throws {
        _ = try await started("echo one; read go; echo READY; read stay", printed: "one")
        let clock = TestClock()
        async let waiting =
            WaitTool(jobs: jobs, clock: clock)
            .run(
                input(#"{"job":"job-1","output_contains":"READY"}"#), in: context)
        try await clock.waitForSleepers(count: 1)
        #expect(jobs.job("job-1")?.write(Array("go\n".utf8)) == true)
        let output = await waiting
        #expect(output == ToolOutput("READY\n[job-1 printed \"READY\"]\n[job-1 still running]"))
        _ = await JobStopTool(jobs: jobs).run(input(#"{"job":"job-1"}"#), in: context)
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
        _ = await JobStopTool(jobs: jobs).run(input(#"{"job":"job-1"}"#), in: context)
    }

    @Test func `a wait that times out says so, and is not an error`() async throws {
        _ = try await started("echo up; read never", printed: "up")
        let clock = TestClock()
        async let waiting =
            WaitTool(jobs: jobs, clock: clock)
            .run(
                input(#"{"job":"job-1","timeout_seconds":7}"#), in: context)
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(7))
        #expect(await waiting == ToolOutput("[nothing happened within 7 s]\n[job-1 still running]"))
        _ = await JobStopTool(jobs: jobs).run(input(#"{"job":"job-1"}"#), in: context)
    }

    @Test func `job_stop ends the job and every process it started`() async throws {
        let (_, started) = try await started(#"sleep 300 & echo "child $!"; wait"#, printed: "child ")
        let child = try await #require(started).child()
        let stopped = await JobStopTool(jobs: jobs).run(input(#"{"job":"job-1"}"#), in: context)
        #expect(!stopped.isError && stopped.content.hasPrefix("[job-1 stopped]"))
        #expect(try await ProcessExit.observed(child), "the backgrounded child must die with the group")
    }

    @Test(arguments: [false, true])
    func `ask exiting stops every job, waiting or not`(atOnce: Bool) async throws {
        let (_, started) = try await started(#"sleep 300 & echo "child $!"; wait"#, printed: "child ")
        let child = try await #require(started).child()
        if atOnce { jobs.terminateAllNow() } else { await jobs.stopAll() }
        #expect(try await ProcessExit.observed(child))
    }

    @Test func `wait returns when a file appears`() async throws {
        let clock = TestClock()
        async let waiting = WaitTool(jobs: jobs, clock: clock).run(input(#"{"file_exists":"out/flag"}"#), in: context)
        try await clock.waitForSleepers(count: 1)
        try FileManager.default.createDirectory(at: root.appending(path: "out"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appending(path: "out/flag").path, contents: Data())
        #expect(await waiting == ToolOutput("[out/flag exists]"))
    }

    @Test func `wait returns when a local port accepts connections`() async throws {
        let port = try #require(Self.freePort())
        #expect(!PortWait.accepts(port), "nothing bound there yet: refused at once")
        let clock = TestClock()
        async let waiting = WaitTool(jobs: jobs, clock: clock).run(input(#"{"port_open":\#(port)}"#), in: context)
        // The timeout and the first backoff are both asleep: the port has been tried once, and refused.
        try await clock.waitForSleepers(count: 2)
        let listener = try #require(Self.listen(on: port))
        defer { close(listener) }
        clock.advance(by: .milliseconds(50))
        #expect(await waiting == ToolOutput("[port \(port) accepts connections]"))
    }

    /// A port the kernel just handed out and that is free again.
    private static func freePort() -> Int? {
        guard let socket = listen(on: 0) else { return nil }
        defer { close(socket) }
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) == 0 }
        }
        return named ? Int(UInt16(bigEndian: address.sin_port)) : nil
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

    @Test func `bad requests name the problem`() async {
        let wait = WaitTool(jobs: jobs, clock: TestClock())
        #expect(await wait.run(input(#"{"job":"job-9"}"#), in: context) == .error("No job named job-9."))
        #expect(
            await wait.run(input("{}"), in: context) == .error("Give at least one of job, file_exists or port_open."))
        #expect(
            await wait.run(input(#"{"file_exists":"x","output_contains":"y"}"#), in: context)
                == .error("output_contains needs a job."))
        #expect(
            await JobStopTool(jobs: jobs).run(input(#"{"job":"nope"}"#), in: context) == .error("No job named nope."))
    }
}
