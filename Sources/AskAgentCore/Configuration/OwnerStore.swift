internal import AemiJSON
internal import AskAI
internal import Foundation

/// A small JSON file among ask's own, the person's alone: what they trusted, what they allowed. Read whole and written whole.
enum OwnerStore {
    /// The value kept at `path`, or nil when there is no file. A file that is there and cannot be read or parsed is an error, never
    /// an empty store: a damaged file must not pass for "nothing was said", nor hide why.
    /// `what` names the file for the error: "a trust store".
    static func load<Value: Decodable>(_: Value.Type, from path: String, what: String) throws(ConfigurationError)
        -> Value?
    {
        guard let bytes = try ConfigurationFileReader.read(path) else { return nil }
        do { return try AemiJSON.JSONDecoder().decode(Value.self, from: bytes) } catch {
            throw .invalid(path: path, line: nil, column: nil, reason: "not \(what): \(error)")
        }
    }

    /// Writes `value` to `path`, owner-only, replacing it atomically, in a directory made owner-only (ADR-0089).
    /// - Throws: ``ConfigurationError/unreadable(path:errno:)`` carrying the errno of whatever failed.
    static func save(_ value: some Encodable, to path: String, flush: (Int32) -> Int32 = FileFlush.barrier)
        throws(ConfigurationError)
    {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var encoder = AemiJSON.JSONEncoder()
        encoder.prettyPrinted = true
        encoder.options.keyOrder = .sorted
        guard let data = try? encoder.encode(value) else {
            throw .invalid(path: path, line: nil, column: nil, reason: "cannot encode")
        }
        // The new file is flushed, renamed over the store, and the folder flushed.
        do { try AtomicFile.replace(URL(fileURLWithPath: path), with: [UInt8](data), flush: flush) } catch {
            throw .unreadable(path: path, errno: error.code)
        }
    }
}
