internal import AemiJSON
public import AemiSearch
internal import AskAI

/// What of a session is searched (t209): a typed line, a reply's text, a tool call (its name and input), a tool's result, a
/// compaction's summary; each a document with its entry and kind. Read from the session's entries, so every format (JSONL, framed,
/// compressed, encrypted) is searched alike.
public enum SessionSearchDocuments {
    /// The documents of one entry.
    public static func documents(of entry: SessionEntry, time: Int64) -> [SearchDocument] {
        func document(_ text: String, _ kind: String) -> SearchDocument {
            SearchDocument(text: text, fields: ["entry": entry.id.description, "kind": kind], time: time)
        }
        switch entry.payload {
            case .user(let text, _): return text.isEmpty ? [] : [document(text, "user")]
            case .assistant(let text): return text.isEmpty ? [] : [document(text, "reply")]
            case .toolResult(_, let content, _, _, _): return content.isEmpty ? [] : [document(content, "tool")]
            case .compaction(let summary, _): return [document(summary, "summary")]
            case .response(let response, _):
                return response.blocks.compactMap { block in
                    switch block {
                        case .text(let text) where !text.isEmpty: document(text, "reply")
                        case .toolCall(_, let name, let input):
                            document(name + " " + String(decoding: input.bytes, as: UTF8.self), "call")
                        default: nil
                    }
                }
            default: return []
        }
    }
}
