internal import AemiJSON
internal import AemiJSONRPC
internal import Synchronization

/// The sessions active on a connection (ACP v1, Session Setup): made by `session/new`, named by the id it answered.
final class ACPSessions: Sendable {
    private let source: ACPSession.Source
    private let loader: ACPSession.Loader?
    private let active = Mutex<[String: ACPTurns]>([:])

    init(source: @escaping ACPSession.Source, loader: ACPSession.Loader? = nil) {
        self.source = source
        self.loader = loader
    }

    /// Cancels every session's turn, as `session/cancel` would each.
    func cancelAll() {
        for turns in active.withLock({ Array($0.values) }) { turns.cancel() }
    }

    /// Whether saved sessions can be loaded (`loadSession`).
    var canLoad: Bool { loader != nil }

    /// `session/new`: a session for the directory the client names, which must be an absolute path.
    func new(_ params: JSON?) async -> Result<JSONValue, JSONRPCError> {
        guard let cwd = params?["cwd"].string, cwd.hasPrefix("/") else {
            return .failure(.invalidParams("session/new needs cwd, an absolute path"))
        }
        do {
            let session = try await source(cwd)
            active.withLock { $0[session.id] = ACPTurns(session: session) }
            return .success(["sessionId": .string(session.id)])
        } catch {
            return .failure(
                JSONRPCError(code: JSONRPCError.internalError, message: "The session could not be made: \(error)")
            )
        }
    }

    /// `session/load`: the saved session the client names, replayed to it as updates before the answer, then active.
    func load(_ params: JSON?, client: ACPClient) async -> Result<JSONValue, JSONRPCError> {
        guard let id = params?["sessionId"].string, let cwd = params?["cwd"].string, cwd.hasPrefix("/") else {
            return .failure(.invalidParams("session/load needs sessionId, and cwd, an absolute path"))
        }
        // Its file has one writer, which is the conversation that already serves it here.
        guard active.withLock({ $0[id] }) == nil else {
            return .failure(.invalidParams("session \(id) is already active on this connection"))
        }
        let loaded: ACPSession.Loaded?
        do { loaded = try await loader?(id, cwd) } catch {
            return .failure(
                JSONRPCError(code: JSONRPCError.internalError, message: "The session could not be loaded: \(error)")
            )
        }
        guard let loaded else { return .failure(.unknownSession(id)) }
        let turns = ACPTurns(session: loaded.session)
        var reader = ACPTurnReader(session: loaded.session, client: client)
        for update in loaded.history.flatMap(\.flattened) { await reader.replay(update, in: turns) }
        active.withLock { $0[id] = turns }
        return .success([:])
    }

    /// The turns of session `id`, or the error an unknown session is answered with (Errors, "Unknown sessions").
    func turns(of params: JSON?) -> Result<ACPTurns, JSONRPCError> {
        guard let id = params?["sessionId"].string else { return .failure(.invalidParams("sessionId is missing")) }
        guard let turns = active.withLock({ $0[id] }) else { return .failure(.unknownSession(id)) }
        return .success(turns)
    }
}
