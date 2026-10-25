/// Why a request to a server did not produce a result.
public enum MCPError: Error, Sendable, Equatable {
    /// The server named a protocol version this client does not speak. The connection is closed.
    case unsupportedVersion(String)
    /// The server answered with a JSON-RPC error: its code and its words.
    case rpc(code: Int, message: String)
    /// The server answered with something that is not the answer to that request.
    case malformedResponse(String)
    /// The server did not answer in time. It has been told the request is abandoned.
    case timedOut(method: String)
    /// The caller gave up. The server has been told.
    case cancelled
    /// The server is gone, or the connection was closed.
    case disconnected
    /// A request was made before ``MCPConnection/start()`` finished.
    case notStarted
    /// ``MCPConnection/start()`` was called again.
    case alreadyStarted
    /// The server's address may not be used, and why (never the address itself, which can carry a password).
    case refusedEndpoint(String)
    /// A listing never ended: the server kept offering another page.
    case tooManyPages
}
