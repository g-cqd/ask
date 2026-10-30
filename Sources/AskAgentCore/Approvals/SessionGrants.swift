internal import AemiJSON
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
        var sandbox: [Request]
        var destructive: [String]
    }

    /// Writes the grants to `path`, readable by the person alone.
    public func write(to path: String) throws {
        let record = calls.record
        let wire = Wire(
            phrases: record.phrases, programs: record.programs, files: record.files, tools: record.tools,
            sandbox: sandbox.map { Wire.Request(network: $0.network?.description, write: $0.write, read: $0.read) },
            destructive: destructive.sorted())
        let bytes = try AemiJSON.JSONEncoder().encode(wire)
        guard
            FileManager.default.createFile(atPath: path, contents: Data(bytes), attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
    }

    /// The grants at `path`, which is removed whatever it held; nil when there is no file or it is not one this wrote.
    public static func take(from path: String) -> SessionGrants? {
        defer { try? FileManager.default.removeItem(atPath: path) }
        guard let data = FileManager.default.contents(atPath: path),
            let wire = try? AemiJSON.JSONDecoder().decode(Wire.self, from: Array(data))
        else { return nil }
        return SessionGrants(
            calls: CallGrants(phrases: wire.phrases, programs: wire.programs, files: wire.files, tools: wire.tools),
            sandbox: wire.sandbox.map {
                SandboxRequest(
                    network: $0.network.flatMap(SandboxPolicy.Network.init(named:)), write: $0.write, read: $0.read)
            },
            destructive: Set(wire.destructive))
    }
}
