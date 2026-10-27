public import AskAI
public import AskAgentCore
internal import Foundation

/// `write`: creates, overwrites, or applies targeted string replacements to a file.
public struct WriteTool: ArgumentTool {
    public struct Arguments: Decodable, Sendable {
        let path: String
        let content: String?
        let oldText: String?
        let newText: String?
        let replaceAll: Bool?

        private enum CodingKeys: String, CodingKey {
            case path
            case content
            case oldText = "old_text"
            case newText = "new_text"
            case replaceAll = "replace_all"
        }
    }

    public let definition = ToolDefinition(
        name: "write",
        description:
            "Create, overwrite, or edit a file. Supply content (or new_text) to overwrite, or old_text and new_text for exact replacement."
    ) {
        ToolProperty.string("path")
        ToolProperty.string("content").optional
        ToolProperty.string("old_text", minLength: 1).optional
        ToolProperty.string("new_text").optional
        ToolProperty.boolean("replace_all").optional
        SandboxRequest.property
    }

    public init() {}

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        guard arguments.content == nil || (arguments.oldText == nil && arguments.newText == nil) else {
            return .error("Use content alone, or old_text/new_text; do not mix write modes.")
        }
        if let oldText = arguments.oldText {
            guard let newText = arguments.newText else {
                return .error("new_text is required when old_text is provided.")
            }
            return try await EditTool()
                .run(
                    .init(path: arguments.path, oldText: oldText, newText: newText, replaceAll: arguments.replaceAll),
                    in: context)
        }

        guard let payload = arguments.content ?? arguments.newText else {
            return .error("Supply either content/new_text to write, or old_text and new_text to edit.")
        }
        let url = try FileTools.authorized(arguments.path, for: [.write], in: context)
        try FileTools.write(payload, to: url, shownAs: arguments.path, in: context)
        return ToolOutput("Wrote \(payload.utf8.count) bytes to \(arguments.path).")
    }
}
