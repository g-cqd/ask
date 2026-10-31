internal import AemiJSON
public import Foundation

/// Which account a model several accounts serve was last chosen with, so `/model` asks once and then uses it (roadmap 0092). A
/// preference, not a secret: a damaged file is read as nothing remembered and the next choice rewrites it.
public struct ModelAccountMemory: Sendable {
    public let url: URL

    /// The memory kept at `url`; nothing is read or made until it is asked.
    public init(url: URL) { self.url = url }

    /// The account last chosen for `model` of the `kind` subscription, when there is one.
    public func account(for model: String, kind: ConnectionKind) -> String? { load()[Self.key(model, kind)] }

    /// Remembers `account` for `model` of the `kind` subscription, in place of any earlier choice.
    /// - Throws: ``AtomicFile/Failure`` when the file cannot be written.
    public func remember(_ account: String, for model: String, kind: ConnectionKind) throws {
        var all = load()
        guard all[Self.key(model, kind)] != account else { return }
        all[Self.key(model, kind)] = account
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        var encoder = AemiJSON.JSONEncoder()
        encoder.options.keyOrder = .sorted
        try AtomicFile.replace(url, with: try encoder.encodeToBytes(all))
    }

    private static func key(_ model: String, _ kind: ConnectionKind) -> String { "\(kind.rawValue)/\(model)" }

    private func load() -> [String: String] {
        guard let data = FileManager.default.contents(atPath: url.path) else { return [:] }
        return (try? AemiJSON.JSONDecoder().decode([String: String].self, from: [UInt8](data))) ?? [:]
    }
}
