internal import CryptoKit
internal import Testing

@testable import AskGateway

/// What a Noise channel refuses: a changed message, a replayed one, a responder whose key is not the one `IK` expects, and a message
/// out of turn. A refused message moves no state, so the real one still opens.
struct NoiseFailureTests {
    private typealias Key = NoiseHandshake.PrivateKey

    private func pair(_ pattern: NoiseHandshake.Pattern, responder: Key = Key(), expected: Key? = nil) throws -> (
        NoiseHandshake, NoiseHandshake
    ) {
        let initiator = try NoiseHandshake(
            pattern: pattern,
            initiator: true,
            localStatic: Key(),
            remoteStatic: pattern == .ik ? (expected ?? responder).publicKey : nil,
            prologue: Array("ask-gateway/1".utf8)
        )
        let other = try NoiseHandshake(
            pattern: pattern,
            initiator: false,
            localStatic: responder,
            prologue: Array("ask-gateway/1".utf8)
        )
        return (initiator, other)
    }

    private func complete(_ initiator: inout NoiseHandshake, _ responder: inout NoiseHandshake) throws {
        while !initiator.isComplete {
            if initiator.writesNext {
                _ = try responder.readMessage(try initiator.writeMessage())
            } else {
                _ = try initiator.readMessage(try responder.writeMessage())
            }
        }
    }

    @Test func `a changed transport message is refused and the real one still opens`() throws {
        var (initiator, responder) = try pair(.xx)
        try complete(&initiator, &responder)
        var sending = try initiator.transport()
        var receiving = try responder.transport()
        let sealed = try sending.seal(Array("steer".utf8))
        var changed = sealed
        changed[0] ^= 0x01
        #expect(throws: NoiseHandshake.Failure.cipher(.authenticationFailed)) { try receiving.open(changed) }
        #expect(try receiving.open(sealed) == Array("steer".utf8))
        #expect(throws: NoiseHandshake.Failure.cipher(.authenticationFailed)) { try receiving.open(sealed) }
    }

    @Test func `IK to a responder holding another key fails at its first message`() throws {
        var (initiator, responder) = try pair(.ik, responder: Key(), expected: Key())
        let first = try initiator.writeMessage()
        #expect(throws: NoiseHandshake.Failure.cipher(.authenticationFailed)) { try responder.readMessage(first) }
    }

    @Test func `a message out of turn, or after the end, is refused`() throws {
        var (initiator, responder) = try pair(.xx)
        #expect(throws: NoiseHandshake.Failure.wrongTurn) { try responder.writeMessage() }
        try complete(&initiator, &responder)
        #expect(throws: NoiseHandshake.Failure.finished) { try initiator.writeMessage() }
    }

    @Test func `a different prologue fails the handshake`() throws {
        var initiator = try NoiseHandshake(pattern: .xx, initiator: true, localStatic: Key(), prologue: [1])
        var responder = try NoiseHandshake(pattern: .xx, initiator: false, localStatic: Key(), prologue: [2])
        _ = try responder.readMessage(try initiator.writeMessage())
        let second = try responder.writeMessage()
        #expect(throws: NoiseHandshake.Failure.cipher(.authenticationFailed)) { try initiator.readMessage(second) }
    }
}
