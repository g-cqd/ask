internal import AemiJSON

/// An OAuth error body, whose `error` is a code or an object holding one: Codex's endpoints send both.
struct CodexErrorBody: Decodable {
    let code: String?

    private enum Keys: String, CodingKey { case error }
    private enum Nested: String, CodingKey { case code }

    init(from decoder: any Decoder) throws {
        let keys = try decoder.container(keyedBy: Keys.self)
        if let text = try? keys.decode(String.self, forKey: .error) {
            code = text
        } else {
            code = try? keys.nestedContainer(keyedBy: Nested.self, forKey: .error).decode(String.self, forKey: .code)
        }
    }

    /// The code in `body`, or nil when it has none.
    static func code(in body: [UInt8]) -> String? {
        (try? AemiJSON.JSONDecoder().decode(CodexErrorBody.self, from: body))?.code
    }
}
