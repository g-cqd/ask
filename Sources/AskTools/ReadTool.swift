internal import AemiKernel
public import AskAI
public import AskAgentCore
internal import Foundation

/// `read`: a file's text or a window of its lines, or an image, pages of a PDF, or frames of a video.
public struct ReadTool: ArgumentTool {
    /// The most images one call returns when the model does not say, and the most it may ask for.
    static let defaultImages = 8
    static let largestImages = 20
    /// What `max_images` says of itself: one number for how many pictures, a video's frames among them (ADR-0164).
    private static let pictures =
        "The most pictures one call returns: 8 unless given. Video: that many frames, 4 unless given, spread evenly from start to end."

    public struct Arguments: Decodable, Sendable {
        let path: String
        let offset: Int?
        let limit: Int?
        let pages: String?
        let at: [Double]?
        /// What `max_images` was called for a video before ADR-0164: read as it, said to no model, so that it is not dropped silently.
        let count: Int?
        let every: Double?
        let start: Double?
        let end: Double?
        let maxImages: Int?
        let render: Bool?

        private enum CodingKeys: String, CodingKey {
            case path, offset, limit, pages, at, count, every, start, end, render
            case maxImages = "max_images"
        }
    }

    public let definition = ToolDefinition(
        name: "read",
        description: """
            Read a file: text as text; an image (PNG, JPEG, GIF, WebP, BMP, TIFF, HEIC, AVIF), a PDF or a video (MP4, MOV, M4V) \
            as pictures.
            Text comes whole unless offset or limit choose lines. A PDF page with text comes as text, one without as a picture.
            """
    ) {
        ToolProperty.string("path").described("The file: absolute, or relative to the working directory.")
        ToolProperty.integer("offset", minimum: 1).described("Text: the first line to return, counting from 1.")
            .optional
        ToolProperty.integer("limit", minimum: 1).described("Text: how many lines to return.").optional
        // @dl:accept -- a tool declares its arguments and what each says through one builder: the lists are data
        ToolProperty.string("pages").described(#"PDF: the pages to read, such as "1-3,7"."#).optional
        ToolProperty.schema("at", #"{"type":"array","items":{"type":"number","minimum":0}}"#)
            .described("Video: the seconds at which to take frames, exactly.").optional
        ToolProperty.schema("every", #"{"type":"number","exclusiveMinimum":0}"#)
            .described("Video: a frame every this many seconds.").optional
        ToolProperty.schema("start", #"{"type":"number","minimum":0}"#)
            .described("Video: where the frames begin, in seconds.").optional
        ToolProperty.schema("end", #"{"type":"number","minimum":0}"#)
            .described("Video: where the frames end, in seconds.").optional
        // @dl:accept -- a tool declares its arguments and what each says through one builder: the lists are data
        ToolProperty.integer("max_images", minimum: 1, maximum: 20).described(Self.pictures).optional
        ToolProperty.boolean("render").described("PDF: every page as a picture, also a page that has text.").optional
        // @dl:accept -- the file tools share a tool's shape: a schema, an empty init, and a run that asks the sandbox first
        SandboxRequest.property
    }

    /// Executable path of `ask` for out-of-process Seatbelt media decoding (`ask decode-media`, N-A2).
    /// Nil in unit tests (which run in-process without the `ask` CLI binary).
    public let mediaDecoderExecutable: String?

    public init(mediaDecoderExecutable: String? = nil) {
        self.mediaDecoderExecutable = mediaDecoderExecutable
    }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let url = try FileTools.authorized(arguments.path, for: [.read], in: context)
        let header = FileTools.header(of: url, in: context)
        let asked = arguments.maxImages ?? arguments.count
        let maximumImages = min(Self.largestImages, max(1, asked ?? Self.defaultImages))
        if VideoReader.looksLikeVideo(header) {
            return try await readVideo(
                at: url,
                arguments: arguments,
                asked: asked,
                maximumImages: maximumImages,
                in: context
            )
        }
        let isPDF = PDFReader.isPDF(header)
        let isImage = ImageReader.mediaType(of: header) != nil
        if let executable = mediaDecoderExecutable, !context.sandbox.isUnrestricted, isPDF || isImage {
            return try await readMediaSandboxed(
                at: url,
                kind: isPDF ? .pdf : .image,
                arguments: arguments,
                maximumImages: maximumImages,
                executable: executable,
                in: context
            )
        }
        let bytes = try FileTools.bytes(
            at: url,
            shownAs: arguments.path,
            in: context,
            limit: (isImage || isPDF) ? FileTools.maximumMediaBytes : FileTools.maximumFileBytes
        )
        if PDFReader.isPDF(bytes) {
            return try PDFReader.read(
                bytes,
                path: arguments.path,
                pages: arguments.pages,
                maximumImages: maximumImages,
                render: arguments.render ?? false,
                allowance: ImageReader.Allowance(context.imageLimits)
            )
        }
        if ImageReader.mediaType(of: bytes) != nil {
            return try MediaDecodeHost.decodeImage(
                bytes,
                shownAs: arguments.path,
                allowance: ImageReader.Allowance(context.imageLimits)
            )
        }
        let text = try FileTools.text(from: bytes, shownAs: arguments.path)
        guard arguments.offset != nil || arguments.limit != nil else { return ToolOutput(text) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let first = Swift.max(1, arguments.offset ?? 1)
        guard first <= lines.count else {
            return .error("\(arguments.path) has \(lines.count) lines; offset \(first) is past the end.")
        }
        let last = Swift.min(lines.count, first + Swift.max(1, arguments.limit ?? lines.count) - 1)
        return ToolOutput(
            lines[(first - 1) ..< last].joined(separator: "\n") + "\n[lines \(first)–\(last) of \(lines.count)]"
        )
    }

    private func readVideo(
        at url: URL,
        arguments: Arguments,
        asked: Int?,
        maximumImages: Int,
        in context: ToolContext
    ) async throws(ToolFailure) -> ToolOutput {
        let request = VideoReader.Request(
            at: arguments.at,
            // One number says how many pictures (ADR-0164): a video's frames are that many, and 4 when the call does not say.
            count: asked.map { _ in maximumImages },
            every: arguments.every,
            start: arguments.start,
            end: arguments.end,
            maximumImages: maximumImages
        )
        let allowance = ImageReader.Allowance(context.imageLimits)
        if let executable = mediaDecoderExecutable, !context.sandbox.isUnrestricted {
            return try await ScopedFile.withCopy(
                of: url,
                shownAs: arguments.path,
                limit: FileTools.maximumMediaBytes,
                in: context
            ) { copy throws(ToolFailure) in
                var media = MediaDecodeHost.Request(kind: .video, filePath: copy.path, shownPath: arguments.path)
                media.maximumImages = maximumImages
                media.at = request.at
                media.count = request.count
                media.every = request.every
                media.start = request.start
                media.end = request.end
                media.imageLimits = context.imageLimits
                return try await MediaDecodeHost.runSandboxed(media, executable: executable)
            }
        }
        if context.sandbox.isUnrestricted {
            return try await VideoReader.read(url, path: arguments.path, request, allowance: allowance)
        }
        // AVFoundation opens a path, and a path can be swapped after the check: it reads a verified copy instead.
        return try await ScopedFile.withCopy(
            of: url,
            shownAs: arguments.path,
            limit: FileTools.maximumMediaBytes,
            in: context
        ) { copy throws(ToolFailure) in
            try await VideoReader.read(copy, path: arguments.path, request, allowance: allowance)
        }
    }

    private func readMediaSandboxed(
        at url: URL,
        kind: MediaDecodeHost.Request.Kind,
        arguments: Arguments,
        maximumImages: Int,
        executable: String,
        in context: ToolContext
    ) async throws(ToolFailure) -> ToolOutput {
        try await ScopedFile.withCopy(
            of: url,
            shownAs: arguments.path,
            limit: FileTools.maximumMediaBytes,
            in: context
        ) { copy throws(ToolFailure) in
            var media = MediaDecodeHost.Request(kind: kind, filePath: copy.path, shownPath: arguments.path)
            media.pages = arguments.pages
            media.render = arguments.render ?? false
            media.maximumImages = maximumImages
            media.imageLimits = context.imageLimits
            return try await MediaDecodeHost.runSandboxed(media, executable: executable)
        }
    }
}
