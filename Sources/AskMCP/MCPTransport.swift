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

    /// Ends the conversation: tells the server, waits a moment for it to leave, then makes it. Safe to call again.
    func close() async
}
