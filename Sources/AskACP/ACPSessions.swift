internal import AemiJSON
internal import AemiJSONRPC
internal import Synchronization

/// The sessions active on a connection (ACP v1, Session Setup): made by `session/new`, named by the id it answered.
final class ACPSessions: Sendable {
    private let source: ACPSession.Source
    private let active = Mutex<[String: ACPTurns]>([:])

    init(source: @escaping ACPSession.Source) { self.source = source }

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

    /// The turns of session `id`, or the error an unknown session is answered with (Errors, "Unknown sessions").
    func turns(of params: JSON?) -> Result<ACPTurns, JSONRPCError> {
        guard let id = params?["sessionId"].string else { return .failure(.invalidParams("sessionId is missing")) }
        guard let turns = active.withLock({ $0[id] }) else { return .failure(.unknownSession(id)) }
        return .success(turns)
    }
}
