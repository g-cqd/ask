internal import AemiKernel
public import AskAI
public import AskAgentCore
internal import Foundation

/// `edit`: replaces an exact piece of text that occurs once, or everywhere when asked.
public struct EditTool: Tool {
    struct Arguments: Decodable {
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
            "Replace old_text with new_text in a file. old_text must match exactly once unless replace_all is true.",
        inputSchema: try! JSONObject(
            validating: Array(
                #"""
                {"type":"object","properties":{"path":{"type":"string"},"old_text":{"type":"string","minLength":1},\#
                "new_text":{"type":"string"},"replace_all":{"type":"boolean"}},"required":["path","old_text","new_text"]}
                """#
                .utf8)))

    public init() {}

    public func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        let arguments: Arguments
        switch self.arguments(Arguments.self, from: input) {
            case .success(let value): arguments = value
            case .failure(let output): return output
        }
        guard !arguments.oldText.isEmpty else { return .error("old_text must not be empty.") }
        let url = FileTools.url(arguments.path, in: context)
        let text: String
        switch FileTools.text(at: url, shownAs: arguments.path) {
            case .success(let value): text = value
            case .failure(let failure): return failure.output
        }
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
        if let failure = FileTools.write(edited, to: url, shownAs: arguments.path) { return failure.output }
        return ToolOutput("Replaced \(count) occurrence\(count == 1 ? "" : "s") in \(arguments.path).")
    }
}
