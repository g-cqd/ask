public import AskAI
public import AskAgentCore
internal import Foundation
internal import Subprocess
internal import System

/// Runs untrusted image, PDF, and video decoding inside a short-lived Seatbelt-confined child process (`ask decode-media`,
/// security review 2026-11-25 N-A2 / R-DES-2): no network, no keychain, zero inherited environment, and read-only access
/// strictly to the single verified media copy, returning re-encoded pixels or extracted text with a hard byte bound.
///
/// A memory-corruption bug in ImageIO, CoreGraphics, PDFKit, or AVFoundation is thereby contained to a credential-free,
/// network-less child process that terminates immediately after one decode.
public enum MediaDecodeHost {
    public struct Request: Codable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case image, pdf, video
        }

        public var kind: Kind
        public var filePath: String
        public var shownPath: String
        public var pages: String?
        public var render: Bool
        public var maximumImages: Int
        public var at: [Double]?
        public var count: Int?
        public var every: Double?
        public var start: Double?
        public var end: Double?
        public var imageLimits: ImageLimits?

        public init(
            kind: Kind,
            filePath: String,
            shownPath: String,
            pages: String? = nil,
            render: Bool = false,
            maximumImages: Int = 8,
            at: [Double]? = nil,
            count: Int? = nil,
            every: Double? = nil,
            start: Double? = nil,
            end: Double? = nil,
            imageLimits: ImageLimits? = nil
        ) {
            self.kind = kind
            self.filePath = filePath
            self.shownPath = shownPath
            self.pages = pages
            self.render = render
            self.maximumImages = maximumImages
            self.at = at
            self.count = count
            self.every = every
            self.start = start
            self.end = end
            self.imageLimits = imageLimits
        }
    }

    public struct Response: Codable, Sendable {
        public struct EncodedImage: Codable, Sendable {
            public var mediaType: String
            public var dataBase64: String
        }

        public var content: String
        public var isError: Bool
        public var images: [EncodedImage]
    }

    /// Maximum stdout payload returned by one media decode helper (128 MiB).
    static let maximumResponseBytes = 128 << 20

    /// The strict zero-network, read-only Seatbelt profile confining `ask decode-media` to `filePath` and `executable`
    /// (resolved canonically so symlinks like `/tmp` → `/private/tmp` match Seatbelt subpath rules).
    public static func sandboxPolicy(for filePath: String, executable: String) -> SandboxPolicy {
        let canonicalFile = CanonicalPath.of(filePath, relativeTo: "/") ?? filePath
        let canonicalExec = CanonicalPath.of(executable, relativeTo: "/") ?? executable
        let dir = (canonicalFile as NSString).deletingLastPathComponent
        let execDir = (canonicalExec as NSString).deletingLastPathComponent
        return SandboxPolicy(
            network: .none,
            write: .roots([]),
            read: .roots([dir, execDir]),
            denyRead: [],
            denyWrite: [],
            askable: []
        )
    }

    /// Serves one JSON `Request` from stdin and writes one JSON `Response` to stdout. Called by `ask decode-media`.
    public static func serveStandardStreams() async {
        let inputData = FileHandle.standardInput.readDataToEndOfFile()
        let response: Response
        do {
            let request = try JSONDecoder().decode(Request.self, from: inputData)
            response = await decodeLocally(request)
        } catch {
            response = Response(content: "Media decoder received malformed request.", isError: true, images: [])
        }
        if let encoded = try? JSONEncoder().encode(response) {
            FileHandle.standardOutput.write(encoded)
        }
    }

    /// Executes `request` inside the current (already-sandboxed helper) process.
    static func decodeLocally(_ request: Request) async -> Response {
        let allowance = ImageReader.Allowance(request.imageLimits)
        let url = URL(fileURLWithPath: request.filePath)
        do {
            let output: ToolOutput
            switch request.kind {
                case .video:
                    let videoRequest = VideoReader.Request(
                        at: request.at,
                        count: request.count,
                        every: request.every,
                        start: request.start,
                        end: request.end,
                        maximumImages: request.maximumImages
                    )
                    output = try await VideoReader.read(
                        url,
                        path: request.shownPath,
                        videoRequest,
                        allowance: allowance
                    )
                case .pdf:
                    let bytes = try readBoundedBytes(at: url, shownAs: request.shownPath)
                    output = try PDFReader.read(
                        bytes,
                        path: request.shownPath,
                        pages: request.pages,
                        maximumImages: request.maximumImages,
                        render: request.render,
                        allowance: allowance
                    )
                case .image:
                    let bytes = try readBoundedBytes(at: url, shownAs: request.shownPath)
                    output = try decodeImage(bytes, shownAs: request.shownPath, allowance: allowance)
            }
            return Response(
                content: output.content,
                isError: output.isError,
                images: output.images.map {
                    Response.EncodedImage(mediaType: $0.mediaType, dataBase64: Data($0.data).base64EncodedString())
                }
            )
        } catch {
            return Response(content: error.output.content, isError: true, images: [])
        }
    }

    /// Decodes `request` inside a short-lived `sandbox-exec` child of `executable` (`ask decode-media`), with zero
    /// network, zero inherited credentials, and read-only access solely to `request.filePath`'s private directory.
    static func runSandboxed(_ request: Request, executable: String) async throws(ToolFailure) -> ToolOutput {
        let payload: Data
        do { payload = try JSONEncoder().encode(request) } catch {
            throw ToolFailure("\(request.shownPath) could not be prepared for decoding.")
        }
        let policy = sandboxPolicy(for: request.filePath, executable: executable)
        let arguments = SeatbeltProfile(policy).arguments + [executable, "decode-media"]
        let status: TerminationStatus
        let stdout: Data
        do {
            let result = try await Subprocess.run(
                .path(FilePath("/usr/bin/sandbox-exec")),
                arguments: Arguments(arguments),
                environment: .custom([:]),
                platformOptions: JobProcess.groupOptions(graceSeconds: 1),
                input: .data(payload),
                output: .data(limit: maximumResponseBytes),
                error: .discarded
            )
            status = result.terminationStatus
            stdout = result.standardOutput
        } catch {
            throw ToolFailure("\(request.shownPath): sandboxed media decoder failed to run.")
        }
        guard status.isSuccess, !stdout.isEmpty,
            let decoded = try? JSONDecoder().decode(Response.self, from: stdout)
        else {
            throw ToolFailure("\(request.shownPath) could not be decoded in the media sandbox.")
        }
        if decoded.isError { throw ToolFailure(decoded.content) }
        var output = ToolOutput(decoded.content)
        output.images = decoded.images.compactMap { part in
            guard let bytes = Data(base64Encoded: part.dataBase64) else { return nil }
            return ImagePart(mediaType: part.mediaType, data: Array(bytes))
        }
        return output
    }

    private static func readBoundedBytes(at url: URL, shownAs path: String) throws(ToolFailure) -> [UInt8] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count <= FileTools.maximumMediaBytes
        else { throw ToolFailure("\(path) could not be read.") }
        return Array(data)
    }

    static func decodeImage(_ bytes: [UInt8], shownAs path: String, allowance: ImageReader.Allowance)
        throws(ToolFailure)
        -> ToolOutput
    {
        do {
            let result = try ImageReader.read(bytes, allowance: allowance)
            var output = ToolOutput("\(path): \(result.summary)")
            output.images = [result.part]
            return output
        } catch .animated {
            throw ToolFailure("\(path) is an animated PNG; it was not read.")
        } catch .cannotFit {
            throw ToolFailure(
                "\(path) could not be made small enough to send (long side 2000 px, 4.5 MiB as base64, and what the model's provider accepts)."
            )
        } catch {
            throw ToolFailure("\(path) looks like an image but could not be decoded.")
        }
    }
}
