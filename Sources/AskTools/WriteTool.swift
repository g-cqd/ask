internal import AemiKernel
public import AskAI
public import AskAgentCore
internal import Foundation

/// `write`: replaces or creates a whole file.
public struct WriteTool: ArgumentTool {
    public struct Arguments: Decodable, Sendable {
        let path: String
        let content: String
    }

    public let definition = ToolDefinition(
        name: "write",
        description: "Create or replace a whole file with content. Parent directories are created."
    ) {
        ToolProperty.string("path")
        ToolProperty.string("content")
    }

    public init() {}

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let url = try FileTools.authorized(arguments.path, for: [.write], in: context)
        try FileTools.write(arguments.content, to: url, shownAs: arguments.path)
        return ToolOutput("Wrote \(arguments.content.utf8.count) bytes to \(arguments.path).")
    }
}
