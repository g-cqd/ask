public import AskAI
public import AskAgentCore
internal import Foundation

/// `write`: the whole file from `content`, or a part of it changed by `old_text` and `new_text`: one way to do each (ADR-0158).
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
            return .error("Give content alone for the whole file, or old_text and new_text to change part of it.")
        }
        if let oldText = arguments.oldText {
            guard let newText = arguments.newText else {
                return .error("Give new_text with old_text: what replaces it, empty to remove it.")
            }
            return try await EditTool()
                .run(
                    .init(path: arguments.path, oldText: oldText, newText: newText, replaceAll: arguments.replaceAll),
                    in: context
                )
        }
        // Refused, not written as the whole file (ADR-0158): new_text alone is as likely an edit that lost its old_text, and
        // writing it would leave the file holding only the piece meant to go into it.
        guard arguments.newText == nil else {
            return .error("Give old_text with new_text to change part of the file, or content for the whole file.")
        }
        guard let content = arguments.content else {
            return .error("Give content for the whole file, or old_text and new_text to change part of it.")
        }
        let url = try FileTools.authorized(arguments.path, for: [.write], in: context)
        try FileTools.write(content, to: url, shownAs: arguments.path, in: context)
        return ToolOutput("Wrote \(content.utf8.count) bytes to \(arguments.path).")
    }
}
