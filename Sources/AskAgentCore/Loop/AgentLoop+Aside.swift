public import AskAI

/// `/btw` (roadmap 0194, the owner's choice of 2026-11-03): a question beside the conversation, answered by one request over the
/// conversation so far, with no tools, and kept out of the conversation.
extension AgentLoop {
    /// What follows the person's question in an aside's request.
    public static let asideInstruction =
        "[ask] This is an aside from the person, answered beside the conversation: reply in text, briefly. Do not call any tool; "
        + "this reply is not added to the conversation, and the work under way goes on without it."

    /// What a thread is asked when it merges into its parent (roadmap 0195): the summary its parent receives, like a compaction's.
    public static let mergeInstruction = """
        [ask] This thread is merging back into the conversation it was forked from, which receives your summary in place of \
        everything this thread did. Write it now: what you were asked; what you found and decided, and why; the files you changed, \
        with paths, and the commands that mattered, with what they showed; what is unfinished, uncertain or needs the person. Fold \
        in what any threads merged into this one reported. Be concise: a few short paragraphs or bullets. Do not call any tool. \
        Reply with the summary only.
        """

    /// The answer to `question` over `tree`'s context (none before a session starts), and what the request spent.
    ///
    /// The request carries the tools' definitions, as every request of the conversation does: a provider refuses a history of tool
    /// calls without them, and the same prefix reads from its cache. Only the reply's text is the answer; a tool the model calls anyway
    /// is not run.
    /// - Parameters:
    ///   - question: what is asked; empty when the instruction is the whole question, as a merge's is.
    ///   - tree: the conversation it is asked over; nil before a session starts.
    ///   - instruction: what follows the question; a thread's merge (roadmap 0195) asks for its summary instead.
    /// - Returns: the reply's text, and what the request spent.
    /// - Throws: ``AgentError`` when the request fails.
    public func aside(
        _ question: String,
        over tree: SessionTree?,
        instruction: String = asideInstruction
    ) async throws(AgentError) -> (answer: String, usage: TokenUsage) {
        var request = request(for: tree?.context() ?? []) { _ in }
        let asked = RequestBlock.text(question.isEmpty ? instruction : question + "\n\n" + instruction)
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
