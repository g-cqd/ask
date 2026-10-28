public import AskAI

/// The model messages for a context, always a valid request, with every repair it took named.
///
/// The rules come from the provider protocols, not from preference:
/// - consecutive entries of one role merge into one message, so a turn's tool results share a user message;
/// - tool results lead the message that carries them;
/// - every tool call is answered in the next message. A call with no recorded result, because the run was
///   interrupted, gets an explicit error result, and a result whose call is not in context (compacted away,
///   or damaged) is dropped;
/// - blocks that cannot be sent back are dropped, and a response left empty produces no message.
public struct RequestContext: Sendable, Equatable {
    /// One change made so the context is a valid request.
    public enum Repair: Sendable, Equatable {
        case interruptedToolCall(id: String)
        case orphanedToolResult(id: String)
        case droppedBlock(type: String)
    }

    /// The text that stands in for a result the run never recorded.
    public static let interruptedResult = "No result was recorded: the run was interrupted before this tool finished."
    /// What precedes a compaction's summary.
    public static let summaryPrefix = "Summary of the conversation so far:\n"

    public private(set) var messages: [ModelMessage] = []
    public private(set) var repairs: [Repair] = []
    /// Calls the last assistant message made that no result has answered yet.
    private var unanswered: [String] = []

    /// The messages for `context`, root first, as ``SessionTree/context()`` returns it.
    public init(_ context: [SessionEntry]) {
        for entry in context { add(entry.payload) }
        answerOutstanding()
    }

    private mutating func add(_ payload: SessionPayload) {
        switch payload {
            case .destination: break
            case .user(let text): addUser(.text(text))
            case .compaction(let summary, _): addUser(.text(Self.summaryPrefix + summary))
            case .assistant(let text): addAssistant([.text(text)])
            case .response(let response): addAssistant(response.blocks.compactMap { replayable($0) })
            case .toolResult(let id, let content, let isError, let images):
                guard let index = unanswered.firstIndex(of: id) else {
                    repairs.append(.orphanedToolResult(id: id))
                    return
                }
                unanswered.remove(at: index)
                append(.toolResult(id: id, content: content, isError: isError, images: images), role: .user)
        }
    }

    private mutating func addUser(_ block: RequestBlock) {
        answerOutstanding()
        append(block, role: .user)
    }

    private mutating func addAssistant(_ blocks: [RequestBlock]) {
        guard !blocks.isEmpty else { return }
        answerOutstanding()
        for block in blocks { append(block, role: .assistant) }
        unanswered = blocks.compactMap {
            if case .toolCall(let id, _, _) = $0 { return id }
            return nil
        }
    }

    /// Answers calls still open before anything else is added: results must lead the next user message.
    private mutating func answerOutstanding() {
        for id in unanswered {
            repairs.append(.interruptedToolCall(id: id))
            append(.toolResult(id: id, content: Self.interruptedResult, isError: true), role: .user)
        }
        unanswered.removeAll()
    }

    private mutating func append(_ block: RequestBlock, role: ModelMessage.Role) {
        if messages.last?.role == role {
            messages[messages.count - 1].blocks.append(block)
        } else {
            messages.append(ModelMessage(role: role, blocks: [block]))
        }
    }

    private mutating func replayable(_ block: ContentBlock) -> RequestBlock? {
        switch block {
            case .text(let text): return .text(text)
            case .thinking(let text, let signature): return .thinking(text: text, signature: signature)
            case .redactedThinking(let data): return .redactedThinking(data: data)
            case .toolCall(let id, let name, let input): return .toolCall(id: id, name: name, input: input)
            case .unrecognized(let type):
                repairs.append(.droppedBlock(type: type))
                return nil
        }
    }
}
