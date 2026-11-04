public import AskAI

/// `/btw` (roadmap 0194, the owner's choice of 2026-11-03): a question beside the conversation, answered by one request over the
/// conversation so far, with no tools, and kept out of the conversation.
extension AgentLoop {
    /// What follows the person's question in an aside's request.
    public static let asideInstruction =
        "[ask] This is an aside from the person, answered beside the conversation: reply in text, briefly. Do not call any tool; "
        + "this reply is not added to the conversation, and the work under way goes on without it."

    /// The answer to `question` over `tree`'s context (none before a session starts), and what the request spent.
    ///
    /// The request carries the tools' definitions, as every request of the conversation does: a provider refuses a history of tool
    /// calls without them, and the same prefix reads from its cache. Only the reply's text is the answer; a tool the model calls anyway
    /// is not run.
    /// - Throws: ``AgentError`` when the request fails.
    public func aside(_ question: String, over tree: SessionTree?) async throws(AgentError) -> (
        answer: String, usage: TokenUsage
    ) {
        var request = request(for: tree?.context() ?? []) { _ in }
        let asked = RequestBlock.text(question + "\n\n" + Self.asideInstruction)
        if request.messages.last?.role == .user {
            request.messages[request.messages.count - 1].blocks.append(asked)
        } else {
            request.messages.append(ModelMessage(role: .user, blocks: [asked]))
        }
        let response = try await stream(request) { _ in }
        let text = response.blocks.compactMap { block -> String? in
            if case .text(let text) = block { text } else { nil }
        }
        return (text.joined(separator: "\n"), response.usage)
    }
}
