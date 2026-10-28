internal import AemiJSON

/// One message from a server, sorted into what it is.
enum MCPEnvelope {
    /// The answer to a request this client made: its `result`, parsed once with the whole message and handed on as it is (roadmap 0114).
    case response(id: Int, outcome: Result<JSON, MCPError>)
    /// A request from the server, with its id as written, so the answer can echo it.
    case request(id: [UInt8], method: String, params: [UInt8]?)
    /// A notice that wants no answer.
    case notification(method: String, params: [UInt8]?)
    /// Not a message: what it was.
    case malformed(String)

    /// Sorts one line.
    static func parse(_ bytes: [UInt8]) -> MCPEnvelope {
        guard
            let document = try? AemiJSON.parse(bytes, options: JSONParseOptions(recordsContainerSpans: true)),
            document.root.isObject
        else { return .malformed(Self.describe(bytes)) }
        let root = document.root
        let id = root["id"].withRawJSONBytes { Array($0) }
        let params = root["params"].isObject ? root["params"].withRawJSONBytes { Array($0) } : nil
        if let method = root["method"].string {
            guard let id else { return .notification(method: method, params: params) }
            return .request(id: id, method: method, params: params)
        }
        guard let number = root["id"].int else {
            return .malformed("a message with no method and no id of this client's")
        }
        if root["error"].isObject {
            return .response(
                id: number,
                outcome: .failure(
                    .rpc(code: root["error"]["code"].int ?? 0, message: root["error"]["message"].string ?? "")))
        }
        guard root["result"].isObject else {
            return .response(id: number, outcome: .failure(.malformedResponse("the result is not an object")))
        }
        return .response(id: number, outcome: .success(root["result"]))
    }

    /// A few words for an event: the first characters of the line.
    private static func describe(_ bytes: [UInt8]) -> String {
        let text = String(decoding: bytes.prefix(60), as: UTF8.self)
        return bytes.count > 60 ? text + "…" : text
    }
}
