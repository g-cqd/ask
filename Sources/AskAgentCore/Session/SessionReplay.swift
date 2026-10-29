internal import AskAI

/// A recorded session as the events that produced it, so a resumed conversation is shown by the same code that
/// showed it live.
///
/// A tool call is replayed where its result was recorded, started and finished together, as a live run shows it.
/// A call the run never answered finishes as interrupted, with the result the next request will carry for it.
public enum SessionReplay {
    /// One step: a prompt the user wrote, or something the loop reported.
    public enum Step: Sendable, Equatable {
        case prompt(String)
        case event(AgentEvent)
    }

    /// The steps for `entries`, in order: a tree's active branch, root first.
    public static func steps(_ entries: [SessionEntry]) -> [Step] {
        var steps: [Step] = []
        var pending: [(id: String, name: String, input: JSONObject)] = []
        func interruptPending() {
            for call in pending {
                steps.append(.event(.toolStarted(id: call.id, name: call.name, input: call.input)))
                let output = ToolOutput(RequestContext.interruptedResult, isError: true)
                steps.append(.event(.toolFinished(id: call.id, name: call.name, output: output)))
            }
            pending.removeAll()
        }
        for entry in entries {
            if case .destination = entry.payload { continue }
            if case .toolResult(let id, let content, let isError, _) = entry.payload,
                let index = pending.firstIndex(where: { $0.id == id })
            {
                let call = pending.remove(at: index)
                steps.append(.event(.toolStarted(id: id, name: call.name, input: call.input)))
                let output = ToolOutput(content, isError: isError)
                steps.append(.event(.toolFinished(id: id, name: call.name, output: output)))
                continue
            }
            interruptPending()
            steps += replayed(entry.payload, calls: &pending)
        }
        interruptPending()
        return steps
    }

    private static func replayed(
        _ payload: SessionPayload, calls: inout [(id: String, name: String, input: JSONObject)]
    ) -> [Step] {
        switch payload {
            case .destination: return []
            case .user(let text) where text == AgentLoop.continuationPrompt: return [.event(.continuedAtOutputLimit)]
            case .user(let text) where text == AgentLoop.reconnectionPrompt: return [.event(.continuedAfterDrop)]
            case .user(let text): return [.prompt(SkillInvocation.shown(text))]
            case .assistant(let text): return [.event(.model(.textDelta(index: 0, text)))]
            case .compaction(let summary, _): return [.event(.compacted(summary: summary, usage: TokenUsage()))]
            case .toolResult: return []  // Its call is not in context: the request drops it too.
            case .response(let response):
                var steps: [Step] = []
                for (index, block) in response.blocks.enumerated() {
                    switch block {
                        case .text(let text): steps.append(.event(.model(.textDelta(index: index, text))))
                        case .thinking(let text, _): steps.append(.event(.model(.thinkingDelta(index: index, text))))
                        case .toolCall(let id, let name, let input): calls.append((id, name, input))
                        default: break
                    }
                }
                return steps + [.event(.responded(response))]
        }
    }
}
