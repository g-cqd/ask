internal import AemiKernel
public import AskAI
public import AskAgentCore
internal import Foundation

/// `read`: a file's text or a window of its lines, or an image, pages of a PDF, or frames of a video.
public struct ReadTool: ArgumentTool {
    /// The most images one call returns when the model does not say, and the most it may ask for.
    static let defaultImages = 8
    static let largestImages = 20

    public struct Arguments: Decodable, Sendable {
        let path: String
        let offset: Int?
        let limit: Int?
        let pages: String?
        let at: [Double]?
        let count: Int?
        let every: Double?
        let start: Double?
        let end: Double?
        let maxImages: Int?

        private enum CodingKeys: String, CodingKey {
            case path, offset, limit, pages, at, count, every, start, end
            case maxImages = "max_images"
        }
    }

    public let definition = ToolDefinition(
        name: "read",
        description: """
            Read a UTF-8 text file (optionally offset, the 1-based first line, and limit, a line count), or show an image \
            (PNG, JPEG, GIF, WebP, BMP, TIFF, HEIC, AVIF), a PDF, or a video (MP4, MOV, M4V) as pictures. For a PDF, pages \
            such as "1-3,7" chooses pages. For a video, at (seconds) takes exact frames; otherwise count frames are spread \
            over start..end (seconds), or one is taken every `every` seconds. max_images (default 8, at most 20) limits the \
            pictures returned by one call.
            """
    ) {
        ToolProperty.string("path")
        ToolProperty.integer("offset", minimum: 1).optional
        ToolProperty.integer("limit", minimum: 1).optional
        ToolProperty.string("pages").optional
        ToolProperty.schema("at", #"{"type":"array","items":{"type":"number","minimum":0}}"#).optional
        ToolProperty.integer("count", minimum: 1, maximum: 20).optional
        ToolProperty.schema("every", #"{"type":"number","exclusiveMinimum":0}"#).optional
        ToolProperty.schema("start", #"{"type":"number","minimum":0}"#).optional
        ToolProperty.schema("end", #"{"type":"number","minimum":0}"#).optional
        ToolProperty.integer("max_images", minimum: 1, maximum: 20).optional
        // @dl:accept -- the file tools share a tool's shape: a schema, an empty init, and a run that asks the sandbox first
        SandboxRequest.property
    }

    public init() {}

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let url = try FileTools.authorized(arguments.path, for: [.read], in: context)
        let header = FileTools.header(of: url)
        let maximumImages = min(Self.largestImages, max(1, arguments.maxImages ?? Self.defaultImages))
        if VideoReader.looksLikeVideo(header) {
            let request = VideoReader.Request(
                at: arguments.at, count: arguments.count, every: arguments.every, start: arguments.start,
                end: arguments.end, maximumImages: maximumImages)
            return try await VideoReader.read(url, path: arguments.path, request)
        }
        let isMedia = ImageReader.mediaType(of: header) != nil || PDFReader.isPDF(header)
        let bytes = try FileTools.bytes(
            at: url, shownAs: arguments.path, in: context,
            limit: isMedia ? FileTools.maximumMediaBytes : FileTools.maximumFileBytes)
        if PDFReader.isPDF(bytes) {
            return try PDFReader.read(bytes, path: arguments.path, pages: arguments.pages, maximumImages: maximumImages)
        }
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
