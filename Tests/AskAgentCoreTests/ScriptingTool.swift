import AemiJSON
import AskAI
import Synchronization

@testable import AskAgentCore

/// A tool that calls the others, as a codemode script does: each line of its `calls` is a tool's name, called with
/// `{"command":"x"}`, and its result is what they returned, a line each. It keeps what it was offered.
final class ScriptingTool: ArgumentTool {
    struct Arguments: Decodable, Sendable {
        let calls: [String]
        var together: Bool?
    }

    let definition = ToolDefinition(name: "script", description: "Calls other tools.") { ToolProperty.string("calls") }
    private let seen = Mutex<[String]?>(nil)

    /// The names it was offered at its last run; nil when it was offered none.
    var offered: [String]? { seen.withLock { $0 } }

    func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        guard let nested = context.nested else { return .error("nothing to call") }
        seen.withLock { $0 = nested.definitions().map(\.name) }
        let input = (try? JSONObject(validating: Array(#"{"command":"x"}"#.utf8))) ?? .empty
        var outputs: [ToolOutput] = []
        if arguments.together == true {
            outputs = await withTaskGroup(of: (Int, ToolOutput).self) { group in
                for (index, name) in arguments.calls.enumerated() {
                    group.addTask { (index, await nested.call(name, input)) }
                }
                var all: [(Int, ToolOutput)] = []
                for await one in group { all.append(one) }
                return all.sorted { $0.0 < $1.0 }.map(\.1)
            }
        } else {
            for name in arguments.calls { outputs.append(await nested.call(name, input)) }
        }
        return ToolOutput(outputs.map { ($0.isError ? "error: " : "ok: ") + $0.content }.joined(separator: "\n"))
    }
}
