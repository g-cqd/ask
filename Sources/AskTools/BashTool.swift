public import AskAI
public import AskAgentCore
internal import Foundation
internal import Subprocess
internal import Synchronization
internal import System

/// `bash`: runs a command in the working directory and returns its combined output and how it ended.
///
/// - The command runs in its own session, so teardown reaches every process it started and never ask's own
///   process group.
/// - Teardown on timeout or abort: SIGTERM to the group, a grace period, then SIGKILL to the group.
/// - Standard output and error are merged and read as a stream: a 512 KiB head and a 512 KiB tail are kept
///   around a counted omission, so memory stays bounded however much a command prints.
/// - Standard input is closed, so a command that waits for input ends instead of hanging.
public struct BashTool: Tool {
    struct Arguments: Decodable {
        let command: String
        let timeoutSeconds: Int?
        enum CodingKeys: String, CodingKey {
            case command
            case timeoutSeconds = "timeout_seconds"
        }
    }

    /// What tests observe, through an internal hook.
    enum Event: Sendable {
        case output([UInt8])
    }

    public static let defaultTimeout = 120
    public static let maximumTimeout = 600
    static let keptBytes = 512 << 10

    public let definition = ToolDefinition(
        name: "bash",
        description: """
            Run a bash command in the working directory. Returns combined stdout and stderr and the exit status. \
            Standard input is closed. timeout_seconds defaults to 120, at most 600.
            """,
        inputSchema: try! JSONObject(
            validating: Array(
                #"""
                {"type":"object","properties":{"command":{"type":"string"},\#
                "timeout_seconds":{"type":"integer","minimum":1,"maximum":600}},"required":["command"]}
                """#
                .utf8)))

    private let clock: any Clock<Duration>
    private let observe: @Sendable (Event) -> Void

    /// A bash tool timing out on the continuous clock.
    public init() { self.init(clock: ContinuousClock()) { _ in } }

    init(clock: any Clock<Duration>, observe: @escaping @Sendable (Event) -> Void) {
        self.clock = clock
        self.observe = observe
    }

    public func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        let arguments: Arguments
        switch self.arguments(Arguments.self, from: input) {
            case .success(let value): arguments = value
            case .failure(let output): return output
        }
        let timeout = Swift.min(Swift.max(1, arguments.timeoutSeconds ?? Self.defaultTimeout), Self.maximumTimeout)
        let collector = OutputCollector(keeping: Self.keptBytes)
        let ending = await withTaskGroup(of: Ending?.self) { group in
            group.addTask { await self.execute(arguments.command, in: context, into: collector) }
            group.addTask {
                // A cancelled sleep is the run finishing first, not a timeout.
                guard (try? await clock.sleep(for: .seconds(timeout))) != nil else { return nil }
                return .timedOut(seconds: timeout)
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .cancelled
        }
        return ending.output(collector.text)
    }

    private func execute(_ command: String, in context: ToolContext, into collector: OutputCollector) async -> Ending {
        var options = PlatformOptions()
        options.createSession = true
        options.teardownSequence = [
            .gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: .seconds(2)),
            .send(signal: .kill, toProcessGroup: true, allowedDurationToNextStep: .seconds(1))
        ]
        let configuration = Configuration(
            executable: .path("/bin/bash"), arguments: ["-c", command],
            workingDirectory: FilePath(context.workingDirectory), platformOptions: options)
        do {
            let result = try await Subprocess.run(
                configuration, input: .none, output: .sequence, error: .combinedWithOutput
            ) { execution in
                for try await buffer in execution.standardOutput {
                    let bytes = buffer.bytes.withUnsafeBytes { Array($0) }
                    collector.append(bytes)
                    observe(.output(bytes))
                }
            }
            if Task.isCancelled { return .cancelled }
            switch result.terminationStatus {
                case .exited(let code): return .exited(Int(code))
                case .signaled(let signal): return .signalled(Int(signal))
            }
        } catch {
            return Task.isCancelled ? .cancelled : .failedToStart(String(describing: error))
        }
    }

    /// How a command ended.
    private enum Ending: Sendable {
        case exited(Int)
        case signalled(Int)
        case timedOut(seconds: Int)
        case cancelled
        case failedToStart(String)

        func output(_ text: String) -> ToolOutput {
            let body = text.isEmpty ? "" : (text.hasSuffix("\n") ? text : text + "\n")
            switch self {
                case .exited(0): return ToolOutput(body + "[exit 0]")
                case .exited(let code): return .error(body + "[exit \(code)]")
                case .signalled(let signal): return .error(body + "[terminated by signal \(signal)]")
                case .timedOut(let seconds):
                    return .error(body + "[timed out after \(seconds) s; the command and its children were stopped]")
                case .cancelled: return .error(body + "[aborted; the command and its children were stopped]")
                case .failedToStart(let reason): return .error("bash could not start: \(reason)")
            }
        }
    }

    /// Keeps the first and the last `keeping` bytes of a stream, and counts what fell between.
    private final class OutputCollector: Sendable {
        private struct State {
            var head: [UInt8] = []
            var tail: [UInt8] = []
            var tailStart = 0
            var omitted = 0
        }

        private let keeping: Int
        private let state = Mutex(State())

        init(keeping: Int) { self.keeping = keeping }

        func append(_ bytes: [UInt8]) {
            state.withLock { state in
                var rest = bytes[...]
                if state.head.count < keeping {
                    let taken = rest.prefix(keeping - state.head.count)
                    state.head += taken
                    rest = rest.dropFirst(taken.count)
                }
                for byte in rest {
                    if state.tail.count < keeping {
                        state.tail.append(byte)
                    } else {
                        state.tail[state.tailStart] = byte
                        state.tailStart = (state.tailStart + 1) % keeping
                        state.omitted += 1
                    }
                }
            }
        }

        var text: String {
            state.withLock { state in
                let tail = Array(state.tail[state.tailStart...] + state.tail[..<state.tailStart])
                let head = String(decoding: state.head, as: UTF8.self)
                guard state.omitted > 0 else { return head + String(decoding: tail, as: UTF8.self) }
                return head + "\n[… \(state.omitted) bytes omitted …]\n" + String(decoding: tail, as: UTF8.self)
            }
        }
    }
}
