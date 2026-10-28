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
        description:
            "Read a UTF-8 text file, or an image (PNG, JPEG, GIF, WebP) which is shown to you. For text, optionally pass offset (1-based first line) and limit (line count)."
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
        let bytes = try FileTools.bytes(at: url, shownAs: arguments.path, in: context)
        if ImageReader.mediaType(of: bytes) != nil { return try image(bytes, shownAs: arguments.path) }
        let text = try FileTools.text(from: bytes, shownAs: arguments.path)
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

    /// An image file: a line saying what it is, and the image itself for a model that takes images (roadmap 0084).
    private func image(_ bytes: [UInt8], shownAs path: String) throws(ToolFailure) -> ToolOutput {
        do {
            let result = try ImageReader.read(bytes)
            var output = ToolOutput("\(path): \(result.summary)")
            output.images = [result.part]
            return output
        } catch .animated {
            throw ToolFailure("\(path) is an animated PNG; it was not read.")
        } catch .cannotFit {
            throw ToolFailure("\(path) could not be made small enough to send (long side 2000 px, 4.5 MiB as base64).")
        } catch {
            throw ToolFailure("\(path) looks like an image but could not be decoded.")
        }
    }
}
