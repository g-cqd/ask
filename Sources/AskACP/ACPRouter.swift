internal import AemiJSON
internal import AemiJSONRPC
internal import Synchronization

/// What each of the client's requests means (ACP v1): the methods ask answers, and the two refusals around them. Nothing but
/// `initialize` is answered before `initialize` has been (Errors, "Requests before initialization"); after it, a method ask does
/// not have is not found.
final class ACPRouter: Sendable {
    private let agent: ACPImplementation
    private let initialized = Mutex(false)

    init(agent: ACPImplementation) { self.agent = agent }

    /// The answer to `request`.
    func answer(_ request: JSONRPCRequest) async -> Result<JSONValue, JSONRPCError> {
        if request.method == "initialize" { return initialize(request.params) }
        guard initialized.withLock({ $0 }) else { return .failure(.notInitialized(request.method)) }
        return .failure(.methodNotFound(request.method))
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
