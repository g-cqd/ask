internal import CryptoKit
internal import Foundation

/// The Noise protocol's CipherState (revision 34, section 5.1) for `ChaChaPoly`: a key, once there is one, and the nonce that counts
/// the messages sealed with it. Each message is sealed with ChaCha20-Poly1305 under the nonce `n`, written as 32 bits of zeros and
/// then 64 bits little-endian (section 12.3), and the nonce goes up by one; the last value, 2⁶⁴−1, is never used.
package struct NoiseCipherState: Sendable {
    /// Why a cipher state refused a message.
    package enum Failure: Error, Equatable {
        /// The nonce would be 2⁶⁴−1: the channel must end before it.
        case nonceExhausted
        /// The message did not open: wrong key, wrong associated data, or changed in transit.
        case authenticationFailed
    }

    private(set) var key: SymmetricKey?
    private(set) var nonce: UInt64 = 0

    init(key: SymmetricKey? = nil) { self.key = key }

    var hasKey: Bool { key != nil }

    /// `plaintext` sealed with `ad` as associated data; returned as it is while there is no key.
    mutating func encrypt(_ plaintext: [UInt8], ad: [UInt8]) throws(Failure) -> [UInt8] {
        guard let key else { return plaintext }
        guard nonce < .max else { throw .nonceExhausted }
        let sealed: ChaChaPoly.SealedBox
        do {
            sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: try Self.nonce(nonce), authenticating: ad)
        } catch {
            throw .authenticationFailed
        }
        nonce += 1
        return Array(sealed.ciphertext) + Array(sealed.tag)
    }

    /// `ciphertext` opened with `ad` as associated data; returned as it is while there is no key. The nonce goes up only for a
    /// message that opens, so a forged one leaves the channel where it was.
    mutating func decrypt(_ ciphertext: [UInt8], ad: [UInt8]) throws(Failure) -> [UInt8] {
        guard let key else { return ciphertext }
        guard nonce < .max else { throw .nonceExhausted }
        guard ciphertext.count >= 16 else { throw .authenticationFailed }
        let opened: Data
        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: try Self.nonce(nonce),
                ciphertext: ciphertext.dropLast(16),
                tag: ciphertext.suffix(16)
            )
            opened = try ChaChaPoly.open(box, using: key, authenticating: ad)
        } catch {
            throw .authenticationFailed
        }
        nonce += 1
        return Array(opened)
    }

    /// The nonce as ChaChaPoly takes it: 4 bytes of zeros, then `n` little-endian. Twelve bytes are always a valid nonce; it throws
    /// only in name, inside the callers' own error handling.
    private static func nonce(_ n: UInt64) throws -> ChaChaPoly.Nonce {
        var bytes = [UInt8](repeating: 0, count: 12)
        for index in 0 ..< 8 { bytes[4 + index] = UInt8(truncatingIfNeeded: n >> (8 * UInt64(index))) }
        return try ChaChaPoly.Nonce(data: bytes)
    }
}
