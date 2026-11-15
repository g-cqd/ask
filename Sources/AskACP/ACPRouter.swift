internal import AemiJSON
internal import AemiJSONRPC
internal import Synchronization

/// What each of the client's requests means (ACP v1): the methods ask answers, and the two refusals around them. Nothing but
/// `initialize` is answered before `initialize` has been (Errors, "Requests before initialization"); after it, a method ask does
/// not have is not found.
final class ACPRouter: Sendable {
    private let agent: ACPImplementation
    private let initialized = Mutex(false)
    /// The sessions, when this server can make them; without, the session methods are not ask's.
    private let sessions: ACPSessions?
    /// Where updates are sent: the connection, which is made after this and so given once it exists.
    private let client = Mutex<JSONRPCConnection?>(nil)

    init(agent: ACPImplementation, sessions: ACPSession.Source?) {
        self.agent = agent
        self.sessions = sessions.map(ACPSessions.init)
    }

    /// Gives the connection updates are sent on.
    func attach(_ connection: JSONRPCConnection) { client.withLock { $0 = connection } }

    /// The answer to `request`.
    func answer(_ request: JSONRPCRequest) async -> Result<JSONValue, JSONRPCError> {
        if request.method == "initialize" { return initialize(request.params) }
        guard initialized.withLock({ $0 }) else { return .failure(.notInitialized(request.method)) }
        switch (request.method, sessions) {
            case ("session/new", let sessions?): return await sessions.new(request.params)
            case ("session/prompt", let sessions?): return await prompt(request.params, in: sessions)
            default: return .failure(.methodNotFound(request.method))
        }
    }

    /// `session/prompt`: the turn's updates go to the client as `session/update`, and the answer follows the last of them.
    private func prompt(_ params: JSON?, in sessions: ACPSessions) async -> Result<JSONValue, JSONRPCError> {
        let turns: ACPTurns
        switch sessions.turns(of: params) {
            case .success(let found): turns = found
            case .failure(let error): return .failure(error)
        }
        switch ACPPrompt.text(of: params) {
            case .failure(let error): return .failure(error)
            case .success(let text):
                return await turns.prompt(text) { await self.send($0) }
        }
    }

    /// Sends one `session/update` to the client.
    private func send(_ update: JSONValue) async {
        // try?: a client that has gone is not told; the turn goes on to its end and its session keeps what was said
        try? await client.withLock { $0 }?.notify("session/update", update)
    }

    /// `initialize`: the version is ask's whatever the client named, since a client that speaks another is to be told the latest
    /// ask supports and decides for itself. The capabilities say only what is built.
    private func initialize(_ params: JSON?) -> Result<JSONValue, JSONRPCError> {
        guard let params, (try? AemiJSON.JSONDecoder().decode(ACPInitializeParams.self, from: params)) != nil else {
            return .failure(.invalidParams("initialize needs protocolVersion, an integer"))
        }
        initialized.withLock { $0 = true }
        var info: OrderedDictionary<String, JSONValue> = ["name": .string(agent.name)]
        if let title = agent.title { info["title"] = .string(title) }
        info["version"] = .string(agent.version)
        return .success(
            [
                "protocolVersion": .int(Int64(ACPServer.protocolVersion)), "agentCapabilities": [:],
                "agentInfo": .object(info), "authMethods": []
            ]
        )
    }
}
