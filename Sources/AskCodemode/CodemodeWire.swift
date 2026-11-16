package import AemiJSON

/// The messages between ask and the process that hosts a script's VM (ADR-0156), JSON-RPC, a message a line. ask asks `run`
/// once, with the script and the tools it may call; the host asks `call` for each tool the script calls, and tells `said`
/// each thing the script says, as it says it; `run` is answered with how the script ended. Both ends read and write through
/// here, so the two cannot drift apart.
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

    /// How a script ended: what `run` is answered with. What it said has crossed already, a `said` at a time, so that a script
    /// which is stopped keeps it.
    private struct Ended: Decodable {
        let failure: String?
        let unsettled: Int
    }

    /// The text of a tool's answer.
    private struct Answer: Decodable {
        let text: String
    }

    package static let run = "run"
    package static let call = "call"
    package static let said = "said"

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

    package static func saidParameters(_ item: CodemodeItem) -> JSONValue {
        ["text": .string(item.text), "console": .bool(item.console)]
    }

    package static func item(from parameters: JSON?) -> CodemodeItem? { read(parameters) }

    package static func run(from parameters: JSON?) -> Run? { read(parameters) }

    package static func call(from parameters: JSON?) -> Call? { read(parameters) }

    package static func answerText(from result: JSON) -> String? { (read(result) as Answer?)?.text }

    /// How the script ended, with nothing said: its keeper holds what it said.
    package static func result(from json: JSON) -> CodemodeResult? {
        (read(json) as Ended?).map { CodemodeResult(failure: $0.failure, unsettled: $0.unsettled) }
    }

    /// What `json` holds as a `Value`, or nil when it is not one.
    private static func read<Value: Decodable>(_ json: JSON?) -> Value? {
        json.flatMap { try? AemiJSON.JSONDecoder().decode(Value.self, from: $0) }
    }

    package static func encoded(_ result: CodemodeResult) -> JSONValue {
        var encoded: OrderedDictionary<String, JSONValue> = [:]
        if let failure = result.failure { encoded["failure"] = .string(failure) }
        encoded["unsettled"] = .int(Int64(result.unsettled))
        return .object(encoded)
    }
}
