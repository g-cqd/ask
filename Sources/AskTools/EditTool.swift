internal import AemiKernel
public import AskAI
public import AskAgentCore
internal import Foundation

/// `edit`: replaces an exact piece of text that occurs once, or everywhere when asked.
public struct EditTool: ArgumentTool {
    public struct Arguments: Decodable, Sendable {
        let path: String
        let oldText: String
        let newText: String
        let replaceAll: Bool?

        enum CodingKeys: String, CodingKey {
            case path
            case oldText = "old_text"
            case newText = "new_text"
            case replaceAll = "replace_all"
        }
    }

    public let definition = ToolDefinition(
        name: "edit",
        description:
            "Replace old_text with new_text in a file. old_text must match exactly once unless replace_all is true."
    ) {
        ToolProperty.string("path")
        ToolProperty.string("old_text", minLength: 1)
        ToolProperty.string("new_text")
        ToolProperty.boolean("replace_all").optional
    }

    public init() {}

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        guard !arguments.oldText.isEmpty else { return .error("old_text must not be empty.") }
        let url = FileTools.url(arguments.path, in: context)
        let text = try FileTools.text(at: url, shownAs: arguments.path)
        // Exact UTF-8 bytes, not canonically equivalent characters: the model must reproduce what the file holds,
        // and an edit must never land on text written differently from what it quoted.
        let pieces = ByteSearch.split(Array(text.utf8), on: Array(arguments.oldText.utf8))
        let count = pieces.count - 1
        guard count > 0 else { return .error("old_text was not found in \(arguments.path).") }
        guard count == 1 || arguments.replaceAll == true else {
            return .error(
                "old_text occurs \(count) times in \(arguments.path); add context to make it unique, or set replace_all."
            )
        }
        let replacement = Array(arguments.newText.utf8)
        var editedBytes: [UInt8] = []
        editedBytes.reserveCapacity(text.utf8.count + count * replacement.count)
        for (index, piece) in pieces.enumerated() {
            if index > 0 { editedBytes += replacement }
            editedBytes += piece
        }
        let edited = String(decoding: editedBytes, as: UTF8.self)
        try FileTools.write(edited, to: url, shownAs: arguments.path)
        return ToolOutput("Replaced \(count) occurrence\(count == 1 ? "" : "s") in \(arguments.path).")
    }
}
