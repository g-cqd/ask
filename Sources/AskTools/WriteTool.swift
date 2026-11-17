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
        description: """
            Create or overwrite a file with content, or change part of one by replacing old_text with new_text.
            old_text must be in the file exactly as written, and once only unless replace_all. Missing directories are made.
            """
    ) {
        ToolProperty.string("path").described("The file: absolute, or relative to the working directory.")
        ToolProperty.string("content").described("The whole file. Not with old_text.").optional
        ToolProperty.string("old_text", minLength: 1)
            .described("The exact text to replace, enough of it to match once.").optional
        ToolProperty.string("new_text").described("What replaces old_text.").optional
        ToolProperty.boolean("replace_all").described("Replace every match.").optional
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
                    in: context
                )
        }

        guard let payload = arguments.content ?? arguments.newText else {
            return .error("Supply either content/new_text to write, or old_text and new_text to edit.")
        }
        let url = try FileTools.authorized(arguments.path, for: [.write], in: context)
        try FileTools.write(payload, to: url, shownAs: arguments.path, in: context)
        return ToolOutput("Wrote \(payload.utf8.count) bytes to \(arguments.path).")
    }
}
