package import AemiJSON

/// The messages between ask and the process that hosts a script's VM (ADR-0156), JSON-RPC, a message a line. ask asks `run`
/// once, with the script and the tools it may call; the host asks `call` for each tool the script calls; `run` is answered
/// with what the script came to. Both ends read and write through here, so the two cannot drift apart.
package enum CodemodeWire {
    /// What `run` carries.
    package struct Run: Decodable {
        package let code: String
        package let tools: [CodemodeCallable]
    }

    /// What `call` carries: the tool's own name, and its arguments as the JSON object's text.
    package struct Call: Decodable {
        package let tool: String
        package let arguments: String
    }

    /// The text of a tool's answer.
    private struct Answer: Decodable {
        let text: String
    }

    package static let run = "run"
    package static let call = "call"

    package static func runParameters(code: String, tools: [CodemodeCallable]) -> JSONValue {
        let listed = tools.map { tool -> JSONValue in
            ["name": .string(tool.name), "description": .string(tool.description)]
        }
        return ["code": .string(code), "tools": .array(listed)]
    }

    package static func callParameters(tool: String, arguments: String) -> JSONValue {
        ["tool": .string(tool), "arguments": .string(arguments)]
    }

    package static func answer(_ text: String) -> JSONValue { ["text": .string(text)] }

    package static func run(from parameters: JSON?) -> Run? { read(parameters) }

    package static func call(from parameters: JSON?) -> Call? { read(parameters) }

    package static func answerText(from result: JSON) -> String? { (read(result) as Answer?)?.text }

    package static func result(from json: JSON) -> CodemodeResult? { read(json) }

    /// What `json` holds as a `Value`, or nil when it is not one.
    private static func read<Value: Decodable>(_ json: JSON?) -> Value? {
        json.flatMap { try? AemiJSON.JSONDecoder().decode(Value.self, from: $0) }
    }

    package static func encoded(_ result: CodemodeResult) -> JSONValue {
        let items = result.items.map { item -> JSONValue in ["text": .string(item.text), "console": .bool(item.console)]
        }
        var encoded: OrderedDictionary<String, JSONValue> = ["items": .array(items)]
        if let failure = result.failure { encoded["failure"] = .string(failure) }
        encoded["unsettled"] = .int(Int64(result.unsettled))
        return .object(encoded)
    }
}
