internal import AskAI
public import AskAgentCore
internal import Foundation

/// The file tools, in the order they are offered to the model.
public enum FileTools {
    public static let all: [any Tool] = [ReadTool(), WriteTool()]

    /// The largest file read or edited: far above source files, low enough to bound memory.
    static let maximumFileBytes = 16 << 20

    static func url(_ path: String, in context: ToolContext) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path) : URL(fileURLWithPath: context.workingDirectory).appending(path: path)
    }

    /// The file to touch for `path`, once the sandbox agrees (ADR-0035): the policy is asked for each capability the
    /// tool needs, and the path is then used in its canonical form. That narrows what a link swapped in later can do but does not
    /// end it, so `text` and `write` open the object and check where it really is before using it (``ScopedFile``, ADR-0085).
    /// With nothing restricted the path is used as given and nothing is looked up.
    /// - Throws: a ``ToolFailure`` that names the path the model gave and nothing of the policy that refused it (ADR-0115).
    static func authorized(
        _ path: String, for capabilities: [SandboxCapability], in context: ToolContext
    ) throws(ToolFailure) -> URL {
        guard !context.sandbox.isUnrestricted else { return url(path, in: context) }
        for capability in capabilities {
            let decision = context.sandbox.authorize(capability, path: path, relativeTo: context.workingDirectory)
            if case .denied = decision { throw ToolFailure.notPermitted(path) }
        }
        guard let canonical = CanonicalPath.of(path, relativeTo: context.workingDirectory) else {
            throw ToolFailure.notPermitted(path)
        }
        return URL(fileURLWithPath: canonical)
    }

    /// The file's text, or the error output explaining why it cannot be had.
    ///
    /// Under a policy that restricts anything the file is opened once and checked where it really is (``ScopedFile``); with nothing
    /// restricted it is read by name, as there is nothing to be redirected around.
    /// - Parameters:
    ///   - url: the file, as ``authorized(_:for:in:)`` resolved it.
    ///   - path: the name to show in a failure.
    ///   - context: where the sandbox is.
    ///   - between: runs after the path was authorized and before it is used; only tests give one, to change the file system there.
    /// - Returns: the text.
    /// - Throws: a ``ToolFailure`` for a missing, protected, oversized, binary or unreadable file.
    static func text(
        at url: URL, shownAs path: String, in context: ToolContext, between: () -> Void = {}
    ) throws(ToolFailure) -> String {
        between()
        let bytes =
            context.sandbox.isUnrestricted
            ? try unscopedBytes(at: url, shownAs: path)
            : try ScopedFile.read(url, shownAs: path, limit: maximumFileBytes, in: context)
        // On an array, not through Data's iterator: the NUL scan is then a plain loop the compiler vectorizes.
        guard !bytes.contains(0), let text = String(validating: bytes, as: UTF8.self) else {
            throw ToolFailure("\(path) looks binary (\(bytes.count) bytes); it was not read as text.")
        }
        return text
    }

    private static func unscopedBytes(at url: URL, shownAs path: String) throws(ToolFailure) -> [UInt8] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            throw ToolFailure("No file at \(path).")
        }
        let size = (attributes[.size] as? Int) ?? 0
        guard size <= maximumFileBytes else {
            throw ToolFailure("\(path) is \(size) bytes, over the \(maximumFileBytes)-byte limit.")
        }
        guard let data = try? Data(contentsOf: url) else { throw ToolFailure("Cannot read \(path).") }
        return [UInt8](data)
    }

    /// Writes atomically. Foundation's atomic write keeps a replaced file's permissions; a test guards that, and so that
    /// ``ScopedFile`` keeps them too.
    /// - Parameters:
    ///   - text: what the file is to hold.
    ///   - url: the file, as ``authorized(_:for:in:)`` resolved it.
    ///   - path: the name to show in a failure.
    ///   - context: where the sandbox is.
    ///   - between: runs after the path was authorized and before it is used; only tests give one, to change the file system there.
    /// - Throws: a ``ToolFailure`` if the write is protected or cannot be done.
    static func write(
        _ text: String, to url: URL, shownAs path: String, in context: ToolContext, between: () -> Void = {}
    ) throws(ToolFailure) {
        between()
        guard context.sandbox.isUnrestricted else {
            try ScopedFile.write(Array(text.utf8), to: url, shownAs: path, in: context)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw ToolFailure("Cannot write \(path): \(error.localizedDescription)")
        }
    }
}
