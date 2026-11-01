internal import AemiArgon2
internal import CryptoKit

/// How a password becomes the key that wraps the user key: Argon2id (aemi's AemiArgon2, ADR-0138), its parameters stored in `keys.json`
/// and bounded when read, so a changed file cannot make ask take gigabytes or minutes.
struct KeyDerivation: Codable, Equatable {
    let memoryKiB: Int
    let passes: Int
    let lanes: Int

    /// OWASP's Argon2id minimum, 19 MiB and 2 passes, on 4 lanes that run on 4 threads: about 4 ms on an M3. Its memory is wiped and
    /// released as soon as the key is made.
    static let standard = KeyDerivation(memoryKiB: 19 * 1024, passes: 2, lanes: 4)

    /// Whether the parameters are within what ask accepts from a file: at most 256 MiB, 10 passes and 16 lanes, and at least what
    /// RFC 9106 requires.
    var isWithinBounds: Bool {
        (1 ... 16).contains(lanes) && (1 ... 10).contains(passes) && (8 * lanes ... 256 * 1024).contains(memoryKiB)
    }

    /// The 256-bit key `password` and `salt` derive.
    func key(password: [UInt8], salt: [UInt8]) throws(SessionKeyError) -> SymmetricKey {
        guard isWithinBounds else { throw .derivationOutOfBounds }
        do {
            let parameters = try Argon2.Parameters(
                variant: .id,
                memoryKiB: memoryKiB,
                passes: passes,
                lanes: lanes,
                tagLength: 32
            )
            var tag = try Argon2.hash(password: password, salt: salt, parameters: parameters, threads: lanes)
            defer { ConstantTime.wipe(&tag) }
            return SymmetricKey(data: tag)
        } catch {
            throw .derivationOutOfBounds
        }
    }
}
