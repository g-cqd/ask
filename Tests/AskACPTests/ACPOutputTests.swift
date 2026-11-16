import AemiJSONRPC
import Synchronization
import Testing

@testable import AskACP

/// What follows an answer is written after it: a client learns of a session from the answer that made it.
@Suite("What is to follow an answer is written once that answer has been", .timeLimit(.minutes(1)))
struct ACPOutputTests {
    /// What was written, and what ran, in order.
    private final class Lines: JSONRPCSink {
        private let lines = Mutex<[String]>([])
        var all: [String] { lines.withLock { $0 } }
        func note(_ line: String) { lines.withLock { $0.append(line) } }
        func write(_ bytes: [UInt8]) async throws { note(String(decoding: bytes, as: UTF8.self)) }
    }

    private static let update = #"{"jsonrpc":"2.0","method":"session/update","params":{"id":2}}"# + "\n"
    private static let asking = #"{"jsonrpc":"2.0","id":2,"method":"session/request_permission"}"# + "\n"
    private static let first = #"{"jsonrpc":"2.0","id":1,"result":{}}"# + "\n"
    private static let second = #"{"jsonrpc":"2.0","id":2,"result":{}}"# + "\n"
    private static let named = #"{"jsonrpc":"2.0","id":"two","result":{}}"# + "\n"
    private static let refused = #"{"jsonrpc":"2.0","id":2,"error":{"code":-32603,"message":"no"}}"# + "\n"

    @Test func `it runs after the answer to its request, and after no other line`() async throws {
        let base = Lines()
        let output = ACPOutput(base)
        output.after(.number(2)) { base.note("followed") }
        // An update, a request of the server's own with the same id, the answer to another request, an id of another kind.
        for line in [Self.update, Self.asking, Self.first, Self.named] { try await output.write(Array(line.utf8)) }
        #expect(base.all == [Self.update, Self.asking, Self.first, Self.named])
        try await output.write(Array(Self.second.utf8))
        try await output.write(Array(Self.second.utf8))
        #expect(base.all.suffix(3) == [Self.second, "followed", Self.second], "once, and after the line")
    }

    @Test func `an answer whose id is a string is followed too`() async throws {
        let base = Lines()
        let output = ACPOutput(base)
        output.after(.string("two")) { base.note("followed") }
        try await output.write(Array(Self.named.utf8))
        #expect(base.all == [Self.named, "followed"])
    }

    @Test func `an error is followed by nothing, then or later`() async throws {
        let base = Lines()
        let output = ACPOutput(base)
        output.after(.number(2)) { base.note("followed") }
        try await output.write(Array(Self.refused.utf8))
        try await output.write(Array(Self.second.utf8))
        #expect(base.all == [Self.refused, Self.second])
    }
}
