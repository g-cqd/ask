package import CryptoKit

/// A node's list of sessions, sealed to each controller key it trusts (`docs/protocol/gateway.md`, "The sealed list"), so the gateway
/// stores and forwards it without reading it. For each controller: its key's fingerprint (8 bytes), the length of what follows (u32,
/// big-endian), and a Noise `N` message to its key whose payload is the list.
package enum SealedList {
    /// Why a list could not be sealed or opened.
    package enum Failure: Error, Equatable {
        case tooLarge, malformed, noControllers, notOpened
    }

    /// The prologue every list's `N` message is bound to.
    static let prologue = Array("ask-gateway/1 list".utf8)

    /// The largest list: a Noise message less the ephemeral key and the tag.
    package static let maximumPayload = 65_535 - 32 - 16

    /// The first 8 bytes of the SHA-256 of a public key: how an entry says whose it is.
    package static func fingerprint(_ key: Curve25519.KeyAgreement.PublicKey) -> [UInt8] {
        Array(SHA256.hash(data: key.rawRepresentation).prefix(8))
    }

    /// `payload` sealed to each of `controllers`, a fresh ephemeral key for each.
    package static func seal(_ payload: [UInt8], to controllers: [Curve25519.KeyAgreement.PublicKey]) throws(Failure)
        -> [UInt8]
    {
        guard !controllers.isEmpty else { throw .noControllers }
        guard payload.count <= maximumPayload else { throw .tooLarge }
        var out: [UInt8] = []
        for controller in controllers {
            do {
                var handshake = try NoiseHandshake(
                    pattern: .n,
                    initiator: true,
                    localStatic: nil,
                    remoteStatic: controller,
                    prologue: prologue
                )
                let message = try handshake.writeMessage(payload: payload)
                out += fingerprint(controller) + RelayBytes.u32(UInt32(message.count)) + message
            } catch {
                throw .malformed
            }
        }
        return out
    }

    /// The list sealed to `key` in `sealed`; ``Failure/notOpened`` when no entry is addressed to it or the one that is does not open.
    package static func open(_ sealed: [UInt8], with key: Curve25519.KeyAgreement.PrivateKey) throws(Failure) -> [UInt8]
    {
        let mine = fingerprint(key.publicKey)
        var rest = sealed[...]
        while !rest.isEmpty {
            guard rest.count >= 12 else { throw .malformed }
            let print = Array(rest.prefix(8))
            let length = Int(RelayBytes.readU32(rest.dropFirst(8).prefix(4)))
            rest = rest.dropFirst(12)
            guard length >= 48, rest.count >= length else { throw .malformed }
            let message = Array(rest.prefix(length))
            rest = rest.dropFirst(length)
            guard print == mine else { continue }
            do {
                var handshake = try NoiseHandshake(pattern: .n, initiator: false, localStatic: key, prologue: prologue)
                return try handshake.readMessage(message)
            } catch {
                throw .notOpened
            }
        }
        throw .notOpened
    }
}
