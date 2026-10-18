internal import AemiJSON

/// One block of a message sent to the model.
public enum RequestBlock: Sendable, Equatable {
    case text(String)
    case thinking(text: String, signature: String)
    case redactedThinking(data: String)
    case toolCall(id: String, name: String, input: JSONObject)
    case toolResult(id: String, content: String, isError: Bool)
}
