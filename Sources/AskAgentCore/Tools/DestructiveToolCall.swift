public import AskAI

/// A call to a server's tool that the server itself marks destructive, put to the user (ADR-0111).
///
/// Nothing here verifies the mark; a server can mislabel its tools either way. ask asks regardless, trading one keypress per tool per
/// session against a call that destroys something nobody saw coming.
public struct DestructiveToolCall: Sendable, Equatable {
    /// The server, as the configuration named it.
    public let server: String
    /// The tool, as the server named it.
    public let tool: String
    /// The call's whole input, so the question can show what it would do.
    public let input: JSONObject

    /// A call to `tool` of `server`.
    public init(server: String, tool: String, input: JSONObject) {
        self.server = server
        self.tool = tool
        self.input = input
    }

    /// What a session grant remembers: `server/tool`.
    public var grantKey: String { "\(server)/\(tool)" }
}

/// Answers a ``DestructiveToolCall``: true runs it. Only the user may answer true.
public typealias DestructiveApprover = @Sendable (DestructiveToolCall) async -> Bool
