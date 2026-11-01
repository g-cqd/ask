import CryptoKit
import Foundation
import Testing

@testable import AskAgentCore

/// The keys of ADR-0138, section 4: one user key, wrapped by the password (Argon2id) and by a recovery code, opening every file's data
/// key; nothing secret in `keys.json`.
@Suite
struct SessionKeysTests {
    /// Small enough to keep the tests fast; ``KeyDerivation/standard`` is tested on its own.
    static let quick = KeyDerivation(memoryKiB: 64, passes: 1, lanes: 2)
    static let password = Array("correct horse battery staple".utf8)

    @Test
    func `the password and the recovery code both open the user key, and nothing else does`() throws {
        let made = try SessionKeys.create(password: Self.password, derivation: Self.quick)
        #expect(try made.keys.unlock(password: Self.password) == made.userKey)
        #expect(try made.keys.unlock(recoveryCode: made.recoveryCode) == made.userKey)
        #expect(throws: SessionKeyError.wrongPassword) {
            _ = try made.keys.unlock(password: Array("correct horse".utf8))
        }
        let other = try SessionKeys.create(password: Self.password, derivation: Self.quick)
        #expect(throws: SessionKeyError.wrongRecoveryCode) {
            _ = try made.keys.unlock(recoveryCode: other.recoveryCode)
        }
    }

    @Test
    func `a recovery code is read however it is typed, and a wrong character is caught`() throws {
        let made = try SessionKeys.create(password: Self.password, derivation: Self.quick)
        let code = made.recoveryCode
        #expect(code.split(separator: "-").count == 13)
        let retyped = code.lowercased().replacingOccurrences(of: "-", with: " ")
        #expect(try made.keys.unlock(recoveryCode: retyped) == made.userKey)
        var typo = Array(code)
        typo[0] = typo[0] == "A" ? "B" : "A"
        #expect(throws: SessionKeyError.wrongRecoveryCode) { _ = try made.keys.unlock(recoveryCode: String(typo)) }
        #expect(throws: SessionKeyError.unreadableRecoveryCode) { _ = try made.keys.unlock(recoveryCode: "not a code") }
    }

    @Test
    func `changing the password keeps the user key and the recovery code`() throws {
        let made = try SessionKeys.create(password: Self.password, derivation: Self.quick)
        let changed = try made.keys.changingPassword(userKey: made.userKey, to: Array("another one".utf8))
        #expect(throws: SessionKeyError.wrongPassword) { _ = try changed.unlock(password: Self.password) }
        #expect(try changed.unlock(password: Array("another one".utf8)) == made.userKey)
        #expect(try changed.unlock(recoveryCode: made.recoveryCode) == made.userKey)
        #expect(changed.passwordSalt != made.keys.passwordSalt)
    }

    @Test
    func `a keys.json of another version is refused`() throws {
        let made = try SessionKeys.create(password: Self.password, derivation: Self.quick)
        let text = String(decoding: try made.keys.encoded(), as: UTF8.self)
            .replacingOccurrences(of: #""version":1"#, with: #""version":2"#)
        #expect(throws: SessionKeyError.unreadableKeyFile) { _ = try SessionKeys(decoding: Array(text.utf8)) }
    }

    @Test
    func `a key sealed for one purpose does not open as another`() throws {
        let wrapping = SymmetricKey(size: .bits256)
        let key = SymmetricKey(size: .bits256)
        let sealed = Data(try SessionKeys.wrap(key, under: wrapping, purpose: .dataKey))
        #expect(SessionKeys.unwrap(sealed, under: wrapping, purpose: .dataKey) == key)
        #expect(SessionKeys.unwrap(sealed, under: wrapping, purpose: .password) == nil)
        #expect(SessionKeys.unwrap(sealed, under: wrapping, purpose: .recovery) == nil)
    }

    @Test
    func `keys.json round-trips and holds no secret`() throws {
        let made = try SessionKeys.create(password: Self.password, derivation: Self.quick)
        let json = try made.keys.encoded()
        let text = String(decoding: json, as: UTF8.self)
        #expect(!text.contains("correct horse"))
        #expect(!text.contains(made.userKey.withUnsafeBytes { Data($0).base64EncodedString() }))
        #expect(!text.contains(made.recoveryCode))
        let read = try SessionKeys(decoding: json)
        #expect(try read.unlock(password: Self.password) == made.userKey)
    }

    /// Each case breaks one bound only: 32 lanes come with 32 MiB, within the memory bound, so the lane bound alone refuses them.
    @Test(arguments: [
        ["memoryKiB": 1 << 30], ["passes": 1000], ["passes": 0], ["memoryKiB": 4],
        ["lanes": 32, "memoryKiB": 32 * 1024],
        ["lanes": 0]
    ])
    func `derivation parameters out of bounds are refused before any memory is taken`(tampered: [String: Int]) throws {
        let made = try SessionKeys.create(password: Self.password, derivation: Self.quick)
        var text = String(decoding: try made.keys.encoded(), as: UTF8.self)
        for (field, value) in tampered {
            text = text.replacingOccurrences(
                of: #""\#(field)":\d+"#,
                with: #""\#(field)":\#(value)"#,
                options: .regularExpression
            )
        }
        #expect(throws: SessionKeyError.derivationOutOfBounds) { _ = try SessionKeys(decoding: Array(text.utf8)) }
    }

    @Test
    func `the standard derivation is Argon2id at 19 MiB, 2 passes and 4 lanes`() throws {
        #expect(KeyDerivation.standard == KeyDerivation(memoryKiB: 19 * 1024, passes: 2, lanes: 4))
        let made = try SessionKeys.create(password: Self.password, derivation: .standard)
        #expect(try made.keys.unlock(password: Self.password) == made.userKey)
    }

    @Test
    func `a file's data key opens only under its user key, and only unchanged`() throws {
        let made = try SessionKeys.create(password: Self.password, derivation: Self.quick)
        let dataKey = SymmetricKey(size: .bits256)
        let envelope = try made.keys.envelope(for: dataKey, userKey: made.userKey)
        #expect(try made.keys.dataKey(in: envelope, userKey: made.userKey) == dataKey)
        let other = try SessionKeys.create(password: Self.password, derivation: Self.quick)
        #expect(throws: SessionKeyError.otherUserKey) {
            _ = try other.keys.dataKey(in: envelope, userKey: other.userKey)
        }
        for offset in envelope.indices {
            var changed = envelope
            changed[offset] ^= 0x01
            #expect(throws: SessionKeyError.self, "byte \(offset)") {
                _ = try made.keys.dataKey(in: changed, userKey: made.userKey)
            }
        }
    }
}
