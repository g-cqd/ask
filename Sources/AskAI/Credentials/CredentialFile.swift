internal import AemiJSON
internal import Darwin
public import Foundation

/// Every provider's credentials in one owner-only JSON file (ADR-0018), each saved without disturbing the others.
///
/// The directory is created 0700 and the file 0600. A save writes a new file beside the old one and renames
/// it into place, so a crash leaves the old credentials or the new ones, never a mixture.
public struct CredentialFile: Sendable {
    public let url: URL

    /// The file at `url`.
    public init(url: URL) { self.url = url }

    /// `$XDG_CONFIG_HOME/ask/credentials.json` when that is an absolute path, else
    /// `~/.config/ask/credentials.json`.
    public static func standard(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> CredentialFile {
        let configured = environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        let base = URL(fileURLWithPath: configured ?? home + "/.config", isDirectory: true)
        return CredentialFile(url: base.appending(path: "ask/credentials.json"))
    }

    /// The stored Claude credentials, or nil when there are none.
    /// - Throws: ``CredentialFileError/exposed(path:mode:)`` or ``CredentialFileError/damaged(path:)``, so a
    ///   problem is never mistaken for being signed out.
    public func loadClaude() throws(CredentialFileError) -> ClaudeCredentials? { try read()?.claude }

    /// Stores Claude credentials, replacing any, and keeping every other provider's.
    /// - Throws: ``CredentialFileError/io(path:errno:)``, or ``CredentialFileError/damaged(path:)`` when the file
    ///   cannot be read, which is never overwritten.
    public func saveClaude(_ credentials: ClaudeCredentials) throws(CredentialFileError) {
        var stored = try read() ?? Stored()
        stored.claude = credentials
        try write(stored)
    }

    /// The key a provider's sign-in stored, or nil when there is none.
    /// - Throws: as ``loadClaude()``.
    public func loadKey(for provider: String) throws(CredentialFileError) -> StoredKey? { try read()?.keys?[provider] }

    /// Stores `key` for `provider`, replacing its previous one and keeping every other provider's credentials.
    /// - Throws: as ``saveClaude(_:)``.
    public func saveKey(_ key: StoredKey, for provider: String) throws(CredentialFileError) {
        var stored = try read() ?? Stored()
        stored.keys = (stored.keys ?? [:]).merging([provider: key]) { _, new in new }
        try write(stored)
    }

    /// Removes `provider`'s key, keeping every other provider's credentials. Nothing stored is not an error.
    /// - Throws: as ``saveClaude(_:)``.
    public func removeKey(for provider: String) throws(CredentialFileError) {
        guard var stored = try read(), stored.keys?[provider] != nil else { return }
        stored.keys?[provider] = nil
        try write(stored)
    }

    /// The providers that have a stored key, in name order.
    /// - Throws: as ``loadClaude()``.
    public func storedKeyProviders() throws(CredentialFileError) -> [String] {
        (try read()?.keys?.keys).map { $0.sorted() } ?? []
    }

    // MARK: - The file

    /// What the file holds, or nil when there is no file.
    private func read() throws(CredentialFileError) -> Stored? {
        var status = stat()
        guard stat(url.path, &status) == 0 else {
            if errno == ENOENT { return nil }
            throw .io(path: url.path, errno: errno)
        }
        let mode = Int(status.st_mode) & 0o777
        guard mode & 0o077 == 0 else { throw .exposed(path: url.path, mode: mode) }
        guard let bytes = try? Data(contentsOf: url) else { throw .io(path: url.path, errno: errno) }
        guard let stored = try? AemiJSON.JSONDecoder().decode(Stored.self, from: [UInt8](bytes)) else {
            throw .damaged(path: url.path)
        }
        return stored
    }

    /// Writes `stored` as a new owner-only file and renames it into place, so a crash leaves the old file or the new.
    private func write(_ stored: Stored) throws(CredentialFileError) {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .io(path: directory.deletingLastPathComponent().path, errno: EACCES)
        }
        if mkdir(directory.path, 0o700) != 0, errno != EEXIST { throw .io(path: directory.path, errno: errno) }
        var encoder = AemiJSON.JSONEncoder()
        encoder.options.keyOrder = .sorted
        guard let bytes = try? encoder.encodeToBytes(stored) else { throw .damaged(path: url.path) }
        let temporary = directory.appending(path: ".credentials-\(UUID().uuidString).json")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw .io(path: temporary.path, errno: errno) }
        let written = bytes.withUnsafeBytes { unsafe Darwin.write(descriptor, $0.baseAddress, $0.count) }
        let flushed = fsync(descriptor)
        close(descriptor)
        guard written == bytes.count, flushed == 0, rename(temporary.path, url.path) == 0 else {
            let failure = errno
            unlink(temporary.path)
            throw .io(path: url.path, errno: failure)
        }
    }

    /// Deletes the whole file, every provider's credentials. Nothing stored is not an error.
    /// - Throws: ``CredentialFileError/io(path:errno:)``.
    public func remove() throws(CredentialFileError) {
        guard unlink(url.path) == 0 || errno == ENOENT else { throw .io(path: url.path, errno: errno) }
    }

    /// The file's shape: Claude's credentials where they always were, and other providers' keys beside them, so a
    /// file written before keys existed still reads.
    private struct Stored: Codable {
        var claude: ClaudeCredentials?
        var keys: [String: StoredKey]?
    }
}
