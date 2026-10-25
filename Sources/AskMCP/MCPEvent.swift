/// Something a server did that is not the answer to a request.
public enum MCPEvent: Sendable, Equatable {
    /// The server's tools changed; list them again.
    case toolsChanged
    /// The server logged something, as its `notifications/message`: the level it gave, and the text (a string as it was, anything else
    /// as its JSON).
    case log(level: String?, text: String)
    /// A line that was not a message: what it was, in a few words. The connection goes on.
    case malformed(String)
    /// The connection ended, from either side. The last event.
    case closed
}
