internal import AemiKernel
public import AskAI
public import AskAgentCore
internal import Foundation

/// `read`: a file's text, or a window of its lines.
public struct ReadTool: ArgumentTool {
    public struct Arguments: Decodable, Sendable {
        let path: String
        let offset: Int?
        let limit: Int?
    }

    public let definition = ToolDefinition(
        name: "read",
        description: "Read a UTF-8 text file. Optionally pass offset (1-based first line) and limit (line count)."
    ) {
        ToolProperty.string("path")
        ToolProperty.integer("offset", minimum: 1).optional
        ToolProperty.integer("limit", minimum: 1).optional
        // @dl:accept -- the file tools share a tool's shape: a schema, an empty init, and a run that asks the sandbox first
        SandboxRequest.property
    }

    public init() {}

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let url = try FileTools.authorized(arguments.path, for: [.read], in: context)
        let text = try FileTools.text(at: url, shownAs: arguments.path)
        guard arguments.offset != nil || arguments.limit != nil else { return ToolOutput(text) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let first = Swift.max(1, arguments.offset ?? 1)
        guard first <= lines.count else {
            return .error("\(arguments.path) has \(lines.count) lines; offset \(first) is past the end.")
        }
        let last = Swift.min(lines.count, first + Swift.max(1, arguments.limit ?? lines.count) - 1)
        return ToolOutput(
            lines[(first - 1) ..< last].joined(separator: "\n") + "\n[lines \(first)–\(last) of \(lines.count)]")
    }
}
