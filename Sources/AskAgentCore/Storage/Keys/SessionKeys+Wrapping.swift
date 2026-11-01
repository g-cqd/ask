internal import CryptoKit
internal import Foundation

/// Sealing keys under keys: AES-256-GCM, each seal bound to what it is for, so a wrap cannot be used as another.
extension SessionKeys {
    enum Purpose: String {
        case password = "ask.user-key.password.v1"
        case recovery = "ask.user-key.recovery.v1"
        case dataKey = "ask.data-key.v1"
    }

    /// An envelope for an encrypted file's header: the user key's identifier, then `dataKey` sealed under the user key.
    func envelope(for dataKey: SymmetricKey, userKey: SymmetricKey) throws(SessionKeyError) -> [UInt8] {
        Array(keyID.data) + (try Self.wrap(dataKey, under: userKey, purpose: .dataKey))
    }

    /// The data key in `envelope`.
    func dataKey(in envelope: [UInt8], userKey: SymmetricKey) throws(SessionKeyError) -> SymmetricKey {
        guard envelope.count == 16 + 12 + 32 + 16 else { throw .damagedEnvelope }
        guard Data(envelope.prefix(16)) == keyID.data, Self.identifier(of: userKey) == Array(keyID.data) else {
            throw .otherUserKey
        }
        guard let key = Self.unwrap(Data(envelope.dropFirst(16)), under: userKey, purpose: .dataKey) else {
            throw .damagedEnvelope
        }
        return key
    }

    static func wrap(_ key: SymmetricKey, under wrapping: SymmetricKey, purpose: Purpose) throws(SessionKeyError)
        -> [UInt8]
    {
        let sealed = key.withUnsafeBytes { bytes in
            try? AES.GCM.seal(Data(bytes), using: wrapping, authenticating: Data(purpose.rawValue.utf8))
        }
        guard let combined = sealed?.combined else { throw .damagedEnvelope }
        return Array(combined)
    }

    static func unwrap(_ wrapped: Data, under wrapping: SymmetricKey, purpose: Purpose) -> SymmetricKey? {
        guard let box = try? AES.GCM.SealedBox(combined: wrapped),
            let opened = try? AES.GCM.open(box, using: wrapping, authenticating: Data(purpose.rawValue.utf8)),
            opened.count == 32
        else { return nil }
        return SymmetricKey(data: opened)
    }

    /// The recovery code's own 256 bits need no slow derivation: HKDF binds them to their salt and purpose.
    static func recoveryKey(_ recovery: [UInt8], salt: [UInt8]) -> SymmetricKey {
        HKDF<SHA256>
            .deriveKey(
                inputKeyMaterial: SymmetricKey(data: recovery),
                salt: salt,
                info: Data(Purpose.recovery.rawValue.utf8),
                outputByteCount: 32
            )
    }

    static func identifier(of userKey: SymmetricKey) -> [UInt8] {
        let digest = userKey.withUnsafeBytes { SHA256.hash(data: Data("ask.key-id.v1".utf8) + Data($0)) }
        return Array(digest.prefix(16))
    }

    static func random(_ count: Int) -> [UInt8] {
        SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Array($0) }
    }
}
