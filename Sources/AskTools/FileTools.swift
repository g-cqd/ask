internal import AskAI
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
    static func text(at url: URL, shownAs path: String) throws(ToolFailure) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            throw ToolFailure("No file at \(path).")
        }
        let size = (attributes[.size] as? Int) ?? 0
        guard size <= maximumFileBytes else {
            throw ToolFailure("\(path) is \(size) bytes, over the \(maximumFileBytes)-byte limit.")
        }
        guard let data = try? Data(contentsOf: url) else { throw ToolFailure("Cannot read \(path).") }
        // On an array, not through Data's iterator: the NUL scan is then a plain loop the compiler vectorizes.
        let bytes = [UInt8](data)
        guard !bytes.contains(0), let text = String(validating: bytes, as: UTF8.self) else {
            throw ToolFailure("\(path) looks binary (\(data.count) bytes); it was not read as text.")
        }
        return text
    }

    /// Writes atomically. Foundation's atomic write keeps a replaced file's permissions; a test guards that.
    static func write(_ text: String, to url: URL, shownAs path: String) throws(ToolFailure) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw ToolFailure("Cannot write \(path): \(error.localizedDescription)")
        }
    }
}
