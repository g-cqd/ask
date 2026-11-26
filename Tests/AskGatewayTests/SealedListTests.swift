internal import CryptoKit
internal import Testing

@testable import AskGateway

/// A node's list, sealed to each trusted controller: each opens its own, a stranger opens none, and a changed byte opens nothing.
struct SealedListTests {
    private typealias Key = Curve25519.KeyAgreement.PrivateKey
    private let list = Array(#"{"sessions":[{"id":"20261126T001752Z-80b4ee4f","name":"ask"}]}"#.utf8)

    @Test func `each trusted controller opens the list, and a stranger opens none`() throws {
        let (first, second, stranger) = (Key(), Key(), Key())
        let sealed = try SealedList.seal(list, to: [first.publicKey, second.publicKey])
        #expect(try SealedList.open(sealed, with: first) == list)
        #expect(try SealedList.open(sealed, with: second) == list)
        #expect(throws: SealedList.Failure.notOpened) { try SealedList.open(sealed, with: stranger) }
    }

    @Test func `a changed byte, or a cut list, opens nothing`() throws {
        let key = Key()
        var sealed = try SealedList.seal(list, to: [key.publicKey])
        sealed[sealed.count - 1] ^= 0x01
        #expect(throws: SealedList.Failure.notOpened) { try SealedList.open(sealed, with: key) }
        #expect(throws: SealedList.Failure.malformed) { try SealedList.open(Array(sealed.prefix(20)), with: key) }
    }

    @Test func `no controller, or too large a list, is refused`() {
        #expect(throws: SealedList.Failure.noControllers) { try SealedList.seal(list, to: []) }
        #expect(throws: SealedList.Failure.tooLarge) {
            try SealedList.seal([UInt8](repeating: 0, count: SealedList.maximumPayload + 1), to: [Key().publicKey])
        }
    }
}
