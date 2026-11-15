internal import AemiJSON
internal import AemiJSONRPC
internal import AskCodemode
internal import Synchronization

/// The tool calls one script makes, as its keeper serves them: no more than a number at once, the others waiting their turn,
/// and a count of those begun and ended for whoever shows the script's progress.
final class CodemodeCalls: Sendable {
    /// The places its calls run in.
    let limiter: CodemodeLimiter
    private let call: CodemodeVM.Caller
    private let called: @Sendable (Int, Int) -> Void
    private let counts = Mutex((began: 0, ended: 0))

    init(limit: Int, call: @escaping CodemodeVM.Caller, called: @escaping @Sendable (Int, Int) -> Void) {
        limiter = CodemodeLimiter(limit)
        self.call = call
        self.called = called
    }

    /// The work that answers the child's request: a `call`, run when it has a place.
    func admit(_ request: JSONRPCRequest) -> JSONRPCConnection.RequestWork {
        guard request.method == CodemodeWire.call, let asked = CodemodeWire.call(from: request.params) else {
            return {
                .failure(
                    JSONRPCError(code: JSONRPCError.methodNotFound, message: "Method not found: \(request.method)")
                )
            }
        }
        return { await self.run(asked) }
    }

    private func run(_ asked: CodemodeWire.Call) async -> Result<JSONValue, JSONRPCError> {
        guard await limiter.acquire() else { return .failure(Self.refusal("The call was cancelled.")) }
        defer { limiter.release() }
        note { $0.began += 1 }
        defer { note { $0.ended += 1 } }
        switch await call(asked.tool, asked.arguments) {
            case .success(let text): return .success(CodemodeWire.answer(text))
            case .failure(let failure): return .failure(Self.refusal(failure.message))
        }
    }

    private func note(_ change: (inout (began: Int, ended: Int)) -> Void) {
        let now = counts.withLock { counts in
            change(&counts)
            return counts
        }
        called(now.began, now.ended)
    }

    /// A tool's failure as the child reads it: its message is what the script's `Error` says.
    private static func refusal(_ message: String) -> JSONRPCError { JSONRPCError(code: -32000, message: message) }
}
