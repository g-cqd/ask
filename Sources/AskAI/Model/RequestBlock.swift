internal import AemiJSON

/// One block of a message sent to the model.
public enum RequestBlock: Sendable, Equatable {
    case text(String)
    case thinking(text: String, signature: String)
    case redactedThinking(data: String)
    case toolCall(id: String, name: String, input: JSONObject)
    /// A tool's result: its text, and any images it returned (roadmap 0084).
    case toolResult(id: String, content: String, isError: Bool, images: [ImagePart] = [])
    /// A picture the person pasted into their message (roadmap 0224).
    case image(ImagePart)
}
