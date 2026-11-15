package import AemiJSONRPC

/// An ACP agent on one connection (ADR-0153): JSON-RPC 2.0, a message a line, both ways.
///
/// The wire is AemiJSONRPC's, in the server's role: each of the client's requests is admitted in the order it arrived and
/// answered by work in a task of its own, so a long one (a prompt's turn) never holds the reader; notifications are delivered in
/// that same order; and a line that is not a message is answered with its error. This type gives it the output to write to and
/// the bytes to read; ``ACPRouter`` says what each method means.
package final class ACPServer: Sendable {
    /// The protocol's major version this server speaks, and so the one every `initialize` is answered with.
    package static let protocolVersion = 1

    private let connection: JSONRPCConnection

    /// A server that writes to `output` and says it is `agent`. With `sessions` it serves them (`session/new`, `session/prompt`),
    /// and with `load` saved ones too (`session/load`); without, it answers `initialize` and has no session methods.
    package init(
        output: any JSONRPCSink,
        agent: ACPImplementation,
        sessions: ACPSession.Source? = nil,
        load: ACPSession.Loader? = nil
    ) {
        let router = ACPRouter(agent: agent, sessions: sessions.map { ACPSessions(source: $0, loader: load) })
        connection = JSONRPCConnection(
            serving: output,
            framing: .lines,
            admit: { router.admit($0) },
            onNotification: { router.notified($0) }
        )
        router.attach(connection)
    }

    /// Serves the client whose bytes are `chunks` until they end, and every request read from them has been answered.
    package func run(reading chunks: some AsyncSequence<[UInt8], any Error>) async {
        await connection.run(reading: chunks)
    }
}
