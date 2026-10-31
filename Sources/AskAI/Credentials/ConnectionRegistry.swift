public import Foundation

/// Named subscription registrations in stable-id directories, isolated from the legacy default credential file.
/// Metadata and credentials commit together; registration and rename serialize name allocation across processes.
public struct ConnectionRegistry: Sendable {
    public let directory: URL
    private let lockWait: Duration

    /// The directory containing registration directories; no files are created by initialization or reading.
    public init(directory: URL, lockWait: Duration = .seconds(5)) {
        self.directory = directory
        self.lockWait = lockWait
    }

    /// Every intact registration, with unreadable records reported separately.
    public func list() throws -> ConnectionListing {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ConnectionListing(records: [], notices: [])
        }
        var records: [ConnectionRecord] = []
        var notices: [String] = []
        for path in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() {
            guard let id = UUID(uuidString: path) else { continue }
            let url = directory.appending(path: path).appending(path: "credentials.json")
            let file = CredentialFile.preferred(url: url)
            do {
                guard let record = try file.read()?.connection, record.id == id,
                    ConnectionRecord.canonical(record.name) == record.name
                else {
                    notices.append("Unreadable connection registration at \(file.url.path).")
                    continue
                }
                if !record.removed { records.append(record) }
            } catch { notices.append("Connection registration not loaded: \(error)") }
        }
        let grouped = Dictionary(grouping: records, by: \.name)
        let duplicates = Set(grouped.filter { $0.value.count > 1 }.keys)
        for name in duplicates.sorted() {
            notices.append("Ambiguous connection name '\(name)'; neither registration was selected.")
        }
        return ConnectionListing(
            records: records.filter { !duplicates.contains($0.name) }.sorted { $0.name < $1.name }, notices: notices)
    }

    /// Creates a signed-out registration, or returns the same-provider registration already named `name`.
    /// - Parameters:
    ///   - name: case-insensitive local CLI name.
    ///   - provider: subscription behavior, not a separate implementation.
    ///   - reserved: configured destination names that must not be shadowed.
    /// - Returns: the stable registration, without starting authentication.
    /// - Throws: a registration, file, or lock error; no credentials are changed.
    public func register(name: String, provider: ConnectionKind, reserved: [String] = []) throws -> ConnectionRecord {
        let name = try availableName(name, reserved: reserved)
        return try locked {
            let listing = try list()
            guard listing.notices.isEmpty else {
                throw ConnectionError.unreadableRegistry(listing.notices.joined(separator: " "))
            }
            if let existing = listing.records.first(where: { $0.name == name }) {
                guard existing.provider == provider else { throw ConnectionError.nameInUse(name) }
                return existing
            }
            let record = ConnectionRecord(name: name, provider: provider)
            try credentials(for: record)
                .transact(creating: true) {
                    $0.connection = record
                    return ((), true)
                }
            return record
        }
    }

    /// The stable-id credential store for this registration, unaffected by a rename.
    public func credentials(for record: ConnectionRecord) -> CredentialFile {
        credentials(
            for: record, choice: CredentialStorage.chosen, stablySigned: CredentialStorage.runningBuildIsStablySigned,
            keychain: try? KeychainSecretStore())
    }

    /// The registration's file with its secrets where `choice` puts them, as ask's own file (roadmap 0110).
    func credentials(
        for record: ConnectionRecord, choice: CredentialStorage, stablySigned: Bool, keychain: (any SecretStore)?
    ) -> CredentialFile {
        CredentialFile.preferred(
            url: directory.appending(path: record.id.uuidString.lowercased()).appending(path: "credentials.json"),
            choice: choice, stablySigned: stablySigned, keychain: keychain)
    }

    /// The alias file in this registration's own folder, which a rename does not move.
    public func aliases(for record: ConnectionRecord) -> ModelAliasFile {
        ModelAliasFile(
            url: directory.appending(path: record.id.uuidString.lowercased()).appending(path: "aliases.json"))
    }

    /// Renames a registration, retaining its id, credentials, authorization identity and cache location.
    public func rename(_ record: ConnectionRecord, to name: String, reserved: [String] = []) throws {
        let name = try availableName(name, reserved: reserved)
        try locked {
            let listing = try list()
            guard listing.notices.isEmpty else {
                throw ConnectionError.unreadableRegistry(listing.notices.joined(separator: " "))
            }
            guard !listing.records.contains(where: { $0.name == name && $0.id != record.id }) else {
                throw ConnectionError.nameInUse(name)
            }
            try mutate(record) { current, _ in current.name = name }
        }
    }

    /// Removes authentication but keeps the named registration; a pending sign-in cannot restore it.
    public func signOut(_ record: ConnectionRecord) throws { try clear(record, removing: false) }

    /// Marks a registration removed and clears credentials. Its stable id is never reused by another name.
    public func remove(_ record: ConnectionRecord) throws { try clear(record, removing: true) }

    /// Commits a new Codex grant only while registration still matches; a changed remote account needs consent.
    public func saveCodex(_ credentials: CodexCredentials, for record: ConnectionRecord, replaceAccount: Bool = false)
        throws
    {
        guard record.provider == .codex else { throw ConnectionError.changed(record.name) }
        try install(record, identity: credentials.accountID, replaceAccount: replaceAccount) { $0.codex = credentials }
    }

    /// Commits a new Claude grant only while registration still matches; a changed or unknown account needs consent.
    public func saveClaude(_ credentials: ClaudeCredentials, for record: ConnectionRecord, replaceAccount: Bool = false)
        throws
    {
        guard record.provider == .anthropic else { throw ConnectionError.changed(record.name) }
        try install(record, identity: credentials.accountEmail, replaceAccount: replaceAccount) {
            $0.claude = credentials
        }
    }

    private func availableName(_ raw: String, reserved: [String]) throws -> String {
        guard let name = ConnectionRecord.canonical(raw) else { throw ConnectionError.invalidName }
        let builtins =
            ["claude", ProviderSettings.anthropic, ProviderSettings.codex, ProviderSettings.agy, ProviderSettings.apple]
            + ProviderPreset.all.map(\.name)
        guard !(builtins + reserved).contains(where: { $0.lowercased() == name }) else {
            throw ConnectionError.nameInUse(name)
        }
        return name
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = directory.appending(path: ".registry")
        let lock: CredentialLock
        do { lock = try CredentialLock.acquireBlocking(beside: path, wait: lockWait, name: "") } catch CredentialLock
            .Failure.io(let error)
        { throw error } catch { throw CredentialFileError.locked(path: CredentialLock.path(beside: path, name: "")) }
        defer { lock.release() }
        return try body()
    }

    private func clear(_ record: ConnectionRecord, removing: Bool) throws {
        try locked {
            try mutate(record) { current, stored in
                current.authorizationID = UUID()
                current.removed = removing
                if removing { current.accountIdentity = nil }
                // Every secret in this profile is removed, including records an older writer does not understand.
                // Catalogs and future model registrations live beside the credential file, not inside it.
                stored = StoredCredentials()
            }
        }
    }

    private func mutate(_ record: ConnectionRecord, _ change: (inout ConnectionRecord, inout StoredCredentials) -> Void)
        throws
    {
        let changed = try credentials(for: record)
            .transact(creating: false) { stored in
                guard var current = stored.connection, current.id == record.id, !current.removed else {
                    return (false, false)
                }
                change(&current, &stored)
                stored.connection = current
                return (true, true)
            }
        guard changed else { throw ConnectionError.changed(record.name) }
    }

    private func install(
        _ record: ConnectionRecord, identity: String?, replaceAccount: Bool, _ grant: (inout StoredCredentials) -> Void
    ) throws {
        try locked {
            let error: ConnectionError? = try credentials(for: record)
                .transact(creating: false) { stored in
                    guard var current = stored.connection, current.id == record.id, !current.removed,
                        current.authorizationID == record.authorizationID, current.provider == record.provider
                    else { return (.changed(record.name), false) }
                    let changesAccount =
                        current.authenticatedBefore && (identity == nil || current.accountIdentity != identity)
                    guard !changesAccount || replaceAccount else { return (.replacementRequired(current.name), false) }
                    if changesAccount { current.authorizationID = UUID() }
                    current.accountIdentity = identity
                    current.authenticatedBefore = true
                    stored.connection = current
                    grant(&stored)
                    return (nil, true)
                }
            if let error { throw error }
        }
    }
}
