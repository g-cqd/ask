internal import AemiJSON
internal import AemiJSONRPC
internal import Synchronization

/// What each of the client's requests means (ACP v1): the methods ask answers, and the two refusals around them. Nothing but
/// `initialize` is answered before `initialize` has been (Errors, "Requests before initialization"); after it, a method ask does
/// not have is not found.
final class ACPRouter: Sendable {
    private let agent: ACPImplementation
    private let initialized = Mutex(false)
    /// What the client said it can show, in the `initialize` that was answered.
    private let capabilities = Mutex(ACPClientCapabilities())
    /// The sessions, when this server can make them; without, the session methods are not ask's.
    private let sessions: ACPSessions?
    /// Where updates are sent: the connection, which is made after this and so given once it exists.
    private let client = Mutex<JSONRPCConnection?>(nil)

    init(agent: ACPImplementation, sessions: ACPSessions?) {
        self.agent = agent
        self.sessions = sessions
    }

    /// Gives the connection updates are sent on.
    func attach(_ connection: JSONRPCConnection) { client.withLock { $0 = connection } }

    /// Admits `request` where the connection reads it, in the order the client wrote its requests, and returns the work that
    /// answers it. What must follow that order is decided here: whether `initialize` has been answered, and a prompt's place
    /// among its session's prompts and cancellations.
    func admit(_ request: JSONRPCRequest) -> JSONRPCConnection.RequestWork {
        if request.method == "initialize" {
            let answer = initialize(request.params)
            return { answer }
        }
        guard initialized.withLock({ $0 }) else { return { .failure(.notInitialized(request.method)) } }
        let params = request.params
        switch (request.method, sessions) {
            case ("session/new", let sessions?):
                let client = capabilities.withLock { $0 }
                return { await sessions.new(params, client: client) }
            case ("session/prompt", let sessions?): return prompt(params, in: sessions)
            case ("session/load", let sessions?) where sessions.canLoad:
                let client = asClient
                return { await sessions.load(params, client: client) }
            default: return { .failure(.methodNotFound(request.method)) }
        }
    }

    /// The client's input has ended: every turn that runs for it is stopped.
    func clientLeft() { sessions?.cancelAll() }

    /// What the client says without asking: `session/cancel`. Any other notification is ignored, as one nobody knows must be.
    func notified(_ notification: JSONRPCNotification) {
        guard notification.method == "session/cancel", let sessions,
            case .success(let turns) = sessions.turns(of: notification.params)
        else { return }
        turns.cancel()
    }

    /// `session/prompt`: the turn's updates go to the client as `session/update`, and the answer follows the last of them.
    private func prompt(_ params: JSON?, in sessions: ACPSessions) -> JSONRPCConnection.RequestWork {
        let turns: ACPTurns
        switch sessions.turns(of: params) {
            case .success(let found): turns = found
            case .failure(let error): return { .failure(error) }
        }
        switch ACPPrompt.text(of: params) {
            case .failure(let error): return { .failure(error) }
            case .success(let text):
                let (admitted, client) = (turns.admit(), asClient)
                return { await turns.prompt(text, admitted: admitted, client: client) }
        }
    }

    /// The client, as a turn or a replay reaches it.
    private var asClient: ACPClient {
        ACPClient(
            capabilities: capabilities.withLock { $0 },
            notify: send,
            requestPermission: requestPermission,
            elicit: elicit
        )
    }

    /// Sends one `session/update` to the client.
    @Sendable private func send(_ update: JSONValue) async {
        // try?: a client that has gone is not told; the turn goes on to its end and its session keeps what was said
        try? await client.withLock { $0 }?.notify("session/update", update)
    }

    /// Asks the client for a permission, for as long as its person takes to answer; nil when it gives no answer.
    @Sendable private func requestPermission(_ params: JSONValue) async -> JSON? {
        try? await client.withLock { $0 }?.request("session/request_permission", params, timeout: Self.patience)
    }

    /// Asks the client to show a form, for as long as its person takes to fill it; nil when it gives no answer.
    @Sendable private func elicit(_ params: JSONValue) async -> JSON? {
        try? await client.withLock { $0 }?.request("elicitation/create", params, timeout: Self.patience)
    }

    /// A person may leave a question open overnight; the connection's own two minutes would refuse the call for them.
    private static let patience: Duration = .seconds(365 * 24 * 3600)

    /// `initialize`: the version is ask's whatever the client named, since a client that speaks another is to be told the latest
    /// ask supports and decides for itself. The capabilities say only what is built.
    private func initialize(_ params: JSON?) -> Result<JSONValue, JSONRPCError> {
        guard let params, (try? AemiJSON.JSONDecoder().decode(ACPInitializeParams.self, from: params)) != nil else {
            return .failure(.invalidParams("initialize needs protocolVersion, an integer"))
        }
        initialized.withLock { $0 = true }
        capabilities.withLock { $0 = ACPClientCapabilities(initialize: params) }
        var info: OrderedDictionary<String, JSONValue> = ["name": .string(agent.name)]
        if let title = agent.title { info["title"] = .string(title) }
        info["version"] = .string(agent.version)
        return .success(
            [
                "protocolVersion": .int(Int64(ACPServer.protocolVersion)),
                // Only what is built: a saved session can be loaded when this server was given the means.
                "agentCapabilities": sessions?.canLoad == true ? ["loadSession": true] : [:],
                "agentInfo": .object(info), "authMethods": []
            ]
        )
    }
}
