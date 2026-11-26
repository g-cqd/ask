internal import CryptoKit

/// The Noise protocol's SymmetricState (revision 34, section 5.2) for `SHA256`: the chaining key, the handshake hash, and the
/// cipher state they key. `HKDF` here is Noise's own (section 4.3), HMAC-SHA256 chained, which is RFC 5869's with the chaining key as
/// the salt and an empty info; its outputs are 32 bytes each.
struct NoiseSymmetricState: Sendable {
    private(set) var chainingKey: [UInt8]
    private(set) var hash: [UInt8]
    private(set) var cipher = NoiseCipherState()

    /// Starts from the protocol name: as the hash when it fits 32 bytes, padded with zeros; else its SHA-256.
    init(protocolName: String) {
        let name = Array(protocolName.utf8)
        hash = name.count <= 32 ? name + [UInt8](repeating: 0, count: 32 - name.count) : Array(SHA256.hash(data: name))
        chainingKey = hash
    }

    mutating func mixKey(_ input: [UInt8]) {
        let (next, key) = Self.hkdf2(chainingKey: chainingKey, input: input)
        chainingKey = next
        cipher = NoiseCipherState(key: SymmetricKey(data: key))
    }

    mutating func mixHash(_ data: [UInt8]) { hash = Array(SHA256.hash(data: hash + data)) }

    mutating func encryptAndHash(_ plaintext: [UInt8]) throws(NoiseCipherState.Failure) -> [UInt8] {
        let ciphertext = try cipher.encrypt(plaintext, ad: hash)
        mixHash(ciphertext)
        return ciphertext
    }

    mutating func decryptAndHash(_ ciphertext: [UInt8]) throws(NoiseCipherState.Failure) -> [UInt8] {
        let plaintext = try cipher.decrypt(ciphertext, ad: hash)
        mixHash(ciphertext)
        return plaintext
    }

    /// The two transport cipher states: the initiator's sending one first.
    func split() -> (NoiseCipherState, NoiseCipherState) {
        let (first, second) = Self.hkdf2(chainingKey: chainingKey, input: [])
        return (NoiseCipherState(key: SymmetricKey(data: first)), NoiseCipherState(key: SymmetricKey(data: second)))
    }

    /// Noise's `HKDF(chaining_key, input_key_material, 2)`.
    static func hkdf2(chainingKey: [UInt8], input: [UInt8]) -> ([UInt8], [UInt8]) {
        let temporary = SymmetricKey(data: hmac(key: chainingKey, input))
        let first = Array(HMAC<SHA256>.authenticationCode(for: [0x01], using: temporary))
        let second = Array(HMAC<SHA256>.authenticationCode(for: first + [0x02], using: temporary))
        return (first, second)
    }

    private static func hmac(key: [UInt8], _ data: [UInt8]) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }
}
