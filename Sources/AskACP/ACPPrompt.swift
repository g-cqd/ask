internal import AemiJSON
internal import AemiJSONRPC

/// The text of a `session/prompt` (ACP v1, Content): what its content blocks say, in the order the client put them.
///
/// Text and resource links are what every agent must take. A link is written as its address, a file's as its path, where the
/// client put it in the sentence: ask's tools read it when the model asks. The blocks an agent takes only when it advertised them
/// (images, audio, embedded resources) are refused, since ask advertises none yet.
enum ACPPrompt {
    static func text(of params: JSON?) -> Result<String, JSONRPCError> {
        guard let blocks = params?["prompt"].array else {
            return .failure(.invalidParams("prompt is missing, or not a list"))
        }
        var text = ""
        for block in blocks {
            switch block["type"].string {
                case "text":
                    guard let piece = block["text"].string else {
                        return .failure(.invalidParams("a text block has no text"))
                    }
                    text += piece
                case "resource_link":
                    guard let uri = block["uri"].string else {
                        return .failure(.invalidParams("a resource_link block has no uri"))
                    }
                    text += uri.hasPrefix("file://") ? String(uri.dropFirst("file://".count)) : uri
                case let other:
                    return .failure(
                        .invalidParams("ask takes text and resource_link blocks, not \(other ?? "one with no type")")
                    )
            }
        }
        guard !text.isEmpty else { return .failure(.invalidParams("the prompt says nothing")) }
        return .success(text)
    }
}
