internal import AemiKernel
public import AskAI
public import AskAgentCore
internal import Foundation

/// `read`: a file's text, or a window of its lines.
public struct ReadTool: Tool {
    struct Arguments: Decodable {
        let path: String
        let offset: Int?
        let limit: Int?
    }

    public let definition = ToolDefinition(
        name: "read",
        description: "Read a UTF-8 text file. Optionally pass offset (1-based first line) and limit (line count).",
        inputSchema: try! JSONObject(
            validating: Array(
                #"""
                {"type":"object","properties":{"path":{"type":"string"},"offset":{"type":"integer","minimum":1},\#
                "limit":{"type":"integer","minimum":1}},"required":["path"]}
                """#
                .utf8)))

    public init() {}

    public func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        let arguments: Arguments
        switch self.arguments(Arguments.self, from: input) {
            case .success(let value): arguments = value
            case .failure(let output): return output
        }
        let text: String
        switch FileTools.text(at: FileTools.url(arguments.path, in: context), shownAs: arguments.path) {
            case .success(let value): text = value
            case .failure(let failure): return failure.output
        }
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
