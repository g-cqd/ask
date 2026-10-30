internal import AskAI
internal import Synchronization

@testable import AskAgentCore

/// A tool that counts its runs, under whatever name a test gives it.
final class CountingTool: Tool {
    let definition: ToolDefinition
    private let runs = Mutex(0)

    init(_ name: String) {
        definition = ToolDefinition(
            name: name, description: "Counts.",
            inputSchema: try! JSONObject(validating: Array(#"{"type":"object"}"#.utf8)))
    }

    var count: Int { runs.withLock { $0 } }

    func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        runs.withLock { $0 += 1 }
        return ToolOutput("ran")
    }
}
