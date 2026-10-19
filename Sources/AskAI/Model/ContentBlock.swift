/// One block of a complete assistant response.
// @dl:accept -- the assembled response and the request are different directions with different cases (unrecognized; toolResult); roadmap 0026 revisits the block vocabulary
public enum ContentBlock: Sendable, Equatable {
    case text(String)
    /// Reasoning, with the signature that must accompany it when sent back.
    case thinking(text: String, signature: String)
    case redactedThinking(data: String)
    /// A tool call with its arguments, validated as one JSON object.
    case toolCall(id: String, name: String, input: JSONObject)
    /// A block type the decoder did not know, kept so the response is not silently shortened.
    case unrecognized(type: String)
}
