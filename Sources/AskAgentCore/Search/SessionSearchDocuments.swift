internal import AemiJSON
public import AemiSearch

/// What of a session line is searched (t209): a typed line, a reply's text, a tool call (its name and input), a tool's result, a
/// compaction's summary; each a document with the session, its project, the entry and its kind. Read with AemiJSON's lazy access,
/// so a line is never decoded whole.
public enum SessionSearchDocuments {
    /// The documents of one line of a plain session file.
    public static func documents(
        fromLine line: ArraySlice<UInt8>,
        session: String,
        project: String,
        time: Int64
    ) -> [SearchDocument] {
        let options = JSONParseOptions(recordsContainerSpans: true)
        guard let root = (try? AemiJSON.parse(Array(line), options: options))?.root, root["type"].string == "entry"
        else {
            return []
        }
        let payload = root["payload"]
        let entry = root["id"].string ?? ""
        func document(_ text: String, _ kind: String) -> SearchDocument {
            SearchDocument(
                text: text,
                fields: ["session": session, "project": project, "entry": entry, "kind": kind],
                time: time
            )
        }
        switch payload["kind"].string {
            case "user": return payload["text"].string.map { [document($0, "user")] } ?? []
            case "tool_result":
                return
                    (payload["content"].string
                    ?? payload["content"].withRawJSONBytes { String(decoding: $0, as: UTF8.self) })
                    .map { [document($0, "tool")] } ?? []
            case "compaction": return payload["summary"].string.map { [document($0, "summary")] } ?? []
            case "response":
                var found: [SearchDocument] = []
                payload["blocks"]
                    .forEachElement { block in
                        if block["type"].string == "text", let text = block["text"].string {
                            found.append(document(text, "reply"))
                        }
                        if block["type"].string == "tool_call", let name = block["name"].string {
                            let input = block["input"].withRawJSONBytes { String(decoding: $0, as: UTF8.self) } ?? ""
                            found.append(document(name + " " + input, "call"))
                        }
                    }
                return found
            default: return []
        }
    }
}
