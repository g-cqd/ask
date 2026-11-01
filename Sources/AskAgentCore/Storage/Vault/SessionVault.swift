internal import AemiArgon2
internal import AemiJSON
public import AskAI
internal import Darwin
internal import Foundation

/// The keys of encrypted sessions as ask keeps them (ADR-0138): `keys.json` and the first-start answer in the state directory, private
/// to the person (0600 in a 0700 directory), and the user key in the keychain when the password is remembered.
public struct SessionVault: Sendable {
    public let stateRoot: String
    let derivation: KeyDerivation

    public init(stateRoot: String) {
        self.init(stateRoot: stateRoot, derivation: .standard)
    }

    init(stateRoot: String, derivation: KeyDerivation) {
        self.stateRoot = stateRoot
        self.derivation = derivation
    }

    public var keysPath: String { stateRoot + "/keys.json" }
    var choicePath: String { stateRoot + "/session-encryption.json" }
    public var hasKeys: Bool { FileManager.default.fileExists(atPath: keysPath) }

    /// New keys under `password`: the keyring, and the recovery code to show once.
    public func create(password: String) throws -> (keyring: SessionKeyring, recoveryCode: String) {
        guard !hasKeys else { throw SessionVaultError.keysExist }
        var secret = Array(password.utf8)
        defer { ConstantTime.wipe(&secret) }
        let made = try SessionKeys.create(password: secret, derivation: derivation)
        try write(try made.keys.encoded(), to: keysPath)
        return (SessionKeyring(keys: made.keys, userKey: made.userKey), made.recoveryCode)
    }

    public func unlock(password: String) throws -> SessionKeyring {
        let keys = try storedKeys()
        var secret = Array(password.utf8)
        defer { ConstantTime.wipe(&secret) }
        return SessionKeyring(keys: keys, userKey: try keys.unlock(password: secret))
    }

    public func unlock(recoveryCode: String) throws -> SessionKeyring {
        let keys = try storedKeys()
        return SessionKeyring(keys: keys, userKey: try keys.unlock(recoveryCode: recoveryCode))
    }

    public func changePassword(_ keyring: SessionKeyring, to password: String) throws {
        var secret = Array(password.utf8)
        defer { ConstantTime.wipe(&secret) }
        let changed = try keyring.keys.changingPassword(userKey: keyring.userKey, to: secret)
        try write(try changed.encoded(), to: keysPath)
    }

    /// The keyring from the keychain, when the user key kept there belongs to this `keys.json`.
    public func remembered(in store: any SecretStore) -> SessionKeyring? {
        guard let keys = try? storedKeys(),
            let key = try? RememberedSessionKey.recall(keyID: keys.keyID.data, from: store)
        else { return nil }
        return SessionKeyring(keys: keys, userKey: key)
    }

    public func remember(_ keyring: SessionKeyring, in store: any SecretStore) throws {
        try RememberedSessionKey.remember(keyring.userKey, in: store)
    }

    public func forget(in store: any SecretStore) throws {
        try RememberedSessionKey.forget(in: store)
    }

    /// The first-start answer, nil until it is given.
    public func choice() -> SessionEncryptionChoice? {
        guard let data = FileManager.default.contents(atPath: choicePath) else { return nil }
        return try? AemiJSON.JSONDecoder().decode(SessionEncryptionChoice.self, from: Array(data))
    }

    public func record(_ choice: SessionEncryptionChoice) throws {
        try write(try AemiJSON.JSONEncoder().encodeToBytes(choice), to: choicePath)
    }

    private func storedKeys() throws -> SessionKeys {
        guard let data = FileManager.default.contents(atPath: keysPath) else { throw SessionVaultError.noKeys }
        return try SessionKeys(decoding: Array(data))
    }

    /// `bytes` at `path`, private, replacing it whole or not at all: written beside it, flushed, then renamed over it.
    private func write(_ bytes: [UInt8], to path: String) throws {
        do {
            try FileManager.default.createDirectory(
                atPath: stateRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw SessionVaultError.write(errno: EACCES)
        }
        let temporary = path + ".tmp"
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw SessionVaultError.write(errno: errno) }
        let written = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        let flushed = fsync(descriptor)
        close(descriptor)
        guard written == bytes.count, flushed == 0, rename(temporary, path) == 0 else {
            let failure = errno
            unlink(temporary)
            throw SessionVaultError.write(errno: failure)
        }
    }
}
