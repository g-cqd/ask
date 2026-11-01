internal import AemiArgon2
internal import AemiJSON
internal import CryptoKit
internal import Foundation

/// `keys.json` (ADR-0138, section 4): the user key, wrapped twice, by a key Argon2id derives from the password and by one derived from
/// the recovery code, and the derivation's parameters. Nothing in it opens anything without the password or the code. The user key, in
/// turn, seals each encrypted file's own data key (``envelope(for:userKey:)``), so changing the password rewraps one key, not every file.
struct SessionKeys: Codable, Equatable {
    static let version = 1

    let version: Int
    /// Names the user key without revealing it: the first 16 bytes of a SHA-256 over it.
    let keyID: Base64Bytes
    let derivation: KeyDerivation
    let passwordSalt: Base64Bytes
    let passwordWrap: Base64Bytes
    let recoverySalt: Base64Bytes
    let recoveryWrap: Base64Bytes

    /// A new user key under `password`, its recovery code, and the file that keeps both wraps.
    static func create(password: [UInt8], derivation: KeyDerivation = .standard) throws(SessionKeyError) -> (
        keys: SessionKeys, userKey: SymmetricKey, recoveryCode: String
    ) {
        let userKey = SymmetricKey(size: .bits256)
        var recovery = SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }
        defer { ConstantTime.wipe(&recovery) }
        let recoverySalt = Self.random(16)
        let keys = try SessionKeys(
            version: version,
            keyID: Base64Bytes(Self.identifier(of: userKey)),
            derivation: derivation,
            passwordSalt: Base64Bytes([]),
            passwordWrap: Base64Bytes([]),
            recoverySalt: Base64Bytes(recoverySalt),
            recoveryWrap: Base64Bytes(
                Self.wrap(userKey, under: Self.recoveryKey(recovery, salt: recoverySalt), purpose: .recovery)
            )
        )
        .changingPassword(userKey: userKey, to: password)
        return (keys, userKey, RecoveryCode.text(for: recovery))
    }

    func unlock(password: [UInt8]) throws(SessionKeyError) -> SymmetricKey {
        let key = try derivation.key(password: password, salt: Array(passwordSalt.data))
        guard let userKey = Self.unwrap(passwordWrap.data, under: key, purpose: .password) else { throw .wrongPassword }
        return userKey
    }

    func unlock(recoveryCode: String) throws(SessionKeyError) -> SymmetricKey {
        var recovery = try RecoveryCode.bytes(of: recoveryCode)
        defer { ConstantTime.wipe(&recovery) }
        let key = Self.recoveryKey(recovery, salt: Array(recoverySalt.data))
        guard let userKey = Self.unwrap(recoveryWrap.data, under: key, purpose: .recovery) else {
            throw .wrongRecoveryCode
        }
        return userKey
    }

    /// The same user key, the same recovery code, under a new password and a new salt.
    func changingPassword(userKey: SymmetricKey, to password: [UInt8]) throws(SessionKeyError) -> SessionKeys {
        let salt = Self.random(16)
        let wrap = try Self.wrap(userKey, under: derivation.key(password: password, salt: salt), purpose: .password)
        return SessionKeys(
            version: version,
            keyID: keyID,
            derivation: derivation,
            passwordSalt: Base64Bytes(salt),
            passwordWrap: Base64Bytes(wrap),
            recoverySalt: recoverySalt,
            recoveryWrap: recoveryWrap
        )
    }
}

/// `keys.json` on disk: in an extension, so the type keeps its memberwise initializer.
extension SessionKeys {
    /// `keys.json` as read from disk, refused when it is not one or asks for more than ask allows.
    init(decoding json: [UInt8]) throws(SessionKeyError) {
        guard let keys = try? AemiJSON.JSONDecoder().decode(SessionKeys.self, from: json), keys.version == Self.version
        else {
            throw .unreadableKeyFile
        }
        guard keys.derivation.isWithinBounds else { throw .derivationOutOfBounds }
        self = keys
    }

    func encoded() throws(SessionKeyError) -> [UInt8] {
        var encoder = AemiJSON.JSONEncoder()
        encoder.options.keyOrder = .sorted
        guard let bytes = try? encoder.encodeToBytes(self) else { throw .unreadableKeyFile }
        return bytes
    }
}
