internal import AemiJSON
internal import Darwin
internal import Foundation

/// What the person allowed for the session, carried across `/reload` (roadmap 0159): the calls (subcommands, programs, files, tools),
/// the sandbox allowances, and the server tools marked destructive. The old process writes it to a file only the person can read; the
/// new one takes it, which removes the file.
public struct SessionGrants: Sendable, Equatable {
    public var calls: CallGrants
    public var sandbox: [SandboxRequest]
    /// `server/tool` keys (ADR-0111).
    public var destructive: Set<String>

    public init(calls: CallGrants = CallGrants(), sandbox: [SandboxRequest] = [], destructive: Set<String> = []) {
        self.calls = calls
        self.sandbox = sandbox
        self.destructive = destructive
    }

    private struct Wire: Codable {
        struct Request: Codable {
            var network: String?
            var write: [String]?
            var read: [String]?
        }

        var phrases: [String]
        var programs: [String]
        var files: [String]
        var tools: [String]
        /// Web hosts `fetch` may read (roadmap 0237); absent in a file written before them.
        var hosts: [String]?
        var sandbox: [Request]
        var destructive: [String]
    }

    /// Writes the grants to `path`, readable by the person alone.
    public func write(to path: String) throws {
        let record = calls.record
        let wire = Wire(
            phrases: record.phrases,
            programs: record.programs,
            files: record.files,
            tools: record.tools,
            hosts: record.hosts,
            sandbox: sandbox.map { Wire.Request(network: $0.network?.description, write: $0.write, read: $0.read) },
            destructive: destructive.sorted()
        )
        let bytes = try AemiJSON.JSONEncoder().encode(wire)
        // A new file only, never through a link, readable by the person alone (security audit 2026-11-22, HIGH-10): what is there
        // already, or a link planted at the name, is not written through.
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try file.write(contentsOf: bytes)
    }

    /// The grants at `path`, which is removed whatever it held; nil when there is no file or it is not one this wrote.
    public static func take(from path: String) -> SessionGrants? {
        // try?: the file is read once; one that cannot be removed is refused on its next read by its owner and mode, not trusted
        defer { try? FileManager.default.removeItem(atPath: path) }
        // Only a regular file of the person's, readable by them alone, opened without following a link (security audit
        // 2026-11-22, HIGH-10): grants are what lets calls run unasked, so a file someone else could write is not read.
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
            info.st_mode & 0o077 == 0,
            let data = try? file.readToEnd(),
            let wire = try? AemiJSON.JSONDecoder().decode(Wire.self, from: Array(data))
        else { return nil }
        return SessionGrants(
            calls: CallGrants(
                phrases: wire.phrases,
                programs: wire.programs,
                files: wire.files,
                tools: wire.tools,
                hosts: wire.hosts ?? []
            ),
            sandbox: wire.sandbox.map {
                SandboxRequest(
                    network: $0.network.flatMap(SandboxPolicy.Network.init(named:)),
                    write: $0.write,
                    read: $0.read
                )
            },
            destructive: Set(wire.destructive)
        )
    }
}
