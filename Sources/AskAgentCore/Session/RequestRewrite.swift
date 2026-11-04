public import AskAI

/// That hooks rewrote the request a response answered (roadmap 0192, ADR-0143): which hooks, and how large the request was before and
/// after, in bytes of text. The session keeps the conversation as it was; this says the provider saw something else, so a resume does
/// not take the rewrite for the conversation.
public struct RequestRewrite: Sendable, Equatable, Codable {
    public var hooks: [String]
    public var bytesBefore: Int
    public var bytesAfter: Int

    public init(hooks: [String], bytesBefore: Int, bytesAfter: Int) {
        self.hooks = hooks
        self.bytesBefore = bytesBefore
        self.bytesAfter = bytesAfter
    }

    /// The bytes of text `request` carries: its system prompt, and its messages' text, thinking, tool inputs and results. Pictures
    /// count for nothing: a rewrite that drops one is still said, by its hooks, if not by its size.
    public static func textBytes(of request: ModelRequest) -> Int {
        request.systemPrompt.reduce(0) { $0 + $1.utf8.count }
            + request.messages.reduce(0) { total, message in
                total
                    + message.blocks.reduce(0) { sum, block in
                        sum + bytes(of: block)
                    }
            }
    }

    private static func bytes(of block: RequestBlock) -> Int {
        switch block {
            case .text(let text): text.utf8.count
            case .thinking(let text, _): text.utf8.count
            case .redactedThinking(let data): data.utf8.count
            case .toolCall(_, let name, let input): name.utf8.count + input.bytes.count
            case .toolResult(_, let content, _, _): content.utf8.count
        }
    }
}
