internal import AemiKernel
public import AskAI
public import AskAgentCore
internal import Foundation

/// `write`: replaces or creates a whole file.
public struct WriteTool: Tool {
    struct Arguments: Decodable {
        let path: String
        let content: String
    }

    public let definition = ToolDefinition(
        name: "write",
        description: "Create or replace a whole file with content. Parent directories are created.",
        inputSchema: try! JSONObject(
            validating: Array(
                #"""
                {"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},\#
                "required":["path","content"]}
                """#
                .utf8)))

    public init() {}

    public func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        let arguments: Arguments
        switch self.arguments(Arguments.self, from: input) {
            case .success(let value): arguments = value
            case .failure(let output): return output
        }
        let url = FileTools.url(arguments.path, in: context)
        if let failure = FileTools.write(arguments.content, to: url, shownAs: arguments.path) { return failure.output }
        return ToolOutput("Wrote \(arguments.content.utf8.count) bytes to \(arguments.path).")
    }
}
