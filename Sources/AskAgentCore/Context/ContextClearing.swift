internal import AskAI

/// Light compaction (roadmap 0032, the owner's choice of 2026-11-12). Once the context reaches a trigger below the compaction
/// threshold, a tool's output and the reasoning before the kept tail leave the request: an output becomes one line saying so, the
/// reasoning is not sent. Compaction then comes later; the session keeps everything, and the summary is still made from all of it.
///
/// Nothing is recorded. How far the clearing reaches is worked out from the context alone, a walk over the responses' recorded sizes,
/// so every request after a clearing has the same prefix (the provider's cache breaks once, at the clearing) and a resumed session
/// sends what it sent. A clearing is made only when it frees as many bytes as the trigger has tokens (about a quarter of the context),
/// and at least ``minimumBytes``: each one makes the provider cache the prefix again, so a few large ones are cheaper than many small.
enum ContextClearing {
    /// The least a clearing frees, whatever the trigger.
    static let minimumBytes = 64 * 1024
    /// The share of the compaction threshold that triggers a clearing.
    static let share = 0.6

    /// What stands in for an output that was cleared.
    static func stub(for content: String) -> String {
        let lines = content.utf8.reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
        return "[ask left this output out to keep the context small: \(lines) lines, \(content.utf8.count) bytes. "
            + "Run the tool again if it is needed.]"
    }

    /// The index in `context` before which output and reasoning are cleared, or nil when nothing is: the cut of the kept tail
    /// (`keep` bytes) at the last response whose size reached `trigger` and whose clearing freed enough.
    static func reach(in context: [SessionEntry], at trigger: Int, keepingRecentBytes keep: Int) -> Int? {
        var reach: Int?
        for index in firstNew(in: context) ..< context.count {
            guard case .response(let response, _) = context[index].payload, size(response.usage) >= trigger,
                let cut = Compaction.cut(context[...index], keepingRecentBytes: keep), cut > (reach ?? 0)
            else { continue }
            if freed(context[(reach ?? 0) ..< cut]) >= Swift.max(minimumBytes, trigger) { reach = cut }
        }
        return reach
    }

    /// `payload` as a request before the reach sends it.
    static func cleared(_ payload: SessionPayload) -> SessionPayload {
        switch payload {
            case .toolResult(let id, let content, let isError, let images, let facts):
                let stub = stub(for: content)
                guard content.utf8.count > stub.utf8.count || !images.isEmpty else { return payload }
                return .toolResult(callID: id, content: stub, isError: isError, images: [], facts: facts)
            case .response(var response, let rewrite):
                response.blocks.removeAll(where: isReasoning)
                return .response(response, rewrite: rewrite)
            default:
                return payload
        }
    }

    /// Where the entries written since the last compaction start: the kept ones before them report sizes from before it.
    private static func firstNew(in context: [SessionEntry]) -> Int {
        guard let first = context.first, case .compaction = first.payload else { return 0 }
        return context.firstIndex { $0.parentID == first.id } ?? context.count
    }

    private static func size(_ usage: TokenUsage) -> Int {
        (usage.input ?? 0) + (usage.cacheRead ?? 0) + (usage.cacheCreation ?? 0) + (usage.output ?? 0)
    }

    /// The bytes a clearing of `entries` frees: their outputs and their reasoning.
    private static func freed(_ entries: ArraySlice<SessionEntry>) -> Int {
        entries.reduce(0) { total, entry in
            switch entry.payload {
                case .toolResult(_, let content, _, _, _): total + content.utf8.count
                case .response(let response, _):
                    total + response.blocks.filter(isReasoning).reduce(0) { $0 + reasoningBytes($1) }
                default: total
            }
        }
    }

    private static func isReasoning(_ block: ContentBlock) -> Bool {
        switch block {
            case .thinking, .redactedThinking: true
            default: false
        }
    }

    private static func reasoningBytes(_ block: ContentBlock) -> Int {
        switch block {
            case .thinking(let text, let signature): text.utf8.count + signature.utf8.count
            case .redactedThinking(let data): data.utf8.count
            default: 0
        }
    }
}
