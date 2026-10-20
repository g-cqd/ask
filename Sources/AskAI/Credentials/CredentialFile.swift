internal import Darwin
public import Foundation

/// Every provider's credentials in one owner-only JSON file (ADR-0018), each saved without disturbing the others.
///
/// The directory is created 0700 and the file 0600. A save writes a new file beside the old one and renames
/// it into place, so a crash leaves the old credentials or the new ones, never a mixture.
///
/// Every change is one transaction under a short lock shared by every ask process: read the file, change one record,
/// write. Without it two saves read the same file and the later erases the earlier (eight concurrent saves kept one or
/// two). A read takes no lock and writes nothing: a rename is whole, so a reader sees the old file or the new one.
public struct CredentialFile: Sendable {
    public let url: URL
    let lockWait: Duration

    /// The file at `url`, waiting up to `lockWait` for another ask's save to finish.
    public init(url: URL, lockWait: Duration = .seconds(5)) {
        self.url = url
        self.lockWait = lockWait
    }

    /// `$XDG_CONFIG_HOME/ask/credentials.json` when that is an absolute path, else
    /// `~/.config/ask/credentials.json`.
    public static func standard(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> CredentialFile {
        let configured = environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        let base = URL(fileURLWithPath: configured ?? home + "/.config", isDirectory: true)
        // @dl:accept -- Claude's and Codex's public accessors are twins over different credential types; a protocol to share them would cost more than it saves
        return CredentialFile(url: base.appending(path: "ask/credentials.json"))
    }

    /// The stored Claude credentials, or nil when there are none.
    /// - Throws: ``CredentialFileError/exposed(path:mode:)`` or ``CredentialFileError/damaged(path:)``, so a
    ///   problem is never mistaken for being signed out.
    public func loadClaude(connection: ConnectionRecord? = nil) throws(CredentialFileError) -> ClaudeCredentials? {
        try load(\.claude, connection: connection)
    }

    /// Stores Claude credentials, replacing any, and keeping every other provider's.
    /// - Throws: ``CredentialFileError/io(path:errno:)``, or ``CredentialFileError/damaged(path:)`` when the file
    ///   cannot be read, which is never overwritten.
    public func saveClaude(_ credentials: ClaudeCredentials) throws(CredentialFileError) {
        try save(\.claude, credentials)
    }

    /// Stores `credentials` only if the stored ones are still `expected`.
    /// - Returns: false when they changed or were removed meanwhile, and nothing was written.
    /// - Throws: as ``saveClaude(_:)``.
    public func saveClaude(
        _ credentials: ClaudeCredentials, ifStill expected: ClaudeCredentials, connection: ConnectionRecord? = nil
    )
        throws(CredentialFileError) -> Bool
    {
        try replace(\.claude, with: credentials, ifStill: expected, connection: connection)
    }

    /// Stores `credentials` only if the stored ones are still `expected`.
    /// - Returns: false when they changed or were removed meanwhile, and nothing was written.
    /// - Throws: as ``saveClaude(_:)``.
    public func saveCodex(
        _ credentials: CodexCredentials, ifStill expected: CodexCredentials, connection: ConnectionRecord? = nil
    )
        throws(CredentialFileError) -> Bool
    {
        try replace(\.codex, with: credentials, ifStill: expected, connection: connection)
    }

    /// The stored Codex credentials, or nil when there are none.
    /// - Throws: as ``loadClaude()``.
    public func loadCodex(connection: ConnectionRecord? = nil) throws(CredentialFileError) -> CodexCredentials? {
        try load(\.codex, connection: connection)
    }

    /// Stores Codex credentials, replacing any, whole, and keeping every other provider's.
    /// - Throws: as ``saveClaude(_:)``.
    public func saveCodex(_ credentials: CodexCredentials) throws(CredentialFileError) {
        try save(\.codex, credentials)
    }

    /// Removes Codex's credentials, keeping every other provider's. Nothing stored is not an error.
    /// - Throws: as ``saveClaude(_:)``.
    public func removeCodex() throws(CredentialFileError) {
        try clear(\.codex)
    }

    /// The key a provider's sign-in stored, or nil when there is none.
    /// - Throws: as ``loadClaude()``.
    public func loadKey(for provider: String) throws(CredentialFileError) -> StoredKey? { try read()?.keys?[provider] }

    /// Stores `key` for `provider`, replacing its previous one and keeping every other provider's credentials.
    /// - Throws: as ``saveClaude(_:)``.
    public func saveKey(_ key: StoredKey, for provider: String) throws(CredentialFileError) {
        try transact(creating: true) {
            $0.keys = ($0.keys ?? [:]).merging([provider: key]) { _, new in new }
            return ((), true)
        }
    }

    /// Removes `provider`'s key, keeping every other provider's credentials. Nothing stored is not an error.
    /// - Throws: as ``saveClaude(_:)``.
    public func removeKey(for provider: String) throws(CredentialFileError) {
        try transact(creating: false) {
            guard $0.keys?[provider] != nil else { return ((), false) }
            $0.keys?[provider] = nil
            return ((), true)
        }
    }

    /// Every stored key, by provider.
    /// - Throws: as ``loadClaude()``.
    public func loadKeys() throws(CredentialFileError) -> [String: StoredKey] { try read()?.keys ?? [:] }

    /// Removes Claude's credentials, keeping every other provider's. Nothing stored is not an error.
    /// - Throws: as ``saveClaude(_:)``.
    public func removeClaude() throws(CredentialFileError) {
        try clear(\.claude)
    }

    // MARK: - Transactions

    /// Runs one change under the save lock: read what is stored, let `change` alter it, and write it back if `change` says so.
    ///
    /// A file that cannot be read as credentials stops the transaction before `change` runs, so a damaged file is never
    /// overwritten. With `creating` false, a directory that does not exist yet is not made: there is nothing to change.
    /// `change` must not start another transaction: the lock is not reentrant.
    func transact<T>(creating: Bool, _ change: (inout StoredCredentials) -> (result: T, write: Bool))
        throws(CredentialFileError) -> T
    {
        if creating {
            try prepareDirectory()
        } else if !FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) {
            var empty = StoredCredentials()
            return change(&empty).result
        }
        let lock = try takeLock()
        defer { lock.release() }
        var stored = try read() ?? StoredCredentials()
        let outcome = change(&stored)
        if outcome.write { try write(stored) }
        return outcome.result
    }

