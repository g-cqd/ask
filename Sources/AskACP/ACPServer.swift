package import AemiJSONRPC

/// An ACP agent on one connection (ADR-0153): JSON-RPC 2.0, a message a line, both ways.
///
/// The wire is AemiJSONRPC's: requests matched to answers, each of the client's requests answered in a task of its own so a long
/// one (a prompt's turn) never holds the reader, notifications delivered in order. This type gives it the output to write to and
/// the bytes to read; ``ACPRouter`` says what each method means.
package final class ACPServer: Sendable {
    /// The protocol's major version this server speaks, and so the one every `initialize` is answered with.
    package static let protocolVersion = 1

    private let connection: JSONRPCConnection

    /// A server that writes to `output` and says it is `agent`. With `sessions` it serves them (`session/new`, `session/prompt`);
    /// without, it answers `initialize` and has no session methods.
    package init(output: any JSONRPCSink, agent: ACPImplementation, sessions: ACPSession.Source? = nil) {
        let router = ACPRouter(agent: agent, sessions: sessions)
        connection = JSONRPCConnection(sink: output, framing: .lines) { await router.answer($0) }
        router.attach(connection)
    }

    /// Serves the client whose bytes are `chunks` until they end, and every request read from them has been answered.
    package func run(reading chunks: some AsyncSequence<[UInt8], any Error>) async {
        await connection.run(reading: chunks)
    }
}
