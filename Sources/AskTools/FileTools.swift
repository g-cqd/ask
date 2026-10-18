internal import AemiKernel
public import AskAI
public import AskAgentCore
internal import Foundation

/// The file tools, in the order they are offered to the model.
public enum FileTools {
    public static let all: [any Tool] = [ReadTool(), WriteTool(), EditTool()]

    /// The largest file read or edited: far above source files, low enough to bound memory.
    static let maximumFileBytes = 16 << 20

    static func url(_ path: String, in context: ToolContext) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path) : URL(fileURLWithPath: context.workingDirectory).appending(path: path)
    }

    /// The file's text, or the error output explaining why it cannot be had.
    static func text(at url: URL, shownAs path: String) -> Result<String, ToolFailure> {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return .failure(ToolFailure("No file at \(path)."))
        }
        let size = (attributes[.size] as? Int) ?? 0
        guard size <= maximumFileBytes else {
            return .failure(ToolFailure("\(path) is \(size) bytes, over the \(maximumFileBytes)-byte limit."))
        }
        guard let data = try? Data(contentsOf: url) else { return .failure(ToolFailure("Cannot read \(path).")) }
        // On an array, not through Data's iterator: the NUL scan is then a plain loop the compiler vectorizes.
        let bytes = [UInt8](data)
        guard !bytes.contains(0), let text = String(validating: bytes, as: UTF8.self) else {
            return .failure(ToolFailure("\(path) looks binary (\(data.count) bytes); it was not read as text."))
        }
        return .success(text)
    }

    /// Writes atomically. Foundation's atomic write keeps a replaced file's permissions; a test guards that.
    static func write(_ text: String, to url: URL, shownAs path: String) -> ToolFailure? {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            return nil
        } catch {
            return ToolFailure("Cannot write \(path): \(error.localizedDescription)")
        }
    }
}

/// An error output as a value that can travel in a `Result`.
struct ToolFailure: Error {
    let output: ToolOutput
    init(_ message: String) { output = .error(message) }
}

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