    /// Stores `value` in the record at `record`, creating the file if there is none.
    private func save<T>(_ record: WritableKeyPath<StoredCredentials, T?>, _ value: T) throws(CredentialFileError) {
        try transact(creating: true) {
            $0[keyPath: record] = value
            return ((), true)
        }
    }

    /// Empties the record at `record`. Nothing stored is not an error, and makes nothing.
    private func clear<T>(_ record: WritableKeyPath<StoredCredentials, T?>) throws(CredentialFileError) {
        try transact(creating: false) {
            guard $0[keyPath: record] != nil else { return ((), false) }
            $0[keyPath: record] = nil
            return ((), true)
        }
    }

    /// Replaces the record at `record` only while it is still `expected`; false, and nothing written, when it is not.
    private func replace<T: Equatable>(
        _ record: WritableKeyPath<StoredCredentials, T?>, with value: T, ifStill expected: T,
        connection: ConnectionRecord?
    )
        throws(CredentialFileError) -> Bool
    {
        try transact(creating: false) { stored in
            guard matches(connection, stored), stored[keyPath: record] == expected else { return (false, false) }
            stored[keyPath: record] = value
            return (true, true)
        }
    }

    private func takeLock() throws(CredentialFileError) -> CredentialLock {
        do { return try CredentialLock.acquireBlocking(beside: url, wait: lockWait, name: "write") } catch {
            switch error {
                case .timedOut, .cancelled: throw .locked(path: CredentialLock.path(beside: url, name: "write"))
                case .io(let failure): throw failure
            }
        }
    }

    /// Makes the 0700 directory the file and its locks live in.
    private func prepareDirectory() throws(CredentialFileError) {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .io(path: directory.deletingLastPathComponent().path, errno: EACCES)
        }
        if mkdir(directory.path, 0o700) != 0, errno != EEXIST { throw .io(path: directory.path, errno: errno) }
    }

    // MARK: - The file

    /// What the file holds, or nil when there is no file.
    func read() throws(CredentialFileError) -> StoredCredentials? {
        var status = stat()
        guard stat(url.path, &status) == 0 else {
            if errno == ENOENT { return nil }
            throw .io(path: url.path, errno: errno)
        }
        let mode = Int(status.st_mode) & 0o777
        guard mode & 0o077 == 0 else { throw .exposed(path: url.path, mode: mode) }
        guard let bytes = try? Data(contentsOf: url) else { throw .io(path: url.path, errno: errno) }
        do { return try StoredCredentials(decoding: [UInt8](bytes)) } catch StoredCredentials.FormatError.newerVersion {
            throw .newerFormat(path: url.path)
        } catch { throw .damaged(path: url.path) }
    }

    /// Writes `stored` as a new owner-only file and renames it into place, so a crash leaves the old file or the new.
    private func write(_ stored: StoredCredentials) throws(CredentialFileError) {
        let directory = url.deletingLastPathComponent()
        guard let bytes = try? stored.encoded() else { throw .damaged(path: url.path) }
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
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { return }
        let lock = try takeLock()
        defer { lock.release() }
        guard unlink(url.path) == 0 || errno == ENOENT else { throw .io(path: url.path, errno: errno) }
    }
}
