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
    /// (`keep` bytes) at the last response whose size reached `trigger` and whose clearing freed enough, or after which a clearing
    /// shows in the sizes.
    ///
    /// The trigger is the current model's, and a clearing may have been made under a lower one, before a change of model or of
    /// `compactAt`. Measured (ADR-0155): 14 clearings at 408,945 tokens, then a model whose trigger was 463,200; no response had
    /// reached it, so nothing was cleared and a 240,000-token request became one of 3,330,961. A context only grows, so a response
    /// much smaller than the one before it, to the same model and as ask built it, is a clearing that was made: it is kept.
    static func reach(in context: [SessionEntry], at trigger: Int, keepingRecentBytes keep: Int) -> Int? {
        var reach: Int?
        var before: (index: Int, size: Int, model: String)?
        /// Moves the reach to the kept tail's cut at the response at `index`, when that clears at least `least` bytes more.
        func clear(at index: Int, freeing least: Int) {
            guard let cut = Compaction.cut(context[...index], keepingRecentBytes: keep), cut > (reach ?? 0) else {
                return
            }
            if freed(context[(reach ?? 0) ..< cut]) >= Swift.max(minimumBytes, least) { reach = cut }
        }
        for index in firstNew(in: context) ..< context.count {
            switch context[index].payload {
                case .destination: before = nil
                case .response(let response, let rewrite):
                    let size = size(response.usage)
                    if let earlier = before, rewrite == nil, earlier.model == response.model,
                        fell(from: earlier.size, to: size)
                    {
                        clear(at: earlier.index, freeing: earlier.size - size)
                    }
                    // A request hooks rewrote, or one with no count, says nothing of the context's size.
                    before = rewrite == nil && size > 0 ? (index, size, response.model) : nil
                    if size >= trigger { clear(at: index, freeing: trigger) }
                default: continue
            }
        }
        return reach
    }

    /// Whether a response of `size` tokens after one of `earlier` shows a clearing between them: smaller by an eighth, and by what the
    /// least clearing frees at eight bytes a token. A clearing frees a quarter of the context or more; a model that drops its earlier
    /// reasoning, or counts a little differently from one request to the next, frees less.
    private static func fell(from earlier: Int, to size: Int) -> Bool {
        earlier - size >= Swift.max(minimumBytes / 8, earlier / 8)
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
