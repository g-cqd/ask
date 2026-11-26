package import CryptoKit

/// A Noise handshake (revision 34, section 5.3) over `25519_ChaChaPoly_SHA256`, for the patterns ADR-0170 uses: `XX` between a node
/// and the gateway, each learning the other's static key in the handshake; `IK` from a controller to a node whose static key it
/// already holds; and the one-way `N`, which seals a node's list to a controller's key. A handshake is written and read message by message; once its last message is through, ``transport`` gives the
/// two cipher states of the channel.
package struct NoiseHandshake: Sendable {
    /// The patterns ADR-0170 uses.
    package enum Pattern: String, Sendable, CaseIterable {
        case xx = "XX"
        case ik = "IK"
        case n = "N"

        enum Token: Sendable { case e, s, ee, es, se, ss }

        /// The messages' tokens, the initiator's first.
        var messages: [[Token]] {
            switch self {
                case .xx: [[.e], [.e, .ee, .s, .es], [.s, .se]]
                case .ik: [[.e, .es, .s, .ss], [.e, .ee, .se]]
                case .n: [[.e, .es]]
            }
        }

        /// The keys known before the handshake, hashed in order: the responder's static key for `IK` and `N`.
        var respondersStaticIsKnown: Bool { self != .xx }

        /// Whether only the initiator sends, once the handshake is through (section 7.4).
        package var isOneWay: Bool { self == .n }
    }

    /// Why a handshake stopped.
    package enum Failure: Error, Equatable {
        case wrongTurn, finished, malformed, missingKey
        case cipher(NoiseCipherState.Failure)
    }

    package typealias PrivateKey = Curve25519.KeyAgreement.PrivateKey
    package typealias PublicKey = Curve25519.KeyAgreement.PublicKey

    package let pattern: Pattern
    package let isInitiator: Bool
    private var symmetric: NoiseSymmetricState
    private let localStatic: PrivateKey?
    private var localEphemeral: PrivateKey?
    /// The ephemeral a test fixes, used instead of a fresh one; never set outside tests.
    private let fixedEphemeral: PrivateKey?
    package private(set) var remoteStatic: PublicKey?
    private var remoteEphemeral: PublicKey?
    private var index = 0

    /// A handshake about to begin.
    /// - Parameters:
    ///   - pattern: `XX` or `IK`.
    ///   - initiator: whether this side writes the first message.
    ///   - localStatic: this side's static key; nil only for `N`'s initiator, which has none.
    ///   - remoteStatic: the responder's static key, which `IK`'s initiator must know; nil otherwise.
    ///   - prologue: data both sides must agree on, such as the protocol version and the channel's purpose.
    ///   - ephemeral: for test vectors only: the ephemeral key to use.
    /// - Throws: ``Failure/missingKey`` when `IK`'s initiator is given no responder key.
    package init(
        pattern: Pattern,
        initiator: Bool,
        localStatic: PrivateKey?,
        remoteStatic: PublicKey? = nil,
        prologue: [UInt8] = [],
        ephemeral: PrivateKey? = nil
    ) throws(Failure) {
        self.pattern = pattern
        isInitiator = initiator
        self.localStatic = localStatic
        self.remoteStatic = remoteStatic
        fixedEphemeral = ephemeral
        symmetric = NoiseSymmetricState(protocolName: "Noise_\(pattern.rawValue)_25519_ChaChaPoly_SHA256")
        symmetric.mixHash(prologue)
        if pattern.respondersStaticIsKnown {
            let responder = initiator ? remoteStatic : localStatic?.publicKey
            guard let responder else { throw .missingKey }
            symmetric.mixHash(Array(responder.rawRepresentation))
        }
    }

    /// Whether every message has been written or read.
    package var isComplete: Bool { index == pattern.messages.count }

    /// The hash of the whole handshake, the same on both sides once it is complete: a channel binding.
    package var handshakeHash: [UInt8] { symmetric.hash }

    /// Whether the next message is this side's to write.
    package var writesNext: Bool { (index % 2 == 0) == isInitiator }

    /// The next message, carrying `payload` (sealed once a key is mixed in).
    package mutating func writeMessage(payload: [UInt8] = []) throws(Failure) -> [UInt8] {
        guard !isComplete else { throw .finished }
        guard writesNext else { throw .wrongTurn }
        var out: [UInt8] = []
        do {
            for token in pattern.messages[index] {
                switch token {
                    case .e:
                        let key = fixedEphemeral ?? PrivateKey()
                        localEphemeral = key
                        let bytes = Array(key.publicKey.rawRepresentation)
                        out += bytes
                        symmetric.mixHash(bytes)
                    case .s:
                        guard let localStatic else { throw Failure.missingKey }
                        out += try symmetric.encryptAndHash(Array(localStatic.publicKey.rawRepresentation))
                    default: try mixDH(token)
                }
            }
            out += try symmetric.encryptAndHash(payload)
        } catch let failure as NoiseCipherState.Failure {
            throw .cipher(failure)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .malformed
        }
        index += 1
        return out
    }

    /// Reads the other side's next message; returns its payload.
    package mutating func readMessage(_ message: [UInt8]) throws(Failure) -> [UInt8] {
        guard !isComplete else { throw .finished }
        guard !writesNext else { throw .wrongTurn }
        var rest = message[...]
        do {
            for token in pattern.messages[index] {
                switch token {
                    case .e:
                        guard rest.count >= 32 else { throw Failure.malformed }
                        let bytes = Array(rest.prefix(32))
                        rest = rest.dropFirst(32)
                        remoteEphemeral = try PublicKey(rawRepresentation: bytes)
                        symmetric.mixHash(bytes)
                    case .s:
                        let length = symmetric.cipher.hasKey ? 48 : 32
                        guard rest.count >= length else { throw Failure.malformed }
                        let bytes = try symmetric.decryptAndHash(Array(rest.prefix(length)))
                        rest = rest.dropFirst(length)
                        remoteStatic = try PublicKey(rawRepresentation: bytes)
                    default: try mixDH(token)
                }
            }
            let payload = try symmetric.decryptAndHash(Array(rest))
            index += 1
            return payload
        } catch let failure as NoiseCipherState.Failure {
            throw .cipher(failure)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .malformed
        }
    }

    /// The channel's cipher states, once the handshake is complete: what this side sends with, and what it receives with.
    package func transport() throws(Failure) -> NoiseTransport {
        guard isComplete else { throw .wrongTurn }
        let (initiatorSends, responderSends) = symmetric.split()
        // One-way: the responder only receives, and sends nothing (section 7.4).
        return isInitiator
            ? NoiseTransport(sending: initiatorSends, receiving: responderSends, handshakeHash: symmetric.hash)
            : NoiseTransport(sending: responderSends, receiving: initiatorSends, handshakeHash: symmetric.hash)
    }

    /// `ee`, `es`, `se`, `ss`: the agreement the token names, from this side's point of view, mixed into the key.
    private mutating func mixDH(_ token: Pattern.Token) throws {
        let initiatorKey: PrivateKey?
        let responderKey: PublicKey?
        switch (token, isInitiator) {
            case (.ee, _): (initiatorKey, responderKey) = (localEphemeral, remoteEphemeral)
            case (.es, true): (initiatorKey, responderKey) = (localEphemeral, remoteStatic)
            case (.es, false): (initiatorKey, responderKey) = (localStatic, remoteEphemeral)
            case (.se, true): (initiatorKey, responderKey) = (localStatic, remoteEphemeral)
            case (.se, false): (initiatorKey, responderKey) = (localEphemeral, remoteStatic)
            case (.ss, _): (initiatorKey, responderKey) = (localStatic, remoteStatic)
            default: throw Failure.malformed
        }
        guard let initiatorKey, let responderKey else { throw Failure.missingKey }
        let shared = try initiatorKey.sharedSecretFromKeyAgreement(with: responderKey)
        let bytes = shared.withUnsafeBytes { Array($0) }
        // An all-zero result means a low-order point: refused, as RFC 7748 section 6.1 allows.
        guard bytes.contains(where: { $0 != 0 }) else { throw Failure.malformed }
        symmetric.mixKey(bytes)
    }
}
