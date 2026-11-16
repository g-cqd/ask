internal import AemiJSON
internal import AemiJSONRPC
internal import Synchronization

/// The server's output, which also says when a request has been answered. What must reach the client after an answer and
/// never before it (the commands of a session, which the client learns of from that answer) is sent once the answer's line
/// has been written: the connection writes an answer from the task that made it, and tells nobody.
///
/// A line is read back only while something waits for an answer, so a turn's updates pass unread.
final class ACPOutput: JSONRPCSink {
    private struct Waiting {
        let id: JSONRPCID
        let then: @Sendable () async -> Void
    }

    private let base: any JSONRPCSink
    private let waiting = Mutex<[Waiting]>([])

    init(_ base: any JSONRPCSink) { self.base = base }

    /// Runs `then` once the answer to request `id` has been written, when it is a result; an error is followed by nothing.
    func after(_ id: JSONRPCID, _ then: @escaping @Sendable () async -> Void) {
        waiting.withLock { $0.append(Waiting(id: id, then: then)) }
    }

    func write(_ bytes: [UInt8]) async throws {
        try await base.write(bytes)
        guard waiting.withLock({ !$0.isEmpty }), let line = try? AemiJSON.parse(bytes).root, !line["method"].exists
        else { return }
        let answered: JSONRPCID? =
            if let number = line["id"].int { .number(Int64(number)) } else { line["id"].string.map { .string($0) } }
        let found = waiting.withLock { waiting -> Waiting? in
            guard let index = waiting.firstIndex(where: { $0.id == answered }) else { return nil }
            return waiting.remove(at: index)
        }
        if line["result"].exists { await found?.then() }
    }
}
