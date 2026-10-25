/// How messages get to and from an MCP server: a pipe to a child process, or HTTP (ADR-0096).
///
/// A transport moves whole JSON-RPC messages and knows nothing of what is in them. The connection above it owns ids, timeouts,
/// cancellation and meaning, so a new transport is only framing and a lifetime.
public protocol MCPTransport: Sendable {
    /// Every message the server sends, one complete JSON-RPC message each, exactly as it was framed. The stream ends when the server
    /// does, whether it exited, hung up or was closed from this side.
    var incoming: AsyncStream<[UInt8]> { get }

    /// Sends one complete JSON-RPC message.
    /// - Parameter message: the message, without framing.
    /// - Throws: when it cannot be delivered, as to a process that has died.
    func send(_ message: [UInt8]) async throws

    /// Told once, after the handshake, which protocol version was agreed. A pipe has no use for it; HTTP must name it in every request.
    /// - Parameter protocolVersion: the version the server answered and this client accepted.
    func negotiated(protocolVersion: String)

    /// What the transport knows about why the conversation ended or never began, in a few words: a program that could not be launched, the
    /// last thing a server wrote to its standard error. Nil when it has nothing to add.
    var diagnostic: String? { get }

    /// Ends the conversation: tells the server, waits a moment for it to leave, then makes it. Safe to call again.
    func close() async
}

extension MCPTransport {
    /// Most transports have nothing to do with the version.
    public func negotiated(protocolVersion: String) {}

    /// Most transports have nothing to add.
    public var diagnostic: String? { nil }
}
