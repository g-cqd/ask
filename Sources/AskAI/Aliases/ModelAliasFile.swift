internal import AemiJSON
public import Foundation

/// A connection's alias file: owner-only, replaced whole, and changed under a lock so two asks cannot lose each other's edit.
public struct ModelAliasFile: Sendable {
    /// Where the aliases live.
    public let url: URL
    let lockWait: Duration

    /// The most bytes a file may hold; far more than 64 aliases need, so a hostile file cannot be read into memory whole.
    static let byteLimit = 1 << 20

    /// The file at `url`, waiting up to `lockWait` for another ask's change.
    public init(url: URL, lockWait: Duration = .seconds(5)) {
        self.url = url
        self.lockWait = lockWait
    }

    /// The aliases; none when there is no file. Reading never writes.
    /// - Throws: ``ModelAliasError/damaged(path:)`` or ``ModelAliasError/newerFormat(path:)``.
    public func load() throws(ModelAliasError) -> ModelAliases {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
        guard let size, size <= Self.byteLimit, let data = FileManager.default.contents(atPath: url.path) else {
            throw .damaged(path: url.path)
        }
        let bytes = [UInt8](data)
        guard let document = try? AemiJSON.parse(bytes), document.root.isObject else { throw .damaged(path: url.path) }
        if let version = document.root["version"].int, version > ModelAliases.formatVersion {
            throw .newerFormat(path: url.path)
        }
        guard let aliases = try? AemiJSON.JSONDecoder().decode(ModelAliases.self, from: document), aliases.isValid
        else {
            throw .damaged(path: url.path)
        }
        return aliases
    }

    /// Adds or replaces an alias, in one transaction.
    /// - Parameters:
    ///   - name: the alias.
    ///   - model: the server's model id.
    ///   - contextWindow: a window the user states, or nil.
    ///   - maxOutputTokens: a reply limit the user states, or nil.
    ///   - thinking: a thinking level for this alias, or nil.
    ///   - known: the model ids this account lists, when known.
    /// - Throws: a ``ModelAliasError``; a damaged file is never overwritten.
    public func set(
        _ name: String, to model: String, contextWindow: Int? = nil, maxOutputTokens: Int? = nil,
        thinking: ThinkingLevel? = nil, known: [String] = []
    ) throws(ModelAliasError) {
        try update(creating: true) { (aliases: inout ModelAliases) throws(ModelAliasError) in
            try aliases.set(
                name, to: model, contextWindow: contextWindow, maxOutputTokens: maxOutputTokens, thinking: thinking,
                known: known)
        }
    }

    /// Removes an alias, in one transaction.
    /// - Parameter name: the alias.
    /// - Throws: a ``ModelAliasError``.
    public func remove(_ name: String) throws(ModelAliasError) {
        try update(creating: false) { (aliases: inout ModelAliases) throws(ModelAliasError) in try aliases.remove(name)
        }
    }

    /// Sets, or with nil clears, the default model, in one transaction.
    /// - Parameter model: an alias or a server id.
    /// - Throws: a ``ModelAliasError``.
    public func setDefault(_ model: String?) throws(ModelAliasError) {
        try update(creating: model != nil) { (aliases: inout ModelAliases) throws(ModelAliasError) in
            try aliases.setDefault(model)
        }
    }

    /// Changes the aliases under the lock, and saves them if `change` altered them. With `creating` false, a folder that
    /// does not exist yet is not made: there is nothing to change.
    func update(creating: Bool, _ change: (inout ModelAliases) throws(ModelAliasError) -> Void) throws(ModelAliasError)
    {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            // Nothing to change in a folder that is not there; and a first write makes the folder, then locks it like any other.
            guard creating else {
                var empty = ModelAliases.empty
                try change(&empty)
                return
            }
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } catch { throw .io(path: directory.path, errno: EACCES) }
        }
        let lock = try take()
        defer { lock.release() }
        let before = try load()
        var after = before
        try change(&after)
        // @dl:accept -- mapping this lock failure to this type's own error is not shared with credential saves, whose error type differs
        if after != before { try save(after) }
    }

    private func take() throws(ModelAliasError) -> CredentialLock {
        do { return try CredentialLock.acquireBlocking(beside: url, wait: lockWait, name: "aliases") } catch {
            switch error {
                case .timedOut, .cancelled: throw .locked(path: CredentialLock.path(beside: url, name: "aliases"))
                case .io(.io(let path, let code)): throw .io(path: path, errno: code)
                case .io: throw .io(path: url.path, errno: EIO)
            }
        }
    }

    private func save(_ aliases: ModelAliases) throws(ModelAliasError) {
        var encoder = AemiJSON.JSONEncoder()
        encoder.options.keyOrder = .sorted
        guard let bytes = try? encoder.encodeToBytes(aliases), bytes.count <= Self.byteLimit else {
            throw .damaged(path: url.path)
        }
        do { try AtomicFile.replace(url, with: bytes) } catch { throw .io(path: url.path, errno: error.code) }
    }
}
