import Synchronization

@testable import AskCodemode

/// The tools a test gives a script: each answers by what its name and arguments are, and every call is kept.
final class ScriptedTools: Sendable {
    private let made = Mutex<[String]>([])
    /// Released to let the calls of `held` answer.
    private let gate = Mutex<[CheckedContinuation<Void, Never>]>([])
    /// Told of each held call as it arrives, for a test to wait on without a clock; its wait ends when the test is cancelled.
    private let arrivals = AsyncStream<Void>.makeStream()

    /// What a script here may call, each with what it is for, in this order.
    private static let described: KeyValuePairs = [
        "read": "Read a file.", "fail": "Always fails.", "held": "Answers when the test lets it.",
        "mcp__dev-radius__search": "Search."
    ]
    static let offered = described.map { CodemodeCallable(name: $0.key, description: $0.value) }

    /// The calls made, as `name arguments`, in the order they were made.
    var calls: [String] { made.withLock { $0 } }

    /// Returns once a held call has arrived (or the test was cancelled).
    func heldArrived() async {
        for await _ in arrivals.stream { return }
    }

    /// Lets every held call answer.
    func release() {
        for waiter in gate.withLock({ waiting in
            defer { waiting = [] }
            return waiting
        }) { waiter.resume() }
    }

    func call(_ tool: String, _ arguments: String) async -> Result<String, CodemodeCallFailure> {
        made.withLock { $0.append("\(tool) \(arguments)") }
        switch tool {
            case "fail": return .failure(CodemodeCallFailure("no such file: \(arguments)"))
            case "held":
                await withCheckedContinuation { waiter in
                    gate.withLock { $0.append(waiter) }
                    arrivals.continuation.yield()
                }
                return .success("held \(arguments)")
            default: return .success("\(tool) \(arguments)")
        }
    }

    /// Runs `code` in a VM over these tools.
    func run(_ code: String) async -> CodemodeResult {
        await CodemodeVM.run(code, tools: Self.offered) { [self] in await call($0, $1) }
    }
}
