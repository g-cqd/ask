internal import Darwin
public import Foundation

/// Writing, removing, and the keys and tokens kept in a secret store, the Keychain, instead of the file (roadmap 0110): a write puts
/// them there first, reading puts them back, and settling moves them to where the file's mode says they belong.
extension CredentialFile {
    /// The file at `url`, its secrets where the process's choice of store puts them (``CredentialStorage``): the Keychain, or the file.
    public static func preferred(url: URL) -> CredentialFile {
        preferred(
            url: url, choice: CredentialStorage.chosen, stablySigned: CredentialStorage.runningBuildIsStablySigned,
            keychain: try? KeychainSecretStore())
    }

    /// The file at `url` with `keychain` as its store when `choice` says so. `auto` in an unsigned build still uses the Keychain for
    /// a file that already keeps its secrets there, so such a build never pulls them back into the file.
    static func preferred(
        url: URL, choice: CredentialStorage, stablySigned: Bool, keychain: (any SecretStore)?
    ) -> CredentialFile {
        var uses = choice.usesKeychain(stablySigned: stablySigned)
        if !uses, choice == .auto, let marked = try? CredentialFile(url: url).readFile()?.markedRecords {
            uses = !marked.isEmpty
        }
        // @dl:accept -- the factory ends where the twin per-provider accessors begin; those twins are accepted above
        return CredentialFile(url: url, secrets: uses ? keychain : nil, vault: keychain)
    }

    /// What the file holds, secrets put back from the secret store, and the records whose secrets were there.
    func readMarked() throws(CredentialFileError) -> (stored: StoredCredentials?, marked: Set<String>) {
        guard var stored = try readFile() else { return (nil, []) }
        let marked = stored.markedRecords
        guard !marked.isEmpty else { return (stored, []) }
        let source = try reader()
        for name in marked.sorted() {
            let found: [String: String]?
            do { found = try source.secrets(for: account(name)) } catch {
                throw .secretStore(path: url.path, status: Self.status(error))
            }
            guard let found else { throw .secretMissing(path: url.path, record: name) }
            stored.setSecrets(found, of: name)
        }
        return (stored, marked)
    }

    /// Moves every secret to where the file's mode says it belongs: into the secret store, or back into the file.
    /// - Throws: what a read or a write throws; nothing is moved when there is nothing to move.
    public func settleSecrets() throws(CredentialFileError) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let lock = try takeLock()
        defer { lock.release() }
        let (found, marked) = try readMarked()
        guard let stored = found else { return }
        let moving = secrets == nil ? !marked.isEmpty : !stored.inlineRecords.isEmpty
        if moving { try write(stored, marked: marked) }
    }

    /// The secret store's name for record `name` of this file.
    func account(_ name: String) -> String { url.path + "#" + name }

    /// Where marked secrets are read and removed: the store in use, else the vault, else the Keychain.
    func reader() throws(CredentialFileError) -> any SecretStore {
        if let secrets { return secrets }
        if let vault { return vault }
        return try keychain()
    }

    /// The Keychain, for a file that marks secrets as kept there.
    private func keychain() throws(CredentialFileError) -> any SecretStore {
        do { return try KeychainSecretStore() } catch { throw .secretStore(path: url.path, status: Self.status(error)) }
    }

    static func status(_ error: any Error) -> Int32 {
        if case SecretStoreError.failed(let status) = error { return status }
        return -1
    }

    /// Writes `stored` as a new owner-only file and renames it into place, so a crash leaves the old file or the new. With a secret
    /// store, every secret goes there first, read back to check it, and the file gets a marker in its place; a store that refuses
    /// leaves the file as it was. Items no longer needed (a record removed, or every secret back in the file) go after the file.
    func write(_ stored: StoredCredentials, removing removed: Set<String> = [], marked: Set<String> = [])
        throws(CredentialFileError)
    {
        var shown = stored
        if let secrets {
            for name in stored.recordNames {
                guard let fields = stored.secrets(of: name) else { continue }
                do {
                    try secrets.store(fields, for: account(name))
                    guard try secrets.secrets(for: account(name)) == fields else { throw SecretStoreError.unreadable }
                } catch { throw .secretStore(path: url.path, status: Self.status(error)) }
                shown.setSecrets(fields.mapValues { _ in StoredCredentials.marker }, of: name)
            }
        }
        guard let bytes = try? shown.encoded() else { throw .damaged(path: url.path) }
        do { try AtomicFile.replace(url, with: bytes) } catch { throw .io(path: url.path, errno: error.code) }
        let stale = secrets == nil ? marked.union(removed.intersection(marked)) : removed
        guard !stale.isEmpty, let store = try? reader() else { return }
        for name in stale { try? store.remove(account: account(name)) }
    }

    /// Deletes the whole file, every provider's credentials. Nothing stored is not an error.
    /// - Throws: ``CredentialFileError/io(path:errno:)``.
    public func remove() throws(CredentialFileError) {
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { return }
        let lock = try takeLock()
        defer { lock.release() }
        let names = (try? readFile())?.map { $0.recordNames } ?? []
        guard unlink(url.path) == 0 || errno == ENOENT else { throw .io(path: url.path, errno: errno) }
        guard !names.isEmpty, let store = try? reader() else { return }
        for name in names { try? store.remove(account: account(name)) }
    }
}
